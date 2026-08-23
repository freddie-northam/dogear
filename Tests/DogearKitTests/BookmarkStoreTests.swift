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
