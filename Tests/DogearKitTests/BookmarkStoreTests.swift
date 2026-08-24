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
    store.flush()
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
    // Filed: refiled into Recipes.
    let (filed, _) = store.add(url: URL(string: "https://a.com/1")!)!
    store.refile(id: filed.id, to: "Recipes")
    // Unsorted: left in place.
    store.add(url: URL(string: "https://a.com/2")!)
    // Done: filed then marked done, so it should count toward archive but
    // not toward its folder's not-done count.
    let (done, _) = store.add(url: URL(string: "https://a.com/3")!)!
    store.refile(id: done.id, to: "Recipes")
    store.markDone(id: done.id)
    // Favorited and done: favorites() includes done bookmarks (a lens, not a
    // queue), so this must count toward favorites even though it is archived.
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

@Test func pickDrawsOnlyFromTheTenOldest() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    var idsOldestFirst: [UUID] = []
    for i in 0..<15 {
        let created = store.addForTesting(urlString: "https://example.com/oldest/\(i)")
        // addForTesting stamps createdAt: Date(); reconstruct with a distinct,
        // strictly increasing timestamp and write it back through the public
        // update path (createdAt is otherwise immutable on Bookmark).
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
    let tenOldest = Set(idsOldestFirst.prefix(10))
    var sampled = Set<UUID>()
    for _ in 0..<50 {
        let picked = try #require(store.pick())
        #expect(tenOldest.contains(picked.id))
        sampled.insert(picked.id)
    }
    #expect(sampled.count >= 2)
}

@Test func recoversFromCorruptStoreUsingBackup() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let store = try BookmarkStore(directory: dir)
    _ = store.add(url: URL(string: "https://a.com/1")!)
    store.flush()
    _ = store.add(url: URL(string: "https://a.com/2")!)
    store.flush()
    // The second add rotated a .bak that contains the first bookmark.
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
    store.flush()
    _ = store.add(url: URL(string: "https://a.com/2")!)
    store.flush()
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

@Test func recoversFromBackupWhenMainFileIsMissing() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let store = try BookmarkStore(directory: dir)
    _ = store.add(url: URL(string: "https://a.com/1")!)
    store.flush()
    _ = store.add(url: URL(string: "https://a.com/2")!)
    store.flush()
    // The second add rotated a .bak that contains the first bookmark.
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
    store.flush()
    _ = store.add(url: URL(string: "https://a.com/2")!)
    store.flush()
    // .bak now holds the single-bookmark state. Delete library.json and recover from it.
    try FileManager.default.removeItem(at: dir.appendingPathComponent("library.json"))
    let recovered = try BookmarkStore(directory: dir)
    // Two more saves after recovery, each rotating library.json into .bak: if the
    // recovery write had clobbered the good .bak instead, this chain would still
    // look fine here but fail the corrupt-and-recover below.
    _ = recovered.add(url: URL(string: "https://a.com/3")!)
    recovered.flush()
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
    store.flush()
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

    // A single click must not block on the disk. The library is written on a
    // background queue, so this measures the caller's share of the work.
    let id = reloaded.library.bookmarks[2500].id
    let mutateStart = ContinuousClock.now
    reloaded.toggleFavorite(id: id)
    let mutateElapsed = ContinuousClock.now - mutateStart
    reloaded.flush()

    // The spec's benchmark table is verified by `PERF=1 swift test -c release
    // -Xswiftc -enable-testing`, not on every PR: shared CI runners are noisy,
    // and a slow neighbour would fail these for reasons unrelated to the diff.
    // Release, because that is what a user runs.
    //
    // The mutation ceiling sits far below what a click cost while the store
    // wrote on the calling thread, so a return to that fails here. It leaves a
    // wide margin over the measured cost: the point is to catch a regression,
    // not to police a millisecond.
    if ProcessInfo.processInfo.environment["PERF"] != nil {
        #expect(elapsed < .milliseconds(200))
        #expect(searchElapsed < .milliseconds(100))
        #expect(mutateElapsed < .milliseconds(3))
    }
}

@Test func flushWritesEveryPendingChange() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let store = try BookmarkStore(directory: dir)
    // A burst: the store coalesces these into far fewer writes than mutations,
    // so the reload below is the only proof that none of them was dropped.
    for i in 0..<200 {
        _ = store.add(url: URL(string: "https://example.com/\(i)")!)
    }
    store.addFolder("Trips")
    store.flush()

    let reloaded = try BookmarkStore(directory: dir)
    #expect(reloaded.library.bookmarks.count == 200)
    #expect(reloaded.library.folders.contains("Trips"))
}

@Test func flushIsSafeWithNothingPending() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    store.flush()
    store.flush()
    #expect(store.library.bookmarks.isEmpty)
}

// Writes a library.json into a fresh temp directory, so a test can open a store on a
// folder list that the public API alone cannot produce (Unsorted not last, or empty).
// Stamped at the current schema version: these tests exercise folder mechanics, not
// migration, so the one-shot default-folder adoption must not fire here.
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
    // Defaults: Recipes, Restaurants, Shows, Music, Articles, Unsorted
    store.moveFolders(fromOffsets: IndexSet(integer: 0), toOffset: 3)
    #expect(store.library.folders == ["Restaurants", "Shows", "Recipes", "Music", "Articles", "Unsorted"])
    // A move past the end lands above Unsorted, never below it.
    store.moveFolders(fromOffsets: IndexSet(integer: 0), toOffset: 99)
    #expect(store.library.folders.last == "Unsorted")
    #expect(store.library.folders[4] == "Restaurants")
}

@Test func moveFoldersPersistsAcrossReload() throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    store.moveFolders(fromOffsets: IndexSet(integer: 4), toOffset: 0)
    store.flush()
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
    // Order is newest first: [3, b, a]. Remove b from the middle.
    let removed = try #require(store.remove(id: b.id))
    #expect(removed.index == 1)
    #expect(store.library.bookmarks.count == 2)
    store.restore(removed.bookmark, at: removed.index)
    #expect(store.library.bookmarks.map(\.id)[1] == b.id)
    #expect(store.library.bookmarks.map(\.id)[2] == a.id)
    // Restoring twice is a no-op.
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
