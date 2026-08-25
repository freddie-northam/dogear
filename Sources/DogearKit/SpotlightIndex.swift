import CoreSpotlight
import Foundation

/// Publishes the library to Spotlight, so a saved link comes back from the
/// system search field without opening Dogear. The index is a copy the system
/// owns and Dogear can rebuild at any time; the JSON library stays the only
/// source of truth.
public enum SpotlightIndex {
    /// Every item Dogear writes carries this domain, so one call clears them
    /// all and nothing else in Spotlight is touched.
    public static let domain = "app.dogear.bookmarks"

    public static func attributes(for bookmark: Bookmark) -> CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .url)
        attributes.title = bookmark.title
        // What the user would recognize: their own note first, then the
        // address of a place, then the link itself.
        attributes.contentDescription = bookmark.note
            ?? bookmark.place?.address
            ?? bookmark.url
        attributes.keywords = [bookmark.folder, bookmark.author].compactMap { $0 }
        attributes.identifier = bookmark.id.uuidString
        return attributes
    }

    public static func item(for bookmark: Bookmark) -> CSSearchableItem {
        let item = CSSearchableItem(
            uniqueIdentifier: bookmark.id.uuidString,
            domainIdentifier: domain,
            attributeSet: attributes(for: bookmark)
        )
        // Spotlight drops an item after a month unless it is told otherwise,
        // and a saved link is meant to keep.
        item.expirationDate = .distantFuture
        return item
    }

    /// Replaces everything Dogear published with the current library. A full
    /// rebuild is what keeps a deleted or renamed bookmark from lingering in
    /// system search.
    /// ponytail: rebuilds the whole domain on each run; index the difference
    /// if a library ever grows large enough for this to show.
    public static func replaceAll(with bookmarks: [Bookmark],
                                  in index: CSSearchableIndex = .default()) {
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            // Spotlight asks for batches rather than one huge call.
            for chunk in stride(from: 0, to: bookmarks.count, by: 500) {
                let slice = bookmarks[chunk..<min(chunk + 500, bookmarks.count)]
                index.indexSearchableItems(slice.map(item(for:)))
            }
        }
    }

    /// Removes every Dogear item, for the moment the user turns the setting off.
    public static func removeAll(in index: CSSearchableIndex = .default()) {
        index.deleteSearchableItems(withDomainIdentifiers: [domain])
    }
}
