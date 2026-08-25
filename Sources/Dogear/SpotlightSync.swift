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

    /// Replaces everything Dogear published with the current library. A full
    /// rebuild is what keeps a deleted or renamed bookmark from lingering in
    /// system search, and it repairs an index the system has purged.
    /// ponytail: rebuilds the whole domain on each run, including once per
    /// launch. Move to CSSearchableIndex's client-state API if a large library
    /// ever makes the rebuild show.
    static func replaceAll(with bookmarks: [Bookmark]) {
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [SpotlightIndex.domain]) { _ in
            // Spotlight asks for batches rather than one huge call.
            for chunk in stride(from: 0, to: bookmarks.count, by: 500) {
                let slice = bookmarks[chunk..<min(chunk + 500, bookmarks.count)]
                index.indexSearchableItems(slice.map(SpotlightIndex.item(for:)))
            }
        }
    }

    /// Removes every Dogear item, for the moment the user turns the setting off.
    static func removeAll() {
        CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: [SpotlightIndex.domain])
    }
}
