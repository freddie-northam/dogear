import Foundation
import Testing
@testable import DogearKit

@Test func startsEmptyWithDefaultFolders() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    #expect(store.library.folders == Library.defaultFolders)
    #expect(store.library.bookmarks.isEmpty)
}

@Test func addPersistsAcrossReload() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let store = try BookmarkStore(directory: dir)
    let (bookmark, isNew) = store.add(url: URL(string: "https://example.com/a")!)!
    #expect(isNew)
    #expect(bookmark.folder == Library.unsorted)
    let reloaded = try BookmarkStore(directory: dir)
    #expect(reloaded.library.bookmarks.map(\.id) == [bookmark.id])
}

@Test func addDedupesOnCanonicalURL() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (first, _) = store.add(url: URL(string: "https://a.com/p?utm_source=x")!)!
    let (second, isNew) = store.add(url: URL(string: "https://A.com/p/")!)!
    #expect(!isNew)
    #expect(second.id == first.id)
    #expect(store.library.bookmarks.count == 1)
}

@Test func addRejectsNonHTTPSchemes() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let result = store.add(url: URL(string: "file:///etc/hosts")!)
    #expect(result == nil)
    #expect(store.library.bookmarks.isEmpty)
}

@Test func updateRefusesToStoreANonHTTPURL() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (bookmark, _) = store.add(url: URL(string: "https://a.com/original")!)!
    var mutated = bookmark
    mutated.url = "javascript:alert(1)"
    store.update(mutated)
    #expect(store.library.bookmarks[0].url == "https://a.com/original")
}

@Test func reAddBumpsToTopOfFolderListing() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (first, _) = store.add(url: URL(string: "https://a.com/1")!)!
    let (second, _) = store.add(url: URL(string: "https://a.com/2")!)!
    let (bumped, isNew) = store.add(url: URL(string: "https://a.com/1")!)!
    #expect(!isNew)
    #expect(bumped.id == first.id)
    #expect(store.bookmarks(in: Library.unsorted).map(\.id) == [first.id, second.id])
}

@Test func doneMovesToArchiveAndBack() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (bookmark, _) = store.add(url: URL(string: "https://a.com/1")!)!
    store.markDone(id: bookmark.id)
    #expect(store.bookmarks(in: Library.unsorted).isEmpty)
    #expect(store.archive().map(\.id) == [bookmark.id])
    store.markUndone(id: bookmark.id)
    #expect(store.bookmarks(in: Library.unsorted).map(\.id) == [bookmark.id])
    #expect(store.archive().isEmpty)
}

@Test func refileSetsManuallyFiled() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (bookmark, _) = store.add(url: URL(string: "https://a.com/1")!)!
    store.refile(id: bookmark.id, to: "Recipes")
    let updated = store.library.bookmarks[0]
    #expect(updated.folder == "Recipes")
    #expect(updated.manuallyFiled)
}

@Test func autoFileBatchWritesOnce() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (a, _) = store.add(url: URL(string: "https://a.com/1")!)!
    let (b, _) = store.add(url: URL(string: "https://a.com/2")!)!
    let (c, _) = store.add(url: URL(string: "https://a.com/3")!)!
    var changes = 0
    store.onChange = { changes += 1 }
    let applied = store.autoFile([
        (id: a.id, folder: "Recipes"),
        (id: b.id, folder: "Recipes"),
        (id: c.id, folder: "Recipes"),
    ])
    #expect(applied == 3)
    #expect(changes == 1)
    #expect(store.library.bookmarks.allSatisfy { $0.folder == "Recipes" })
}

@Test func autoFileSkipsManuallyFiledAndMoved() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (a, _) = store.add(url: URL(string: "https://a.com/1")!)!
    let (b, _) = store.add(url: URL(string: "https://a.com/2")!)!
    let (c, _) = store.add(url: URL(string: "https://a.com/3")!)!
    store.refile(id: a.id, to: "Shows")
    let applied = store.autoFile([
        (id: a.id, folder: "Recipes"),
        (id: b.id, folder: "Recipes"),
        (id: c.id, folder: "Recipes"),
    ])
    #expect(applied == 2)
    #expect(store.library.bookmarks.first { $0.id == a.id }?.folder == "Shows")
    #expect(store.library.bookmarks.first { $0.id == b.id }?.folder == "Recipes")
    #expect(store.library.bookmarks.first { $0.id == c.id }?.folder == "Recipes")
}

@Test func autoFileSkipsUnknownFolder() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (a, _) = store.add(url: URL(string: "https://a.com/1")!)!
    var changes = 0
    store.onChange = { changes += 1 }
    let applied = store.autoFile([(id: a.id, folder: "Not A Real Folder")])
    #expect(applied == 0)
    #expect(changes == 0)
    #expect(store.library.bookmarks.first?.folder == Library.unsorted)
}

@Test func removeFolderMovesBookmarksToUnsorted() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (bookmark, _) = store.add(url: URL(string: "https://a.com/1")!)!
    store.refile(id: bookmark.id, to: "Recipes")
    store.removeFolder("Recipes")
    #expect(!store.library.folders.contains("Recipes"))
    #expect(store.library.bookmarks[0].folder == Library.unsorted)
}

