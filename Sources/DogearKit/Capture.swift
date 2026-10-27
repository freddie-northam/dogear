import Foundation

/// The one way a web link enters the library.
/// The source of a capture decides what happens to a link that is already saved, and what the user reads.
@MainActor
public final class Capture {
    /// Where the links come from.
    public enum Source: Sendable {
        /// Text the user saved on purpose: the popover, a paste, the shortcut, the Services item, or the Shortcuts action.
        /// A link already saved moves to the top and leaves the archive.
        case text(String)
        /// Links dropped on the library window. A card dragged over its own window must not move.
        case drop([URL])
        /// The bodies of Apple Notes. `incremental` means the read covered only notes changed since the last import.
        case notes(html: String, incremental: Bool, unreadFolders: Int)
        /// A bookmarks file from a browser, or a Dogear export.
        case bookmarksFile(html: String)
    }

    /// What one capture did. Every count is of distinct links.
    public struct Outcome {
        /// The new bookmarks, in the order they appeared.
        public let new: [Bookmark]
        public let alreadySaved: Int
        /// The sentence for the user. Nil means the caller shows nothing.
        public let summary: String?
        /// Enrichment of the new bookmarks. Nil when nothing is new.
        public let enrichment: Task<Void, Never>?

        public var found: Int { new.count + alreadySaved }
        /// True when the save added exactly one new link and nothing else, so the popover closes.
        public var savedOneNewLink: Bool { found == 1 && new.count == 1 }
    }

    /// Background jobs that run at once, so a big import does not open one fetch per link.
    public static let maxInFlight = 4

    private let store: BookmarkStore
    private let enrich: @MainActor @Sendable (UUID) async -> Void

    public init(store: BookmarkStore, enrich: @escaping @MainActor @Sendable (UUID) async -> Void) {
        self.store = store
        self.enrich = enrich
    }

    @discardableResult
    public func save(_ source: Source) -> Outcome {
        let (urls, duplicates): ([URL], DuplicatePolicy) = switch source {
        case .text(let text): (URLCleaner.allHTTPURLs(in: text), .resave)
        case .drop(let urls): (urls, .skip)
        case .notes(let html, _, _): (URLCleaner.allHTTPURLs(inHTML: html), .skip)
        case .bookmarksFile(let html): (BookmarksHTML.links(in: html), .skip)
        }
        let added = store.add(urls: urls, duplicates: duplicates)
        return Outcome(
            new: added.new,
            alreadySaved: added.existing.count,
            summary: Self.summary(for: source, new: added.new.count, alreadySaved: added.existing.count),
            enrichment: added.new.isEmpty ? nil
                : Task { [enrich, ids = added.new.map(\.id)] in _ = await boundedMap(ids, limit: Self.maxInFlight, enrich) }
        )
    }

    private static func summary(for source: Source, new: Int, alreadySaved: Int) -> String? {
        let found = new + alreadySaved
        switch source {
        case .drop:
            return nil
        case .text:
            if found == 0 { return "That is not a web link. Dogear saves http and https links." }
            if found > 1 { return new == 0 ? "All \(found) were already saved." : "Saved \(found) links." }
            return new == 1 ? nil : "Already saved. It moved to the top of the library."
        case .notes(_, let incremental, let unreadFolders):
            let message = found > 0 ? imported(new: new, alreadySaved: alreadySaved)
                : incremental ? "No new links since your last import." : "No links found in your notes."
            switch unreadFolders {
            case 0: return message
            case 1: return message + " Dogear could not read 1 folder."
            default: return message + " Dogear could not read \(unreadFolders) folders."
            }
        case .bookmarksFile:
            return found > 0 ? imported(new: new, alreadySaved: alreadySaved) : "No links found in that file."
        }
    }

    private static func imported(new: Int, alreadySaved: Int) -> String {
        if new == 0 {
            return alreadySaved == 1 ? "This link was already saved." : "All \(alreadySaved) links were already saved."
        }
        let message = new == 1 ? "Imported 1 link." : "Imported \(new) links."
        switch alreadySaved {
        case 0: return message
        case 1: return message + " 1 was already saved."
        default: return message + " \(alreadySaved) were already saved."
        }
    }
}
