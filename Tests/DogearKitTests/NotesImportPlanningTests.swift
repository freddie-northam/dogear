import Foundation
import Testing
@testable import DogearKit

@Test func freshURLsDropsAlreadySavedLinksCanonically() {
    let found = [
        URL(string: "https://Example.com/a/")!,
        URL(string: "https://b.com/x")!,
    ]
    // Already saved under its canonical form (lowercase host, no trailing slash).
    let existing: Set<String> = ["https://example.com/a"]
    let fresh = NotesImportPlanning.freshURLs(found, existing: existing)
    #expect(fresh.map(\.absoluteString) == ["https://b.com/x"])
}

@Test func freshURLsPreservesInputOrder() {
    let found = [
        URL(string: "https://a.com/1")!,
        URL(string: "https://b.com/2")!,
        URL(string: "https://c.com/3")!,
    ]
    let fresh = NotesImportPlanning.freshURLs(found, existing: [])
    #expect(fresh.map(\.absoluteString) == ["https://a.com/1", "https://b.com/2", "https://c.com/3"])
}

@Test func secondsSinceIsNilForAFolderWithNoEntry() {
    let cursors = NotesImportCursors()
    #expect(cursors.secondsSince(folderID: "f1", now: Date()) == nil)
}

@Test func secondsSinceAddsAMinuteOfSkewMargin() {
    let now = Date()
    var cursors = NotesImportCursors()
    cursors.lastImport["f1"] = now.addingTimeInterval(-3600)
    #expect(cursors.secondsSince(folderID: "f1", now: now) == 3660)
}

@Test func recordThenSecondsSinceReflectsTheSkewMarginOnly() {
    let now = Date()
    var cursors = NotesImportCursors()
    cursors.record(folderID: "f1", at: now)
    #expect(cursors.secondsSince(folderID: "f1", now: now) == 60)
}

@Test func pruneDropsIdsNotInTheKeptSet() {
    var cursors = NotesImportCursors()
    cursors.lastImport["f1"] = Date()
    cursors.lastImport["f2"] = Date()
    cursors.prune(keeping: ["f1"])
    #expect(cursors.lastImport.keys.sorted() == ["f1"])
}

@Test func cursorsRoundTripThroughJSON() {
    var cursors = NotesImportCursors()
    cursors.record(folderID: "f1", at: Date(timeIntervalSince1970: 1_000_000))
    let data = try! JSONEncoder().encode(cursors)
    let decoded = try! JSONDecoder().decode(NotesImportCursors.self, from: data)
    #expect(decoded == cursors)
}