@Test func countsMatchExistingAccessors() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (filed, _) = store.add(url: URL(string: "https://a.com/1")!)!
    store.refile(id: filed.id, to: "Recipes")
    store.add(url: URL(string: "https://a.com/2")!)
    let (done, _) = store.add(url: URL(string: "https://a.com/3")!)!
    store.refile(id: done.id, to: "Recipes")
    store.markDone(id: done.id)
    let (favoriteDone, _) = store.add(url: URL(string: "https://a.com/4")!)!
    store.toggleFavorite(id: favoriteDone.id)
    store.markDone(id: favoriteDone.id)

    let counts = store.counts()
    for folder in store.library.folders {
        #expect(counts.byFolder[folder, default: 0] == store.bookmarks(in: folder).count)
    }
    #expect(counts.favorites == store.favorites().count)
    #expect(counts.archived == store.archive().count)
}

@Test func searchMatchesTitleAuthorURLIncludingArchive() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (a, _) = store.add(url: URL(string: "https://a.com/pasta")!)!
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
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (existing, _) = store.add(url: URL(string: "https://a.com/old")!)!
    store.markDone(id: existing.id)
    var changes = 0
    store.onChange = { changes += 1 }
    let result = store.add(urls: [
        URL(string: "https://a.com/1")!,
        URL(string: "https://a.com/1")!,
        URL(string: "https://a.com/old")!,
        URL(string: "https://a.com/2")!,
    ], duplicates: .resave)
    #expect(changes == 1)
    #expect(result.new.map(\.url) == ["https://a.com/1", "https://a.com/2"])
    #expect(result.existing.map(\.id) == [existing.id])
    #expect(store.bookmarks(in: Library.unsorted).map(\.url)
        == ["https://a.com/1", "https://a.com/old", "https://a.com/2"])
    #expect(store.archive().isEmpty)
}

private func storeWithADoneMiddle(_ dir: URL) throws -> (BookmarkStore, changes: () -> Int) {
    let store = try BookmarkStore(directory: dir)
    _ = store.add(urls: ["https://a.com/1", "https://a.com/2", "https://a.com/3"].map { URL(string: $0)! },
                  duplicates: .resave)
    store.markDone(id: store.library.bookmarks[1].id)
    var changes = 0
    store.onChange = { changes += 1 }
    return (store, { changes })
}

@Test func skipLeavesASavedLinkWhereItIsAndDone() throws {
    let temp = TempDirectory()
    let (store, changes) = try storeWithADoneMiddle(temp.url)
    let before = store.library.bookmarks
    store.flush()
    let modified = try FileManager.default.attributesOfItem(
        atPath: temp.url.appendingPathComponent("library.json").path)[.modificationDate] as? Date
    let result = store.add(urls: [URL(string: "https://A.com/2/?utm_source=x")!,
                                  URL(string: "https://a.com/3")!], duplicates: .skip)
    #expect(result.new.isEmpty)
    #expect(result.existing.map(\.url) == ["https://a.com/2", "https://a.com/3"])
    #expect(store.library.bookmarks == before)
    #expect(changes() == 0)
    store.flush()
    let after = try FileManager.default.attributesOfItem(
        atPath: temp.url.appendingPathComponent("library.json").path)[.modificationDate] as? Date
    #expect(after == modified)
}

@Test func skipPutsOnlyTheNewLinksOnTopInPasteOrder() throws {
    let temp = TempDirectory()
    let (store, changes) = try storeWithADoneMiddle(temp.url)
    let before = store.library.bookmarks
    let result = store.add(urls: ["https://b.com/x", "https://a.com/2", "https://b.com/y", "https://b.com/x"]
        .map { URL(string: $0)! }, duplicates: .skip)
    #expect(result.new.map(\.url) == ["https://b.com/x", "https://b.com/y"])
    #expect(result.existing.map(\.url) == ["https://a.com/2"])
    #expect(store.library.bookmarks.map(\.url) == ["https://b.com/x", "https://b.com/y"] + before.map(\.url))
    #expect(store.archive().map(\.url) == ["https://a.com/2"])
    #expect(changes() == 1)
}

@Test func aBatchDropsNonHTTPLinksAndDoesNotCountThem() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    var changes = 0
    store.onChange = { changes += 1 }
    for policy in [DuplicatePolicy.resave, .skip] {
        let result = store.add(urls: ["file:///etc/hosts", "mailto:a@b.com", "javascript:alert(1)"]
            .map { URL(string: $0)! }, duplicates: policy)
        #expect(result.new.isEmpty && result.existing.isEmpty)
    }
    #expect(store.library.bookmarks.isEmpty)
    #expect(changes == 0)
}

@Test func twoRecordsWithOneURLResolveToTheFirst() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (original, _) = store.add(url: URL(string: "https://a.com/1")!)!
    let removed = store.remove(id: original.id)!
    let (resaved, _) = store.add(url: URL(string: "https://a.com/1")!)!
    store.restore(removed.bookmark, at: 1)
    #expect(store.library.bookmarks.map(\.id) == [resaved.id, original.id])
    let skipped = store.add(urls: [URL(string: "https://a.com/1")!], duplicates: .skip)
    #expect(skipped.existing.map(\.id) == [resaved.id])
    let bumped = store.add(urls: [URL(string: "https://a.com/1")!], duplicates: .resave)
    #expect(bumped.existing.map(\.id) == [resaved.id])
    #expect(store.library.bookmarks.map(\.id) == [resaved.id, original.id])
}

