import CoreSpotlight
import DogearKit
import Foundation

enum SpotlightSync {
    static let defaultsKey = "spotlightIndexing"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    private static let writer = SpotlightWriter(index: SystemSpotlightIndex())

    static func replaceAll(with bookmarks: [Bookmark]) {
        Task { await writer.write(bookmarks) }
    }

    static func removeAll() {
        Task { await writer.clear() }
    }
}

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
        for chunk in stride(from: 0, to: items.count, by: 500) {
            let slice = Array(items[chunk..<min(chunk + 500, items.count)])
            let failed = await withCheckedContinuation { continuation in
                index.indexSearchableItems(slice) { error in
                    continuation.resume(returning: error != nil)
                }
            }
            if failed { return }
        }
        await recordStamp(stamp)
    }

    func recordStamp(_ stamp: Data) async {
        UserDefaults.standard.set(stamp, forKey: Self.stampKey)
    }
}
