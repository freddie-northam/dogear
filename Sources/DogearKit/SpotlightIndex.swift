import CoreSpotlight
import Foundation

/// Describes a bookmark to Spotlight. Building the description is pure and
/// tested here; writing it to the system index is a side effect with no
/// stand-in, so that half lives in the app beside `DockPresence`.
public enum SpotlightIndex {
    /// Every item Dogear writes carries this domain, so one call clears them
    /// all and nothing else in Spotlight is touched.
    public static let domain = "app.dogear.bookmarks"

    public static func attributes(for bookmark: Bookmark) -> CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .url)
        attributes.title = bookmark.title
        // What the user would recognize: their own note, or the address of a
        // place, and the link itself when there is neither.
        attributes.contentDescription = bookmark.subtitle ?? bookmark.url
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
}