@Test func reAddingADonePlaceLeavesItDone() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let first = try #require(store.add(places: [testPlace("Bao Borough")], to: "Restaurants").first)
    _ = store.add(url: URL(string: "https://a.com/newer")!)
    store.markDone(id: first.id)
    let before = store.library.bookmarks
    #expect(store.add(places: [testPlace("Bao Borough")], to: "Restaurants").isEmpty)
    #expect(store.library.bookmarks == before)
}

@Test func searchMatchesNote() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    _ = store.add(url: URL(string: "https://a.com/tacos")!)
    var updated = store.library.bookmarks[0]
    updated.note = "make for game night"
    store.update(updated)
    #expect(store.search("game night").count == 1)
}

@Test func toggleFavoriteSetsAndClears() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (bookmark, _) = store.add(url: URL(string: "https://a.com/1")!)!
    store.toggleFavorite(id: bookmark.id)
    #expect(store.library.bookmarks[0].isFavorite)
    store.toggleFavorite(id: bookmark.id)
    #expect(!store.library.bookmarks[0].isFavorite)
}

@Test func favoritesIncludeDoneAndSortNewestFirst() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (a, _) = store.add(url: URL(string: "https://a.com/1")!)!
    let (b, _) = store.add(url: URL(string: "https://a.com/2")!)!
    let (c, _) = store.add(url: URL(string: "https://a.com/3")!)!
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
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    #expect(store.pick() == nil)
}

@Test func pickNeverReturnsADoneBookmark() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (done, _) = store.add(url: URL(string: "https://a.com/1")!)!
    let (waiting, _) = store.add(url: URL(string: "https://a.com/2")!)!
    store.markDone(id: done.id)
    #expect(store.pick()?.id == waiting.id)
}

@Test func pickExcludesTheGivenIDWhenAnotherCandidateExists() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (a, _) = store.add(url: URL(string: "https://a.com/1")!)!
    let (b, _) = store.add(url: URL(string: "https://a.com/2")!)!
    #expect(store.pick(excluding: a.id)?.id == b.id)
}

@Test func pickFallsBackToTheExcludedBookmarkWhenItIsTheOnlyOne() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (only, _) = store.add(url: URL(string: "https://a.com/1")!)!
    #expect(store.pick(excluding: only.id)?.id == only.id)
}

@Test func pickWorksThroughTheOldestBookmarksWithoutRepeating() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    var idsOldestFirst: [UUID] = []
    for i in 0..<15 {
        let created = store.addForTesting(urlString: "https://example.com/oldest/\(i)")
        let dated = Bookmark(
            id: created.id, url: created.url, title: created.title, author: created.author,
            note: created.note, folder: created.folder, source: created.source,
            createdAt: Date(timeIntervalSince1970: Double(i)), doneAt: created.doneAt,
            hasThumbnail: created.hasThumbnail, manuallyFiled: created.manuallyFiled,
            favoritedAt: created.favoritedAt
        )
        store.update(dated)
        idsOldestFirst.append(created.id)
    }
    var seen: [UUID] = []
    for _ in 0..<10 {
        let picked = try #require(store.pick())
        store.markShown(id: picked.id)
        seen.append(picked.id)
    }
    #expect(seen == Array(idsOldestFirst.prefix(10)))
    #expect(Set(seen).count == 10)
}

@Test func recoversFromCorruptStoreUsingBackup() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let store = try BookmarkStore(directory: dir)
    _ = store.add(url: URL(string: "https://a.com/1")!)
    _ = store.add(url: URL(string: "https://a.com/2")!)
    store.flush()
    try Data("{corrupt".utf8).write(to: dir.appendingPathComponent("library.json"))
    let recovered = try BookmarkStore(directory: dir)
    #expect(recovered.library.bookmarks.count == 1)
    #expect(recovered.didRecoverFromBackup)
}

@Test func recoveryDoesNotClobberTheGoodBackup() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let store = try BookmarkStore(directory: dir)
    _ = store.add(url: URL(string: "https://a.com/1")!)
    _ = store.add(url: URL(string: "https://a.com/2")!)
    store.flush()
    try Data("{corrupt".utf8).write(to: dir.appendingPathComponent("library.json"))
    _ = try BookmarkStore(directory: dir)
    try Data("{corrupt".utf8).write(to: dir.appendingPathComponent("library.json"))
    let recoveredAgain = try BookmarkStore(directory: dir)
    #expect(recoveredAgain.library.bookmarks.count == 1)
    #expect(recoveredAgain.didRecoverFromBackup)
}

@Test func recoversFromBackupWhenMainFileIsMissing() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let store = try BookmarkStore(directory: dir)
    _ = store.add(url: URL(string: "https://a.com/1")!)
    _ = store.add(url: URL(string: "https://a.com/2")!)
    store.flush()
    try FileManager.default.removeItem(at: dir.appendingPathComponent("library.json"))
    let recovered = try BookmarkStore(directory: dir)
    #expect(recovered.library.bookmarks.count == 1)
    #expect(recovered.didRecoverFromBackup)
}

