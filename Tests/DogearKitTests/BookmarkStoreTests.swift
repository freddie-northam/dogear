import Foundation
import Testing
@testable import DogearKit

private func tempDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("dogear-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func startsEmptyWithDefaultFolders() throws {
    let store = try BookmarkStore(directory: tempDir())
    #expect(store.library.folders == Library.defaultFolders)
    #expect(store.library.bookmarks.isEmpty)
}

@Test func addPersistsAcrossReload() throws {
    let dir = tempDir()
    let store = try BookmarkStore(directory: dir)
    let (bookmark, isNew) = store.add(url: URL(string: "https://example.com/a")!)
    #expect(isNew)
    #expect(bookmark.folder == Library.unsorted)
    let reloaded = try BookmarkStore(directory: dir)
    #expect(reloaded.library.bookmarks.map(\.id) == [bookmark.id])
}

@Test func addDedupesOnCanonicalURL() throws {
    let store = try BookmarkStore(directory: tempDir())
    let (first, _) = store.add(url: URL(string: "https://a.com/p?utm_source=x")!)
    let (second, isNew) = store.add(url: URL(string: "https://A.com/p/")!)
    #expect(!isNew)
    #expect(second.id == first.id)
    #expect(store.library.bookmarks.count == 1)
}

@Test func reAddBumpsToTopOfFolderListing() throws {
    let store = try BookmarkStore(directory: tempDir())
    let (first, _) = store.add(url: URL(string: "https://a.com/1")!)
    let (second, _) = store.add(url: URL(string: "https://a.com/2")!)
    let (bumped, isNew) = store.add(url: URL(string: "https://a.com/1")!)
    #expect(!isNew)
    #expect(bumped.id == first.id)
    #expect(store.bookmarks(in: Library.unsorted).map(\.id) == [first.id, second.id])
}

@Test func doneMovesToArchiveAndBack() throws {
    let store = try BookmarkStore(directory: tempDir())
    let (bookmark, _) = store.add(url: URL(string: "https://a.com/1")!)
    store.markDone(id: bookmark.id)
    #expect(store.bookmarks(in: Library.unsorted).isEmpty)
    #expect(store.archive().map(\.id) == [bookmark.id])
    store.markUndone(id: bookmark.id)
    #expect(store.bookmarks(in: Library.unsorted).map(\.id) == [bookmark.id])
    #expect(store.archive().isEmpty)
}

@Test func refileSetsManuallyFiled() throws {
    let store = try BookmarkStore(directory: tempDir())
    let (bookmark, _) = store.add(url: URL(string: "https://a.com/1")!)
    store.refile(id: bookmark.id, to: "Recipes")
    let updated = store.library.bookmarks[0]
    #expect(updated.folder == "Recipes")
    #expect(updated.manuallyFiled)
}

@Test func removeFolderMovesBookmarksToUnsorted() throws {
    let store = try BookmarkStore(directory: tempDir())
    let (bookmark, _) = store.add(url: URL(string: "https://a.com/1")!)
    store.refile(id: bookmark.id, to: "Recipes")
    store.removeFolder("Recipes")
    #expect(!store.library.folders.contains("Recipes"))
    #expect(store.library.bookmarks[0].folder == Library.unsorted)
}

@Test func searchMatchesTitleAuthorURLIncludingArchive() throws {
    let store = try BookmarkStore(directory: tempDir())
    let (a, _) = store.add(url: URL(string: "https://a.com/pasta")!)
    var updated = store.library.bookmarks[0]
    updated.title = "Creamy garlic pasta"
    updated.author = "Gordon"
    store.update(updated)
    store.markDone(id: a.id)
    #expect(store.search("pasta").count == 1)
    #expect(store.search("gordon").count == 1)
    #expect(store.search("a.com").count == 1)
    #expect(store.search("zebra").isEmpty)
}

