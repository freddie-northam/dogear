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
    public let createdAt: Date
    public var doneAt: Date?
    public var hasThumbnail: Bool
    public var manuallyFiled: Bool
    // Optional like doneAt: synthesized Codable decodes a missing key as nil,
    // so libraries written before this field load unchanged.
    public var favoritedAt: Date?
    /// When the pick row last showed this bookmark. Optional for the same
    /// reason as favoritedAt: an older library file must still load.
    public var lastShownAt: Date?

    public init(id: UUID, url: String, title: String, author: String?, note: String?,
                folder: String, source: Source, createdAt: Date, doneAt: Date?,
                hasThumbnail: Bool, manuallyFiled: Bool, favoritedAt: Date? = nil,
                lastShownAt: Date? = nil) {
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
    }

    public var isDone: Bool { doneAt != nil }
    public var isFavorite: Bool { favoritedAt != nil }
}

extension Bookmark {
    /// A `[title](<url>)` markdown link. Square brackets in the title become
    /// parentheses, and newlines/control characters collapse to single spaces,
    /// so the link text cannot break the markdown syntax or the line structure
    /// of an exported list. The URL is wrapped in CommonMark's angle-bracket
    /// delimiters so a `)` or space inside the URL cannot terminate the link
    /// early, without altering the URL itself.
    public var markdownLink: String {
        // Splitting on newlines/control characters yields an empty component
        // for each run of them; dropping the empties before rejoining is what
        // collapses a run to a single space instead of one space per character.
        let flattenedTitle = title
            .components(separatedBy: .newlines.union(.controlCharacters))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let safeTitle = flattenedTitle
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
        return "[\(safeTitle)](<\(url)>)"
    }

    /// A markdown bullet list, one `- [title](url)` line per bookmark.
    public static func markdownList(_ bookmarks: [Bookmark]) -> String {
        bookmarks.map { "- \($0.markdownLink)" }.joined(separator: "\n")
    }
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