@Test func missingMainFileRecoveryDoesNotDestroyTheBackup() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let store = try BookmarkStore(directory: dir)
    _ = store.add(url: URL(string: "https://a.com/1")!)
    _ = store.add(url: URL(string: "https://a.com/2")!)
    store.flush()
    try FileManager.default.removeItem(at: dir.appendingPathComponent("library.json"))
    let recovered = try BookmarkStore(directory: dir)
    _ = recovered.add(url: URL(string: "https://a.com/3")!)
    _ = recovered.add(url: URL(string: "https://a.com/4")!)
    recovered.flush()
    try Data("{corrupt".utf8).write(to: dir.appendingPathComponent("library.json"))
    let recoveredAgain = try BookmarkStore(directory: dir)
    #expect(!recoveredAgain.library.bookmarks.isEmpty)
    #expect(recoveredAgain.didRecoverFromBackup)
}

@Test func oldLibraryGainsNewDefaultFolders() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let json = """
    {"folders":["Recipes","Restaurants","Shows","Articles","Unsorted"],\
    "bookmarks":[{"id":"00000000-0000-0000-0000-000000000001",\
    "url":"https://a.com/1","title":"A","folder":"Unsorted","source":"web",\
    "createdAt":0,"hasThumbnail":false,"manuallyFiled":false}]}
    """
    try Data(json.utf8).write(to: dir.appendingPathComponent("library.json"))
    let store = try BookmarkStore(directory: dir)
    #expect(store.library.folders.contains("Music"))
    let musicIndex = store.library.folders.firstIndex(of: "Music")!
    let unsortedIndex = store.library.folders.firstIndex(of: Library.unsorted)!
    #expect(musicIndex < unsortedIndex)
    #expect(store.library.schemaVersion == Library.currentSchemaVersion)
}

@Test func folderAdoptionRunsOnce() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let json = """
    {"folders":["Recipes","Restaurants","Shows","Articles","Unsorted"],\
    "bookmarks":[{"id":"00000000-0000-0000-0000-000000000001",\
    "url":"https://a.com/1","title":"A","folder":"Unsorted","source":"web",\
    "createdAt":0,"hasThumbnail":false,"manuallyFiled":false}]}
    """
    try Data(json.utf8).write(to: dir.appendingPathComponent("library.json"))
    let store = try BookmarkStore(directory: dir)
    store.removeFolder("Music")
    let reloaded = try BookmarkStore(directory: dir)
    #expect(!reloaded.library.folders.contains("Music"))
}

@Test func oldURLsAreRecanonicalizedOnLoad() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let json = """
    {"folders":["Unsorted"],"bookmarks":[\
    {"id":"00000000-0000-0000-0000-000000000001",\
    "url":"https://twitter.com/jack/status/20","title":"A","note":"keep me",\
    "folder":"Unsorted","source":"web","createdAt":0,"hasThumbnail":false,"manuallyFiled":false},\
    {"id":"00000000-0000-0000-0000-000000000002",\
    "url":"https://x.com/jack/status/20","title":"B",\
    "folder":"Unsorted","source":"web","createdAt":1,"hasThumbnail":false,"manuallyFiled":false}\
    ]}
    """
    try Data(json.utf8).write(to: dir.appendingPathComponent("library.json"))
    let store = try BookmarkStore(directory: dir)
    #expect(store.library.bookmarks.count == 1)
    #expect(store.library.bookmarks[0].url == "https://x.com/jack/status/20")
    #expect(store.library.bookmarks[0].note == "keep me")
}

@Test func loadsFiveThousandBookmarksUnder200ms() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let store = try BookmarkStore(directory: dir)
    for i in 0..<5000 {
        _ = store.addForTesting(urlString: "https://example.com/item/\(i)")
    }
    store.saveNow()
    let start = ContinuousClock.now
    let reloaded = try BookmarkStore(directory: dir)
    let elapsed = ContinuousClock.now - start
    #expect(reloaded.library.bookmarks.count == 5000)

    let searchStart = ContinuousClock.now
    let results = reloaded.search("item/49")
    let searchElapsed = ContinuousClock.now - searchStart
    #expect(results.contains { $0.url == "https://example.com/item/49" })

    if ProcessInfo.processInfo.environment["PERF"] != nil {
        #expect(elapsed < .milliseconds(200))
        #expect(searchElapsed < .milliseconds(100))
    }
}

private func storeSeeded(folders: [String]) throws -> BookmarkStore {
    let temp = TempDirectory()
    let dir = temp.url
    let data = try JSONEncoder().encode(
        Library(folders: folders, bookmarks: [], schemaVersion: Library.currentSchemaVersion)
    )
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
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    store.renameFolder("Recipes", to: "")
    #expect(store.library.folders == Library.defaultFolders)
}

@Test func folderNamesAreTrimmed() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
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
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    var changes = 0
    store.onChange = { changes += 1 }
    store.removeFolder("Nope")
    #expect(changes == 0)
    #expect(store.library.folders == Library.defaultFolders)
}

@Test func pickPrefersFiledAndOldest() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    for i in 0..<30 {
        _ = store.addForTesting(urlString: "https://example.com/u/\(i)")
    }
    let (filed, _) = store.add(url: URL(string: "https://example.com/filed")!)!
    store.refile(id: filed.id, to: "Recipes")
    let picked = store.pick()
    #expect(picked?.folder == "Recipes")
}


@Test func moveFoldersReordersAndKeepsUnsortedLast() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    store.moveFolders(fromOffsets: IndexSet(integer: 0), toOffset: 3)
    #expect(store.library.folders == ["Restaurants", "Shows", "Recipes", "Music", "Articles", "Unsorted"])
    store.moveFolders(fromOffsets: IndexSet(integer: 0), toOffset: 99)
    #expect(store.library.folders.last == "Unsorted")
    #expect(store.library.folders[4] == "Restaurants")
}

