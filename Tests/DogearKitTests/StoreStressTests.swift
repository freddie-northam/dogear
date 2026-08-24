import Foundation
import Testing
@testable import DogearKit

// The store writes on a background queue while the app mutates it from the
// main thread. These push both at once, so a sanitizer has something to see.

@Test func survivesInterleavedMutationsAndFlushes() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let store = try BookmarkStore(directory: dir)

    // The store is not thread safe by design: the app touches it from the main
    // thread only. What must survive is mutation racing its own write queue.
    for round in 0..<200 {
        _ = store.add(url: URL(string: "https://example.com/\(round)")!)
        if round % 7 == 0 { store.addFolder("Folder\(round)") }
        if round % 11 == 0 { store.flush() }
        if round % 13 == 0 {
            let ids = store.library.bookmarks.prefix(2).map(\.id)
            for id in ids { store.toggleFavorite(id: id) }
        }
    }
    store.flush()

    let reloaded = try BookmarkStore(directory: dir)
    #expect(reloaded.library.bookmarks.count == 200)
    #expect(reloaded.library.folders.contains("Folder0"))
    // Whatever the interleaving, the file on disk must be the state in memory.
    #expect(reloaded.library.bookmarks.map(\.id) == store.library.bookmarks.map(\.id))
    #expect(reloaded.library.folders == store.library.folders)
}

@Test func aBurstOfMutationsEndsWithEveryChangeOnDisk() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let store = try BookmarkStore(directory: dir)
    // No flush between any of these: the coalescing queue has to land them all.
    for i in 0..<500 { _ = store.add(url: URL(string: "https://example.com/burst/\(i)")!) }
    store.flush()
    let reloaded = try BookmarkStore(directory: dir)
    #expect(reloaded.library.bookmarks.count == 500)
}

@Test func repeatedFlushesFromManyTasksDoNotLoseAnything() async throws {
    let temp = TempDirectory()
    let dir = temp.url
    let store = try BookmarkStore(directory: dir)
    for i in 0..<50 { _ = store.add(url: URL(string: "https://example.com/f/\(i)")!) }
    // flush() is writeQueue.sync; several at once must serialise, not deadlock.
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<16 { group.addTask { store.flush() } }
    }
    let reloaded = try BookmarkStore(directory: dir)
    #expect(reloaded.library.bookmarks.count == 50)
}