@Test func batchAddSavesOnceAndDedupes() throws {
    let store = try BookmarkStore(directory: tempDir())
    let (existing, _) = store.add(url: URL(string: "https://a.com/old")!)
    store.markDone(id: existing.id)
    var changes = 0
    store.onChange = { changes += 1 }
    let result = store.add(urls: [
        URL(string: "https://a.com/1")!,
        URL(string: "https://a.com/1")!,
        URL(string: "https://a.com/old")!,
        URL(string: "https://a.com/2")!,
    ])
    #expect(changes == 1)
    #expect(result.new.map(\.url) == ["https://a.com/1", "https://a.com/2"])
    #expect(result.touched == 3)
    // The batch sits at the top in paste order; the re-added duplicate is
    // bumped above older items and no longer done.
    #expect(store.bookmarks(in: Library.unsorted).map(\.url)
        == ["https://a.com/1", "https://a.com/old", "https://a.com/2"])
    #expect(store.archive().isEmpty)
}

@Test func searchMatchesNote() throws {
    let store = try BookmarkStore(directory: tempDir())
    _ = store.add(url: URL(string: "https://a.com/tacos")!)
    var updated = store.library.bookmarks[0]
    updated.note = "make for game night"
    store.update(updated)
    #expect(store.search("game night").count == 1)
}

@Test func toggleFavoriteSetsAndClears() throws {
    let store = try BookmarkStore(directory: tempDir())
    let (bookmark, _) = store.add(url: URL(string: "https://a.com/1")!)
    store.toggleFavorite(id: bookmark.id)
    #expect(store.library.bookmarks[0].isFavorite)
    store.toggleFavorite(id: bookmark.id)
    #expect(!store.library.bookmarks[0].isFavorite)
}

@Test func favoritesIncludeDoneAndSortNewestFirst() throws {
    let store = try BookmarkStore(directory: tempDir())
    let (a, _) = store.add(url: URL(string: "https://a.com/1")!)
    let (b, _) = store.add(url: URL(string: "https://a.com/2")!)
    let (c, _) = store.add(url: URL(string: "https://a.com/3")!)
    for (id, seconds) in [(a.id, 100.0), (b.id, 200.0), (c.id, 300.0)] {
        var bookmark = store.library.bookmarks.first { $0.id == id }!
        bookmark.favoritedAt = Date(timeIntervalSince1970: seconds)
        store.update(bookmark)
    }
    store.markDone(id: c.id)
    #expect(store.favorites().map(\.id) == [c.id, b.id, a.id])
}

@Test func decodesALibraryWrittenBeforeFavorites() throws {
    let json = """
    {"folders":["Unsorted"],"bookmarks":[{"id":"00000000-0000-0000-0000-000000000001",\
    "url":"https://a.com/1","title":"A","folder":"Unsorted","source":"web",\
    "createdAt":0,"hasThumbnail":false,"manuallyFiled":false}]}
    """
    let library = try JSONDecoder().decode(Library.self, from: Data(json.utf8))
    #expect(library.bookmarks[0].favoritedAt == nil)
    #expect(!library.bookmarks[0].isFavorite)
}

@Test func pickReturnsNilOnEmptyStore() throws {
    let store = try BookmarkStore(directory: tempDir())
    #expect(store.pick() == nil)
}

@Test func pickNeverReturnsADoneBookmark() throws {
    let store = try BookmarkStore(directory: tempDir())
    let (done, _) = store.add(url: URL(string: "https://a.com/1")!)
    let (waiting, _) = store.add(url: URL(string: "https://a.com/2")!)
    store.markDone(id: done.id)
    for _ in 0..<20 {
        #expect(store.pick()?.id == waiting.id)
    }
}

@Test func pickExcludesTheGivenIDWhenAnotherCandidateExists() throws {
    let store = try BookmarkStore(directory: tempDir())
    let (a, _) = store.add(url: URL(string: "https://a.com/1")!)
    let (b, _) = store.add(url: URL(string: "https://a.com/2")!)
    for _ in 0..<20 {
        #expect(store.pick(excluding: a.id)?.id == b.id)
    }
}

@Test func pickFallsBackToTheExcludedBookmarkWhenItIsTheOnlyOne() throws {
    let store = try BookmarkStore(directory: tempDir())
    let (only, _) = store.add(url: URL(string: "https://a.com/1")!)
    #expect(store.pick(excluding: only.id)?.id == only.id)
}