@Test func moveFoldersPersistsAcrossReload() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    store.moveFolders(fromOffsets: IndexSet(integer: 4), toOffset: 0)
    let reloaded = try BookmarkStore(directory: temp.url)
    #expect(reloaded.library.folders.first == "Articles")
    #expect(reloaded.library.folders.last == "Unsorted")
}


@Test func removeReturnsPositionAndRestorePutsItBack() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (a, _) = store.add(url: URL(string: "https://a.com/1")!)!
    let (b, _) = store.add(url: URL(string: "https://a.com/2")!)!
    _ = store.add(url: URL(string: "https://a.com/3")!)!
    let removed = try #require(store.remove(id: b.id))
    #expect(removed.index == 1)
    #expect(store.library.bookmarks.count == 2)
    store.restore(removed.bookmark, at: removed.index)
    #expect(store.library.bookmarks.map(\.id)[1] == b.id)
    #expect(store.library.bookmarks.map(\.id)[2] == a.id)
    store.restore(removed.bookmark, at: 0)
    #expect(store.library.bookmarks.count == 3)
}

@Test func restoreClampsAnOutOfRangeIndex() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (a, _) = store.add(url: URL(string: "https://a.com/1")!)!
    let removed = try #require(store.remove(id: a.id))
    store.restore(removed.bookmark, at: 99)
    #expect(store.library.bookmarks.count == 1)
}

@Test func removeFolderReturnsWhatRestoreNeeds() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (x, _) = store.add(url: URL(string: "https://a.com/x")!)!
    store.refile(id: x.id, to: "Recipes")
    let recipesIndex = store.library.folders.firstIndex(of: "Recipes")!
    let removed = try #require(store.removeFolder("Recipes"))
    #expect(removed.index == recipesIndex)
    #expect(removed.bookmarkIDs == [x.id])
    #expect(store.library.bookmarks[0].folder == Library.unsorted)
    store.restoreFolder("Recipes", at: removed.index, bookmarkIDs: removed.bookmarkIDs)
    #expect(store.library.folders[recipesIndex] == "Recipes")
    #expect(store.library.bookmarks[0].folder == "Recipes")
}

@Test func removeFolderRefusesUnsortedAndUnknown() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    #expect(store.removeFolder(Library.unsorted) == nil)
    #expect(store.removeFolder("Nope") == nil)
}

@Test func pickPrefersABookmarkTheRowHasNeverShown() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let older = store.add(url: URL(string: "https://a.com/older")!)!.bookmark
    let newer = store.add(url: URL(string: "https://a.com/newer")!)!.bookmark
    store.markShown(id: older.id)
    #expect(store.pick()?.id == newer.id)
}

@Test func pickReturnsToTheBookmarkShownLongestAgoOnceAllHaveBeenSeen() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let first = store.add(url: URL(string: "https://a.com/first")!)!.bookmark
    let second = store.add(url: URL(string: "https://a.com/second")!)!.bookmark
    store.markShown(id: first.id)
    store.markShown(id: second.id)
    #expect(store.pick()?.id == first.id)
}

@Test func markShownPersistsAcrossReload() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let store = try BookmarkStore(directory: dir)
    let shown = store.add(url: URL(string: "https://a.com/shown")!)!.bookmark
    store.markShown(id: shown.id)
    let reloaded = try BookmarkStore(directory: dir)
    #expect(reloaded.library.bookmarks.first { $0.id == shown.id }?.lastShownAt != nil)
}

@Test func markShownIgnoresAnUnknownID() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    store.add(url: URL(string: "https://a.com/a")!)
    store.markShown(id: UUID())
    #expect(store.library.bookmarks.allSatisfy { $0.lastShownAt == nil })
}

@Test func aLibrarySavedBeforeLastShownAtStillLoads() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let older = """
        {"folders":["Recipes","Unsorted"],"schemaVersion":2,"bookmarks":[
        {"id":"\(UUID().uuidString)","url":"https://a.com/p","title":"Pasta","folder":"Recipes",
        "source":"web","createdAt":0,"hasThumbnail":false,"manuallyFiled":false}]}
        """
    try older.write(to: dir.appendingPathComponent("library.json"), atomically: true, encoding: .utf8)
    let store = try BookmarkStore(directory: dir)
    #expect(store.library.bookmarks.count == 1)
    #expect(store.library.bookmarks[0].lastShownAt == nil)
    #expect(store.library.bookmarks[0].place == nil)
}

private func testPlace(_ name: String, latitude: Double = 51.5, longitude: Double = -0.09) -> Place {
    Place(name: name, address: "\(name) Street", latitude: latitude, longitude: longitude)
}

@Test func addPlacesSavesOneBookmarkPerPlaceInTheChosenFolder() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let places = [testPlace("Bao Borough", longitude: -0.09), testPlace("Kagari", longitude: 139.7)]
    let saved = store.add(places: places, to: "Restaurants")
    #expect(saved.map(\.title) == ["Bao Borough", "Kagari"])
    #expect(saved.allSatisfy { $0.folder == "Restaurants" })
    #expect(saved.allSatisfy { $0.place != nil })
    #expect(saved.allSatisfy { $0.manuallyFiled })
}

