import CoreSpotlight
import DogearKit
import Foundation

/// Writes the library into the system search index, and owns the setting that
/// governs it. This lives in the app, not the kit, for the same reason
/// `MapKitPlaceResolver` does: `CSSearchableIndex.default()` writes the real
/// index of whoever runs it and takes no stand-in, so the file could carry no
/// test. `SpotlightIndex` in the kit builds the descriptions and is tested.
enum SpotlightSync {
    static let defaultsKey = "spotlightIndexing"

    /// On unless the user says otherwise. The index never leaves the Mac.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// Republishes the library when what Spotlight holds no longer matches it.
    /// The caller hands over the bookmarks and nothing else: hashing them takes
    /// about 7 ms at 5,000 records, and it happens on every debounced sync
    /// including the ones where nothing changed, so it belongs off the main
    /// actor rather than in front of this call.
    static func replaceAll(with bookmarks: [Bookmark]) {
        Task { await SpotlightWriter.shared.write(bookmarks) }
    }

    /// Removes every Dogear item, for the moment the user turns the setting off.
    static func removeAll() {
        Task { await SpotlightWriter.shared.clear() }
    }
}

/// Serializes every write to the search index.
///
/// CoreSpotlight is explicit that `beginBatch` must not be called again before
/// the previous `endIndexBatch` has returned, and that concurrent calls to one
/// index instance have undefined results. Dogear writes from three places, and
/// the debounce upstream does not prevent overlap: indexing a large library can
/// outlast it, and the Settings toggle writes directly. An actor with an
/// explicit in-flight flag is what makes those three callers one at a time.
actor SpotlightWriter {
    static let shared = SpotlightWriter()

    private let index = CSSearchableIndex.default()
    private var isWriting = false
    /// The newest request that arrived while a write was running. Holding the
    /// newest, rather than dropping it, is what stops the index settling one
    /// version behind the library while its stamp claims to be current.
    private var queued: (bookmarks: [Bookmark], fingerprint: String)?

    func write(_ bookmarks: [Bookmark]) async {
        let fingerprint = SpotlightIndex.fingerprint(bookmarks)
        guard !isWriting else {
            queued = (bookmarks, fingerprint)
            return
        }
        isWriting = true
        defer { isWriting = false }
        await publish(bookmarks, fingerprint: fingerprint)
        // An await above lets another caller in; it parks its request here
        // rather than opening a second batch, so drain before finishing.
        while let next = queued {
            queued = nil
            await publish(next.bookmarks, fingerprint: next.fingerprint)
        }
    }

    func clear() async {
        guard !isWriting else {
            // A clear beats a queued publish: the user just turned the setting
            // off, and republishing after that would be wrong.
            queued = nil
            return
        }
        isWriting = true
        defer { isWriting = false }
        await deleteEverything()
        await stamp(Data())
    }

    /// Rebuilds only when the stamp Spotlight holds no longer matches the
    /// library. Spotlight keeps that stamp beside the index and hands it back,
    /// so it survives a relaunch: that is what stops a login-item app from
    /// rewriting the whole system index once per session for a library nobody
    /// changed. A purged index returns no stamp, which reads as a mismatch and
    /// rebuilds, so the repair path costs nothing extra.
    private func publish(_ bookmarks: [Bookmark], fingerprint: String) async {
        let published = await lastStamp().flatMap { String(data: $0, encoding: .utf8) }
        guard published != fingerprint else { return }
        await deleteEverything()
        await withCheckedContinuation { continuation in
            index.beginBatch()
            // Spotlight asks for batches rather than one huge call.
            for chunk in stride(from: 0, to: bookmarks.count, by: 500) {
                let slice = bookmarks[chunk..<min(chunk + 500, bookmarks.count)]
                index.indexSearchableItems(slice.map(SpotlightIndex.item(for:)))
            }
            // No expected-state check: this actor is the only writer and it
            // runs one write at a time, so a compare here could only fail for
            // reasons nothing could act on, and it would fail silently.
            index.endIndexBatch(expectedClientState: nil,
                                newClientState: Data(fingerprint.utf8)) { _ in
                continuation.resume()
            }
        }
    }

    private func stamp(_ state: Data) async {
        await withCheckedContinuation { continuation in
            index.beginBatch()
            index.endIndexBatch(expectedClientState: nil, newClientState: state) { _ in
                continuation.resume()
            }
        }
    }

    private func deleteEverything() async {
        await withCheckedContinuation { continuation in
            index.deleteSearchableItems(withDomainIdentifiers: [SpotlightIndex.domain]) { _ in
                continuation.resume()
            }
        }
    }

    private func lastStamp() async -> Data? {
        await withCheckedContinuation { continuation in
            index.fetchLastClientState { state, _ in continuation.resume(returning: state) }
        }
    }
}
