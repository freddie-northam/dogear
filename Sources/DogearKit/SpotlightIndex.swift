import CoreSpotlight
import CryptoKit
import Foundation

/// Describes a bookmark to Spotlight.
public enum SpotlightIndex {
    /// Every item Dogear writes carries this domain, so one call clears them
    /// all and nothing else in Spotlight is touched.
    public static let domain = "app.dogear.bookmarks"

    public static func attributes(for bookmark: Bookmark) -> CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .url)
        attributes.title = bookmark.title
        attributes.contentDescription = bookmark.subtitle ?? bookmark.url
        attributes.keywords = [bookmark.folder, bookmark.author].compactMap { $0 }
        attributes.identifier = bookmark.id.uuidString
        return attributes
    }

    /// Identifies exactly what was last published.
    /// Covers only the fields that `attributes(for:)` reads.
    /// A mark-done or a new `lastShownAt` changes no search result, so it does not force a rebuild.
    /// SHA256, not Hasher: Swift seeds Hasher randomly per process, so its
    /// value would differ on every launch and the comparison this exists for
    /// would never match.
    public static func fingerprint(_ bookmarks: [Bookmark]) -> String {
        var digest = SHA256()
        for bookmark in bookmarks {
            for field in [bookmark.id.uuidString, bookmark.title, bookmark.subtitle ?? "",
                          bookmark.folder, bookmark.author ?? "", bookmark.url] {
                digest.update(data: Data(field.utf8))
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
