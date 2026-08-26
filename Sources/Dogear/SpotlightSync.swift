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

    /// Republishes the library when what Spotlight holds no longer matches
    /// it. Spotlight keeps a small piece of client state beside the index and
    /// hands it back, so the fingerprint of the last publish survives a
    /// relaunch. That is what stops a login-item app from rewriting the whole
    /// system index once per session for a library nobody changed.
    ///
    /// The same state repairs a purged index for free: a system that has
    /// dropped Dogear's items returns no state, which reads as a mismatch and
    /// triggers a full rebuild.
    static func replaceAll(with bookmarks: [Bookmark]) {
        let index = CSSearchableIndex.default()
        let fingerprint = SpotlightIndex.fingerprint(bookmarks)
        index.fetchLastClientState { state, _ in
            let published = state.flatMap { String(data: $0, encoding: .utf8) }
            guard published != fingerprint else { return }
            rebuild(bookmarks, fingerprint: fingerprint, replacing: state, in: index)
        }
    }

    private static func rebuild(_ bookmarks: [Bookmark], fingerprint: String,
                                replacing expected: Data?, in index: CSSearchableIndex) {
        index.deleteSearchableItems(withDomainIdentifiers: [SpotlightIndex.domain]) { _ in
            index.beginBatch()
            // Spotlight asks for batches rather than one huge call.
            for chunk in stride(from: 0, to: bookmarks.count, by: 500) {
                let slice = bookmarks[chunk..<min(chunk + 500, bookmarks.count)]
                index.indexSearchableItems(slice.map(SpotlightIndex.item(for:)))
            }
            // Stamping the state last means an interrupted rebuild leaves the
            // old stamp, and the next launch tries again rather than trusting
            // a half-written index.
            // The state we read is what this rebuild replaces, so a second
            // rebuild that raced this one does not have its stamp overwritten.
            index.endIndexBatch(expectedClientState: expected,
                                newClientState: Data(fingerprint.utf8),
                                completionHandler: nil)
        }
    }

    /// Removes every Dogear item, for the moment the user turns the setting
    /// off. The stamp is cleared too, so turning the setting back on rebuilds
    /// rather than trusting a fingerprint whose items are gone.
    static func removeAll() {
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [SpotlightIndex.domain]) { _ in
            index.beginBatch()
            index.endIndexBatch(expectedClientState: nil, newClientState: Data(),
                                completionHandler: nil)
        }
    }
}