@Test func aPlaceBookmarkStoresAnHTTPSMapLink() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let saved = try #require(store.add(places: [testPlace("Bao Borough")], to: "Restaurants").first)
    let url = try #require(URL(string: saved.url))
    #expect(URLCleaner.isCapturable(url))
    #expect(url.host == "maps.apple.com")
    #expect(saved.place?.latitude == 51.5)
}

@Test func addPlacesSkipsAPlaceAlreadySaved() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    _ = store.add(places: [testPlace("Bao Borough")], to: "Restaurants")
    let again = store.add(places: [testPlace("Bao Borough")], to: "Restaurants")
    #expect(again.isEmpty)
    #expect(store.library.bookmarks.count == 1)
}

@Test func addPlacesFallsBackToUnsortedForAFolderThatIsGone() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let saved = try #require(store.add(places: [testPlace("Kagari")], to: "Nowhere").first)
    #expect(saved.folder == Library.unsorted)
}

@Test func addPlacesPersistsAcrossReload() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let store = try BookmarkStore(directory: dir)
    _ = store.add(places: [testPlace("Bao Borough")], to: "Restaurants")
    let reloaded = try BookmarkStore(directory: dir)
    #expect(reloaded.library.bookmarks.first?.place?.name == "Bao Borough")
    #expect(reloaded.library.bookmarks.first?.place?.address == "Bao Borough Street")
}

@Test func searchFindsAPlaceByItsAddress() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    _ = store.add(places: [Place(name: "Kagari", address: "Ginza, Tokyo",
                                 latitude: 35.6, longitude: 139.7)], to: "Restaurants")
    #expect(store.search("ginza").count == 1)
    #expect(store.search("nowhere").isEmpty)
}

@Test func addPlacesWritesOnceForTheWholeBatch() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    var changes = 0
    store.onChange = { changes += 1 }
    _ = store.add(places: [testPlace("A", longitude: 1), testPlace("B", longitude: 2),
                           testPlace("C", longitude: 3)], to: "Restaurants")
    #expect(changes == 1)
}

@Test func addPlacesDoesNotNotifyWhenNothingIsNew() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    _ = store.add(places: [testPlace("A")], to: "Restaurants")
    var changes = 0
    store.onChange = { changes += 1 }
    _ = store.add(places: [testPlace("A")], to: "Restaurants")
    #expect(changes == 0)
}

@Test func picksUnder50msAndRecordsTheShowingUnder5msWithFiveThousandBookmarks() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    for i in 0..<5000 {
        _ = store.addForTesting(urlString: "https://example.com/item/\(i)")
    }
    store.saveNow()

    let pickStart = ContinuousClock.now
    let picked = try #require(store.pick())
    let pickElapsed = ContinuousClock.now - pickStart

    let markStart = ContinuousClock.now
    store.markShown(id: picked.id)
    let markElapsed = ContinuousClock.now - markStart

    if ProcessInfo.processInfo.environment["PERF"] != nil {
        #expect(pickElapsed < .milliseconds(50))
        #expect(markElapsed < .milliseconds(5))
    }
}

@Test func markThumbnailsAppliesTheBatchWithOneWrite() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let a = store.add(url: URL(string: "https://a.com/a")!)!.bookmark
    let b = store.add(url: URL(string: "https://a.com/b")!)!.bookmark
    var changes = 0
    store.onChange = { changes += 1 }
    #expect(store.markThumbnails([a.id, b.id]) == 2)
    #expect(changes == 1)
    #expect(store.library.bookmarks.allSatisfy { $0.hasThumbnail })
}

@Test func markThumbnailsIgnoresUnknownAndAlreadyMarkedIDs() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let a = store.add(url: URL(string: "https://a.com/a")!)!.bookmark
    #expect(store.markThumbnails([a.id]) == 1)
    var changes = 0
    store.onChange = { changes += 1 }
    #expect(store.markThumbnails([a.id, UUID()]) == 0)
    #expect(changes == 0)
}

@Test func markThumbnailsSetsOnlyTheFlag() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let saved = try #require(store.add(places: [testPlace("Kagari")], to: "Restaurants").first)
    store.refile(id: saved.id, to: "Recipes")
    store.markThumbnails([saved.id])
    let after = try #require(store.library.bookmarks.first { $0.id == saved.id })
    #expect(after.folder == "Recipes")
    #expect(after.place?.name == "Kagari")
    #expect(after.hasThumbnail)
}

@Test func subtitleFallsBackFromNoteToPlaceAddress() {
    let place = Place(name: "Kagari", address: "Ginza, Tokyo", latitude: 35.6, longitude: 139.7)
    let base = Bookmark(id: UUID(), url: "https://a.com/p", title: "T", author: nil, note: nil,
                        folder: "Recipes", source: .web, createdAt: Date(), doneAt: nil,
                        hasThumbnail: false, manuallyFiled: false)
    var withNote = base
    withNote.note = "Halve the salt."
    withNote.place = place
    #expect(withNote.subtitle == "Halve the salt.")
    var withPlace = base
    withPlace.place = place
    #expect(withPlace.subtitle == "Ginza, Tokyo")
    #expect(base.subtitle == nil)
}

