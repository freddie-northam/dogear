import CoreSpotlight
import DogearKit
import Foundation

/// Owns the setting that governs publishing to Spotlight, and the one writer.
/// The sequencing lives in `SpotlightWriter` in the kit, where it has tests;
/// only the calls into the real system index live here.
enum SpotlightSync {
    static let defaultsKey = "spotlightIndexing"

    /// On unless the user says otherwise. The index never leaves the Mac.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    private static let writer = SpotlightWriter(index: SystemSpotlightIndex())

    /// Republishes the library when what Spotlight holds no longer matches it.
    /// The caller hands over the bookmarks and nothing else: hashing them takes
    /// about 7 ms at 5,000 records and happens on every debounced sync, so it
    /// belongs off the main actor rather than in front of this call.
    static func replaceAll(with bookmarks: [Bookmark]) {
        Task { await writer.write(bookmarks) }
    }

    /// Removes every Dogear item, for the moment the user turns the setting off.
    static func removeAll() {
        Task { await writer.clear() }
    }
}

/// The real system index.
///
/// This deliberately does not use CoreSpotlight's batch mode. Batch mode is the
/// only way to store a stamp inside the index itself, and that is what Dogear
/// first reached for, but `beginIndexBatch` raises and takes the app down a few
/// seconds after launch. The stamp does not need Apple's storage: it is one
/// string that says what was last published, and a default holds it.
///
/// ponytail: the stamp lives beside the app rather than beside the index, so a
/// Spotlight purge is invisible here and the items stay missing until something
/// changes or the user toggles the setting. Move the stamp back into the index
/// if batch mode ever works for an app signed like this one.
private struct SystemSpotlightIndex: SpotlightIndexing {
    static let stampKey = "spotlightFingerprint"

    private var index: CSSearchableIndex { .default() }

    func lastStamp() async -> Data? {
        UserDefaults.standard.data(forKey: Self.stampKey)
    }

    func deleteEverything() async {
        await withCheckedContinuation { continuation in
            index.deleteSearchableItems(withDomainIdentifiers: [SpotlightIndex.domain]) { _ in
                continuation.resume()
            }
        }
    }

    func publish(_ items: [CSSearchableItem], stamp: Data) async {
        let index = index
        // Spotlight asks for batches of items rather than one huge call. This
        // is chunking, not CoreSpotlight's batch mode.
        for chunk in stride(from: 0, to: items.count, by: 500) {
            let slice = Array(items[chunk..<min(chunk + 500, items.count)])
            let failed = await withCheckedContinuation { continuation in
                index.indexSearchableItems(slice) { error in
                    continuation.resume(returning: error != nil)
                }
            }
            // Record nothing on failure, so the next run tries again rather
            // than trusting a stamp for items that never landed.
            if failed { return }
        }
        await recordStamp(stamp)
    }

    func recordStamp(_ stamp: Data) async {
        UserDefaults.standard.set(stamp, forKey: Self.stampKey)
    }
}
