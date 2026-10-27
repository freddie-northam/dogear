import Foundation
import Testing
@testable import DogearKit

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
