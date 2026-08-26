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

/// The real system index. Each call wraps one CoreSpotlight completion handler
/// and nothing else, so there is no logic here to leave untested.
private struct SystemSpotlightIndex: SpotlightIndexing {
    private var index: CSSearchableIndex { .default() }

    func lastStamp() async -> Data? {
        await withCheckedContinuation { continuation in
            index.fetchLastClientState { state, _ in continuation.resume(returning: state) }
        }
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
        await withCheckedContinuation { continuation in
            index.beginBatch()
            // Spotlight asks for batches rather than one huge call.
            for chunk in stride(from: 0, to: items.count, by: 500) {
                index.indexSearchableItems(Array(items[chunk..<min(chunk + 500, items.count)]))
            }
            index.endIndexBatch(expectedClientState: nil, newClientState: stamp) { _ in
                continuation.resume()
            }
        }
    }

    func recordStamp(_ stamp: Data) async {
        let index = index
        await withCheckedContinuation { continuation in
            index.beginBatch()
            index.endIndexBatch(expectedClientState: nil, newClientState: stamp) { _ in
                continuation.resume()
            }
        }
    }
}
