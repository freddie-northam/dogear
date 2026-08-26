import CoreSpotlight
import CryptoKit
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

    /// Identifies exactly what was last published. Spotlight stores this
    /// beside the index and hands it back, so a rebuild can be skipped when
    /// nothing a search could match has changed. Covers only the fields
    /// `attributes(for:)` reads: a mark-done or a new lastShownAt does not
    /// change what Spotlight would return, so it must not force a rebuild.
    /// SHA256, not Hasher: Swift seeds Hasher randomly per process, so its
    /// value would differ on every launch and the comparison this exists for
    /// would never match.
    public static func fingerprint(_ bookmarks: [Bookmark]) -> String {
        var digest = SHA256()
        for bookmark in bookmarks {
            for field in [bookmark.id.uuidString, bookmark.title, bookmark.subtitle ?? "",
                          bookmark.folder, bookmark.author ?? "", bookmark.url] {
                digest.update(data: Data(field.utf8))
                // A separator, so "ab" + "c" cannot hash as "a" + "bc".
                digest.update(data: Data([0]))
            }
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
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