@Test func recoversFromCorruptStoreUsingBackup() throws {
    let dir = tempDir()
    let store = try BookmarkStore(directory: dir)
    _ = store.add(url: URL(string: "https://a.com/1")!)
    _ = store.add(url: URL(string: "https://a.com/2")!)
    // The second add rotated a .bak that contains the first bookmark.
    try Data("{corrupt".utf8).write(to: dir.appendingPathComponent("library.json"))
    let recovered = try BookmarkStore(directory: dir)
    #expect(recovered.library.bookmarks.count == 1)
    #expect(recovered.didRecoverFromBackup)
}

@Test func recoveryDoesNotClobberTheGoodBackup() throws {
    let dir = tempDir()
    let store = try BookmarkStore(directory: dir)
    _ = store.add(url: URL(string: "https://a.com/1")!)
    _ = store.add(url: URL(string: "https://a.com/2")!)
    // .bak now holds the single-bookmark state. Corrupt library.json and recover from it.
    try Data("{corrupt".utf8).write(to: dir.appendingPathComponent("library.json"))
    _ = try BookmarkStore(directory: dir)
    // Corrupt library.json again without touching .bak: if recovery had rotated the
    // corrupt file over .bak, this second recovery would fail to find good data.
    try Data("{corrupt".utf8).write(to: dir.appendingPathComponent("library.json"))
    let recoveredAgain = try BookmarkStore(directory: dir)
    #expect(recoveredAgain.library.bookmarks.count == 1)
    #expect(recoveredAgain.didRecoverFromBackup)
}

@Test func loadsFiveThousandBookmarksUnder200ms() throws {
    let dir = tempDir()
    let store = try BookmarkStore(directory: dir)
    for i in 0..<5000 {
        _ = store.addForTesting(urlString: "https://example.com/item/\(i)")
    }
    store.saveNow()
    let start = ContinuousClock.now
    let reloaded = try BookmarkStore(directory: dir)
    let elapsed = ContinuousClock.now - start
    #expect(elapsed < .milliseconds(200))

    let searchStart = ContinuousClock.now
    _ = reloaded.search("item/49")
    #expect(ContinuousClock.now - searchStart < .milliseconds(100))
}

// Writes a library.json into a fresh temp directory, so a test can open a store on a
// folder list that the public API alone cannot produce (Unsorted not last, or empty).
private func storeSeeded(folders: [String]) throws -> BookmarkStore {
    let dir = tempDir()
    let data = try JSONEncoder().encode(Library(folders: folders, bookmarks: []))
    try data.write(to: dir.appendingPathComponent("library.json"))
    return try BookmarkStore(directory: dir)
}

@Test func addFolderInsertsBeforeUnsortedWhereverItSits() throws {
    let store = try storeSeeded(folders: [Library.unsorted, "Recipes"])
    store.addFolder("Shows")
    #expect(store.library.folders == ["Shows", Library.unsorted, "Recipes"])
}

@Test func addFolderOnEmptyFolderListAppends() throws {
    let store = try storeSeeded(folders: [])
    store.addFolder("Shows")
    #expect(store.library.folders == ["Shows"])
}

@Test func renameFolderRejectsAnEmptyName() throws {
    let store = try BookmarkStore(directory: tempDir())
    store.renameFolder("Recipes", to: "")
    #expect(store.library.folders == Library.defaultFolders)
}

@Test func folderNamesAreTrimmed() throws {
    let store = try BookmarkStore(directory: tempDir())
    store.addFolder("  ")
    #expect(store.library.folders == Library.defaultFolders)
    store.renameFolder("Recipes", to: "  ")
    #expect(store.library.folders == Library.defaultFolders)
    store.renameFolder("Recipes", to: " Dishes ")
    #expect(store.library.folders.contains("Dishes"))
    store.addFolder(" Code ")
    #expect(store.library.folders.contains("Code"))
}

@Test func removeFolderIgnoresAnUnknownName() throws {
    let store = try BookmarkStore(directory: tempDir())
    var changes = 0
    store.onChange = { changes += 1 }
    store.removeFolder("Nope")
    #expect(changes == 0)
    #expect(store.library.folders == Library.defaultFolders)
}