@Test func migrationDropsARecordWhoseURLIsNotHTTP() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let older = """
        {"folders":["Recipes","Unsorted"],"schemaVersion":1,"bookmarks":[
        {"id":"\(UUID().uuidString)","url":"file:///etc/hosts","title":"Local","folder":"Recipes",
        "source":"web","createdAt":0,"hasThumbnail":false,"manuallyFiled":false},
        {"id":"\(UUID().uuidString)","url":"https://a.com/p","title":"Pasta","folder":"Recipes",
        "source":"web","createdAt":0,"hasThumbnail":false,"manuallyFiled":false}]}
        """
    try older.write(to: dir.appendingPathComponent("library.json"), atomically: true, encoding: .utf8)
    let store = try BookmarkStore(directory: dir)
    #expect(store.library.bookmarks.map(\.url) == ["https://a.com/p"])
    let reloaded = try BookmarkStore(directory: dir)
    #expect(reloaded.library.bookmarks.count == 1)
}

@Test func migrationKeepsEveryHTTPRecord() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let older = """
        {"folders":["Recipes","Unsorted"],"schemaVersion":1,"bookmarks":[
        {"id":"\(UUID().uuidString)","url":"http://a.com/one","title":"One","folder":"Recipes",
        "source":"web","createdAt":0,"hasThumbnail":false,"manuallyFiled":false},
        {"id":"\(UUID().uuidString)","url":"https://b.com/two","title":"Two","folder":"Recipes",
        "source":"web","createdAt":0,"hasThumbnail":false,"manuallyFiled":false}]}
        """
    try older.write(to: dir.appendingPathComponent("library.json"), atomically: true, encoding: .utf8)
    let store = try BookmarkStore(directory: dir)
    #expect(store.library.bookmarks.count == 2)
}

@Test func everythingThePopoverAsksTheStoreForOnOpenIsUnder50ms() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    for i in 0..<1000 {
        _ = store.addForTesting(urlString: "https://example.com/item/\(i)")
    }
    store.saveNow()

    let start = ContinuousClock.now
    let picked = try #require(store.pick())
    store.markShown(id: picked.id)
    _ = store.counts()
    _ = Array(store.library.bookmarks.filter { !$0.isDone }.prefix(3))
    _ = Array(store.favorites().prefix(3))
    let elapsed = ContinuousClock.now - start

    if ProcessInfo.processInfo.environment["PERF"] != nil {
        #expect(elapsed < .milliseconds(50))
    }
}

@MainActor @Test func reimportingAFiveThousandLinkExportWritesNothingUnder200ms() async throws {
    let temp = TempDirectory()
    let bookmarks = (0..<5_000).map { i in
        Bookmark(id: UUID(), url: "https://example.com/item/\(i)", title: "Item \(i)", author: nil, note: nil,
                 folder: Library.unsorted, source: .web, createdAt: Date(), doneAt: i < 1_000 ? Date() : nil,
                 hasThumbnail: false, manuallyFiled: false)
    }
    try JSONEncoder().encode(Library(folders: Library.defaultFolders, bookmarks: bookmarks,
                                     schemaVersion: Library.currentSchemaVersion))
        .write(to: temp.url.appendingPathComponent("library.json"))
    let store = try BookmarkStore(directory: temp.url)
    let html = BookmarksHTML.export(store.library)
    var changes = 0
    store.onChange = { changes += 1 }

    let start = ContinuousClock.now
    let outcome = Capture(store: store) { _ in }.save(.bookmarksFile(html: html))
    let elapsed = ContinuousClock.now - start

    #expect(outcome.alreadySaved == 5_000)
    #expect(store.archive().count == 1_000)
    #expect(changes == 0)
    if ProcessInfo.processInfo.environment["PERF"] != nil {
        #expect(elapsed < .milliseconds(200))
    }
}

@Test func savingALinkWithAPasswordKeepsTheLinkAndDropsThePassword() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    store.add(url: URL(string: "https://a.com/x")!)
    store.add(url: URL(string: "https://u:secret@a.com/x")!)
    #expect(store.library.bookmarks.map(\.url) == ["https://a.com/x"])
    store.flush()
    let file = try String(contentsOf: temp.url.appendingPathComponent("library.json"), encoding: .utf8)
    #expect(!file.contains("secret"))
}

@Test func aLaunchRemovesAStoredPasswordFromTheLibraryAndTheBackup() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let older = """
        {"folders":["Recipes","Unsorted"],"schemaVersion":2,"bookmarks":[
        {"id":"\(UUID().uuidString)","url":"https://u:secret@a.com/p","title":"Pasta","folder":"Recipes",
        "source":"web","createdAt":0,"hasThumbnail":false,"manuallyFiled":false}]}
        """
    try older.write(to: dir.appendingPathComponent("library.json"), atomically: true, encoding: .utf8)
    let store = try BookmarkStore(directory: dir)
    #expect(store.library.bookmarks.map(\.url) == ["https://a.com/p"])
    for name in ["library.json", "library.json.bak"] {
        let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
        #expect(!text.contains("secret"), "\(name) still holds the password")
    }
}

@Test func aLinkToALocalServerIsStillSaved() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    #expect(store.add(url: URL(string: "http://localhost:3000/docs")!)?.isNew == true)
}

