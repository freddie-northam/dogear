import Foundation

public enum Source: String, Codable, Sendable {
    case tiktok, x, web
}

public struct Bookmark: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var url: String
    public var title: String
    public var author: String?
    public var note: String?
    public var folder: String
    public var source: Source
    public var createdAt: Date
    public var doneAt: Date?
    public var hasThumbnail: Bool
    public var manuallyFiled: Bool
    // Optional like doneAt: synthesized Codable decodes a missing key as nil,
    // so libraries written before this field load unchanged.
    public var favoritedAt: Date?
    /// When the pick row last showed this bookmark. Optional for the same
    /// reason as favoritedAt: an older library file must still load.
    public var lastShownAt: Date?
    /// Set when the bookmark stands for a place on the map instead of a page
    /// on the web. Optional, so an older library file still loads.
    public var place: Place?

    public init(id: UUID, url: String, title: String, author: String?, note: String?,
                folder: String, source: Source, createdAt: Date, doneAt: Date?,
                hasThumbnail: Bool, manuallyFiled: Bool, favoritedAt: Date? = nil,
                lastShownAt: Date? = nil, place: Place? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.author = author
        self.note = note
        self.folder = folder
        self.source = source
        self.createdAt = createdAt
        self.doneAt = doneAt
        self.hasThumbnail = hasThumbnail
        self.manuallyFiled = manuallyFiled
        self.favoritedAt = favoritedAt
        self.lastShownAt = lastShownAt
        self.place = place
    }

    public var isDone: Bool { doneAt != nil }
    public var isFavorite: Bool { favoritedAt != nil }
    public var isPlace: Bool { place != nil }
}

extension String {
    /// The text on one line: newlines and control characters collapse to
    /// single spaces. Splitting yields an empty component for each one, so
    /// dropping the empties turns a run into a single space rather than one
    /// space per character.
    var singleLine: String {
        components(separatedBy: .newlines.union(.controlCharacters))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

extension Bookmark {
    /// Where to open this bookmark on a map, or nil when it is not a place at
    /// all. A resolved place goes to its own coordinates. A link the user
    /// copied out of Maps opens itself. Everything else has no honest answer,
    /// so the app offers nothing rather than guessing from the title.
    public var mapsURL: URL? {
        if let place { return place.mapsURL }
        guard let url = URL(string: url), Place.isMapHost(url) else { return nil }
        return url
    }

    /// The line under the title. A place the user has not written a note on
    /// still has something to say: where it is.
    public var subtitle: String? { note ?? place?.address }

    /// A `[title](<url>)` markdown link. Square brackets in the title become
    /// parentheses, and newlines/control characters collapse to single spaces,
    /// so the link text cannot break the markdown syntax or the line structure
    /// of an exported list. The URL is wrapped in CommonMark's angle-bracket
    /// delimiters so a `)` or space inside the URL cannot terminate the link
    /// early, without altering the URL itself.
    public var markdownLink: String {
        let safeTitle = title.singleLine
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
        return "[\(safeTitle)](<\(url)>)"
    }

    /// A markdown bullet list, one `- [title](url)` line per bookmark.
    public static func markdownList(_ bookmarks: [Bookmark]) -> String {
        bookmarks.map { "- \($0.markdownLink)" }.joined(separator: "\n")
    }
}

extension Library {
    /// The library as an export sees it: one section per folder in the user's
    /// own order, empty folders dropped, and the archive last. Both exporters
    /// walked this shape themselves and had to agree by hand; a bookmark that
    /// is done leaves its folder section in the app, and it must leave it in a
    /// file too.
    public var exportSections: [(name: String, bookmarks: [Bookmark])] {
        var sections = folders.compactMap { folder -> (name: String, bookmarks: [Bookmark])? in
            let items = bookmarks.filter { $0.folder == folder && !$0.isDone }
            return items.isEmpty ? nil : (name: folder, bookmarks: items)
        }
        let archived = bookmarks.filter(\.isDone)
        if !archived.isEmpty { sections.append((name: Library.archiveName, bookmarks: archived)) }
        return sections
    }

    /// The heading a done bookmark files under in an export.
    public static let archiveName = "Archive"
}

public struct Library: Codable, Equatable, Sendable {
    public var folders: [String]
    public var bookmarks: [Bookmark]
    // Optional like Bookmark.favoritedAt: synthesized Codable decodes a missing
    // key as nil, so libraries written before this field load unchanged.
    public var schemaVersion: Int?

    public static let defaultFolders = ["Recipes", "Restaurants", "Shows", "Music", "Articles", "Unsorted"]
    public static let unsorted = "Unsorted"
    public static let currentSchemaVersion = 2

    public init(folders: [String], bookmarks: [Bookmark], schemaVersion: Int? = nil) {
        self.folders = folders
        self.bookmarks = bookmarks
        self.schemaVersion = schemaVersion
    }
}
