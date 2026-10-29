import AppIntents
import DogearKit
import Foundation

extension AppModel {
    /// The running library. An intent can start before the app finishes launching, so it waits up to 2 s.
    @MainActor static func ready() async throws -> AppModel {
        for _ in 0..<20 {
            if let model = AppModel.shared { return model }
            try? await Task.sleep(for: .milliseconds(100))
        }
        throw SaveLinkError.libraryUnavailable
    }
}

struct BookmarkEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Bookmark"
    static var defaultQuery = BookmarkQuery()

    let id: UUID

    @Property(title: "Title")
    var title: String

    @Property(title: "Folder")
    var folder: String

    @Property(title: "Link")
    var url: URL?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(folder)")
    }

    init(_ bookmark: Bookmark) {
        id = bookmark.id
        title = bookmark.title
        folder = bookmark.folder
        url = URL(string: bookmark.url)
    }
}

struct BookmarkQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [BookmarkEntity] {
        let store = try await AppModel.ready().store
        return store.library.bookmarks.filter { identifiers.contains($0.id) }.map(BookmarkEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [BookmarkEntity] {
        let store = try await AppModel.ready().store
        return store.search(string).prefix(20).map(BookmarkEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [BookmarkEntity] {
        let store = try await AppModel.ready().store
        return store.waiting().prefix(20).map(BookmarkEntity.init)
    }
}

struct FolderOptions: DynamicOptionsProvider {
    @MainActor
    func results() async throws -> [String] {
        try await AppModel.ready().store.library.folders
    }
}

extension BookmarkStore {
    /// A folder name from a Shortcuts text action can be any string, so each action checks it here.
    func requireFolder(_ name: String) throws {
        guard library.folders.contains(name) else { throw SaveLinkError.noSuchFolder(name) }
    }

    func requireBookmark(_ entity: BookmarkEntity) throws {
        guard library.bookmarks.contains(where: { $0.id == entity.id }) else {
            throw SaveLinkError.noSuchBookmark
        }
    }
}

struct GetPickIntent: AppIntent {
    static var title: LocalizedStringResource = "Get a Pick from Dogear"
    static var description = IntentDescription(
        "Gives you one waiting bookmark, the same way the popover chooses one. Choose a folder to pick only from it.")
    static var openAppWhenRun = false

    @Parameter(title: "Folder", optionsProvider: FolderOptions())
    var folder: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<BookmarkEntity?> {
        let store = try await AppModel.ready().store
        if let folder { try store.requireFolder(folder) }
        guard let bookmark = store.pick(in: folder) else { return .result(value: nil) }
        // The popover reads the same field, so both places agree on what the user has seen.
        store.markShown(id: bookmark.id)
        return .result(value: BookmarkEntity(bookmark))
    }
}

struct FindBookmarksIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Bookmarks in Dogear"
    static var description = IntentDescription(
        "Finds saved bookmarks whose title, note, author or link contains the text.")
    static var openAppWhenRun = false

    @Parameter(title: "Text")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[BookmarkEntity]> {
        let store = try await AppModel.ready().store
        return .result(value: store.search(text).prefix(50).map(BookmarkEntity.init))
    }
}

struct MarkBookmarkDoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark Bookmark Done"
    static var description = IntentDescription("Moves a bookmark to the Archive.")
    static var openAppWhenRun = false

    @Parameter(title: "Bookmark")
    var bookmark: BookmarkEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = try await AppModel.ready().store
        try store.requireBookmark(bookmark)
        store.markDone(id: bookmark.id)
        return .result()
    }
}

struct MoveBookmarkIntent: AppIntent {
    static var title: LocalizedStringResource = "Move Bookmark to Folder"
    static var description = IntentDescription("Moves a bookmark to another folder.")
    static var openAppWhenRun = false

    @Parameter(title: "Bookmark")
    var bookmark: BookmarkEntity

    @Parameter(title: "Folder", optionsProvider: FolderOptions())
    var folder: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = try await AppModel.ready().store
        try store.requireFolder(folder)
        try store.requireBookmark(bookmark)
        store.refile(id: bookmark.id, to: folder)
        return .result()
    }
}