@Test func aStarClickTakesUnder5msWithFiveThousandBookmarksWhileAWriteIsQueued() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    for i in 0..<5000 {
        _ = store.addForTesting(urlString: "https://example.com/item/\(i)")
    }
    store.saveNow()
    let id = store.library.bookmarks[0].id

    var slowest = Duration.zero
    for _ in 0..<3 {
        let start = ContinuousClock.now
        store.toggleFavorite(id: id)
        slowest = max(slowest, ContinuousClock.now - start)
    }
    store.flush()

    if ProcessInfo.processInfo.environment["PERF"] != nil {
        #expect(slowest < .milliseconds(5))
    }
}

@Test func theLastOfABurstOfChangesIsOnDisk() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let bookmark = try #require(store.add(url: URL(string: "https://a.com/1")!)).bookmark
    for _ in 0..<51 {
        store.toggleFavorite(id: bookmark.id)
    }
    store.flush()
    let data = try Data(contentsOf: temp.url.appendingPathComponent("library.json"))
    let onDisk = try JSONDecoder().decode(Library.self, from: data)
    #expect(onDisk.bookmarks.first?.favoritedAt != nil)
}

@Test func aChangeSurvivesTheStoreThatMadeIt() throws {
    let temp = TempDirectory()
    var id: UUID?
    do {
        let store = try BookmarkStore(directory: temp.url)
        id = store.add(url: URL(string: "https://a.com/1")!)?.bookmark.id
    }
    let reloaded = try BookmarkStore(directory: temp.url)
    #expect(reloaded.library.bookmarks.map(\.id) == [try #require(id)])
}

@MainActor @Test(.timeLimit(.minutes(1))) func aFailedWriteReportsOnTheMainThreadAndALaterChangeStillSaves() async throws {
    let temp = TempDirectory()
    let dir = temp.url.appendingPathComponent("library")
    let store = try BookmarkStore(directory: dir)
    let bookmark = try #require(store.add(url: URL(string: "https://a.com/1")!)).bookmark
    store.flush()
    try FileManager.default.removeItem(at: dir)

    let onMain = await withCheckedContinuation { continuation in
        store.onWriteFailure = { _ in
            store.onWriteFailure = nil
            continuation.resume(returning: Thread.isMainThread)
        }
        store.toggleFavorite(id: bookmark.id)
    }
    #expect(onMain)

    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    store.markDone(id: bookmark.id)
    let reloaded = try BookmarkStore(directory: dir)
    #expect(reloaded.library.bookmarks.first?.doneAt != nil)
    #expect(reloaded.library.bookmarks.first?.favoritedAt != nil)
}

@Test func aSearchKeystrokeTakesUnder40msWithTwentyThousandBookmarks() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let words = ["Creamy", "garlic", "pasta", "Crème", "brûlée", "Ramen", "Tokyo", "São", "Paulo", "café", "review", "Swift"]
    for i in 0..<20_000 {
        _ = store.addForTesting(
            urlString: "https://example\(i % 300).com/post/\(i)",
            title: (0..<6).map { words[($0 * 7 + i) % words.count] }.joined(separator: " "),
            author: i % 3 == 0 ? "Gordon \(i)" : nil,
            note: i % 5 == 0 ? "make for game night \(i)" : nil
        )
    }

    // The first search after a change builds the search text, so it is timed on its own.
    let start = ContinuousClock.now
    let first = store.search("g").count
    let firstElapsed = ContinuousClock.now - start

    var slowest = Duration.zero
    var total = first
    for query in ["ga", "gam", "game", "game n", "crè", "brûl", "zzz", "example12.com"] {
        let start = ContinuousClock.now
        total += store.search(query).count
        slowest = max(slowest, ContinuousClock.now - start)
    }
    #expect(total == 58_738)

    if ProcessInfo.processInfo.environment["PERF"] != nil {
        #expect(firstElapsed < .milliseconds(400))
        #expect(slowest < .milliseconds(40))
    }
}

@Test func searchSeesEveryChangeSinceTheLastSearch() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let (a, _) = try #require(store.add(url: URL(string: "https://a.com/1")!))
    #expect(store.search("risotto").isEmpty)

    var updated = a
    updated.title = "Risotto"
    store.update(updated)
    #expect(store.search("risotto").map(\.id) == [a.id])

    updated.note = "for sunday"
    store.update(updated)
    #expect(store.search("sunday").map(\.id) == [a.id])

    let (b, _) = try #require(store.add(url: URL(string: "https://b.com/risotto")!))
    #expect(Set(store.search("risotto").map(\.id)) == [a.id, b.id])

    _ = store.remove(id: a.id)
    #expect(store.search("risotto").map(\.id) == [b.id])
}

@Test func searchIgnoresCaseKeepsAccentsAndLibraryOrder() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    for (i, title) in ["Crème brûlée", "PASTA night", "Pasta al forno"].enumerated() {
        _ = store.addForTesting(urlString: "https://a.com/\(i)", title: title)
    }
    #expect(store.search("pasta").map(\.title) == ["PASTA night", "Pasta al forno"])
    #expect(store.search("CRÈME").map(\.title) == ["Crème brûlée"])
    #expect(store.search("creme").isEmpty)
    #expect(store.search("").isEmpty)
}

@Test func searchDoesNotMatchAcrossTwoFields() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    _ = store.addForTesting(urlString: "https://a.com/1", title: "pasta", author: "Gordon")
    #expect(store.search("pasta").count == 1)
    #expect(store.search("pastagordon").isEmpty)
    #expect(store.search("pasta gordon").isEmpty)
}
