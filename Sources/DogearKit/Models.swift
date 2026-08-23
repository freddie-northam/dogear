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

    public init(id: UUID, url: String, title: String, author: String?, note: String?,
                folder: String, source: Source, createdAt: Date, doneAt: Date?,
                hasThumbnail: Bool, manuallyFiled: Bool) {
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
    }

    public var isDone: Bool { doneAt != nil }
}

public struct Library: Codable, Equatable, Sendable {
    public var folders: [String]
    public var bookmarks: [Bookmark]

    public static let defaultFolders = ["Recipes", "Restaurants", "Shows", "Articles", "Unsorted"]
    public static let unsorted = "Unsorted"

    public init(folders: [String], bookmarks: [Bookmark]) {
        self.folders = folders
        self.bookmarks = bookmarks
    }
}
