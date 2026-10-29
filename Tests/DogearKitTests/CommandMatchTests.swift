import Testing
@testable import DogearKit

@Test func aBlankQueryKeepsEveryTitleInOrder() {
    #expect(CommandMatch.rank(["b", "a", "c"], query: "") == [0, 1, 2])
    #expect(CommandMatch.rank(["b", "a", "c"], query: "  ") == [0, 1, 2])
}

@Test func caseAndAccentsDoNotMatter() {
    #expect(CommandMatch.rank(["Café list"], query: "CAFE") == [0])
}

@Test func aTitleStartComesBeforeALaterWordStart() {
    #expect(CommandMatch.rank(["Go to Recipes", "Rename Folder", "Export as Markdown"], query: "re") == [1, 0])
}

@Test func aMatchInsideAWordStillCounts() {
    #expect(CommandMatch.rank(["Archive", "Go to Unsorted", "Save from Clipboard"], query: "or") == [1])
}

@Test func aMatchInsideAWordComesAfterAWordStart() {
    #expect(CommandMatch.rank(["Go to Unsorted", "Order by Site"], query: "or") == [1, 0])
}

@Test func initialsMatchAfterPrefixMatches() {
    #expect(CommandMatch.rank(["Suggest Folders"], query: "sf") == [0])
    #expect(CommandMatch.rank(["Suggest Folders", "SF Maps"], query: "sf") == [1, 0])
}

@Test func noMatchGivesAnEmptyList() {
    #expect(CommandMatch.rank(["Archive"], query: "zzz").isEmpty)
}

@Test func tiesKeepTheOriginalOrder() {
    #expect(CommandMatch.rank(["Go A", "Go B", "Go C"], query: "go") == [0, 1, 2])
}
