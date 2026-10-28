import Foundation
import Testing
@testable import DogearKit

private struct AccuracyEntry: Decodable {
    let title: String
    let description: String
    let url: String
    let expected: String
}

@Test func meetsSeventyPercentAccuracyOnFixtureSet() async throws {
    let fixtureURL = Bundle.module.url(forResource: "accuracy-set", withExtension: "json", subdirectory: "Fixtures")!
    let entries = try JSONDecoder().decode([AccuracyEntry].self, from: Data(contentsOf: fixtureURL))
    #expect(entries.count == 50)

    let categorizer = KeywordCategorizer()
    var correct = 0
    var perFolder: [String: (correct: Int, total: Int)] = [:]
    for entry in entries {
        let metadata = FetchedMetadata(title: entry.title, description: entry.description)
        let folder = await categorizer.categorize(metadata, url: URL(string: entry.url)!, folders: Library.defaultFolders)
        var tally = perFolder[entry.expected, default: (correct: 0, total: 0)]
        tally.total += 1
        if folder == entry.expected {
            correct += 1
            tally.correct += 1
        }
        perFolder[entry.expected] = tally
    }
    let accuracy = Double(correct) / Double(entries.count)
    let breakdown = perFolder.sorted { $0.key < $1.key }
        .map { "\($0.key): \($0.value.correct)/\($0.value.total)" }
        .joined(separator: ", ")
    #expect(accuracy >= 0.7, "accuracy \(accuracy) (\(correct)/\(entries.count)) [\(breakdown)]")
}

@Test func returnsNilWhenNothingMatches() async {
    let metadata = FetchedMetadata(title: "xkcd 927", description: nil)
    let folder = await KeywordCategorizer().categorize(metadata, url: URL(string: "https://xkcd.com/927")!, folders: Library.defaultFolders)
    #expect(folder == nil)
}

@Test func matchesCustomFolderByName() async {
    let metadata = FetchedMetadata(title: "Minimal home gym setup ideas", description: nil)
    let folder = await KeywordCategorizer().categorize(metadata, url: URL(string: "https://a.com")!, folders: ["Gym", "Unsorted"])
    #expect(folder == "Gym")
}

@Test func githubFilesToDeveloperWhenTheFolderExists() async {
    let metadata = FetchedMetadata(title: "swiftlang/swift", description: nil)
    let folder = await KeywordCategorizer().categorize(
        metadata, url: URL(string: "https://github.com/swiftlang/swift")!,
        folders: ["Developer", Library.unsorted])
    #expect(folder == "Developer")
}

@Test func githubStaysUnfiledWithoutADeveloperFolder() async {
    let metadata = FetchedMetadata(title: "swiftlang/swift", description: nil)
    let folder = await KeywordCategorizer().categorize(
        metadata, url: URL(string: "https://github.com/swiftlang/swift")!,
        folders: Library.defaultFolders)
    #expect(folder == nil)
}

@Test func xPostWithOneKeywordHitStaysUnfiled() async {
    let metadata = FetchedMetadata(title: "watch this demo tonight", description: nil, source: .x)
    let folder = await KeywordCategorizer().categorize(
        metadata, url: URL(string: "https://x.com/a/status/1")!, folders: Library.defaultFolders)
    #expect(folder == nil)
}

@Test func webPageWithOneKeywordHitStillFiles() async {
    let metadata = FetchedMetadata(title: "watch this demo tonight", description: nil, source: .web)
    let folder = await KeywordCategorizer().categorize(
        metadata, url: URL(string: "https://a.com")!, folders: Library.defaultFolders)
    #expect(folder == "Shows")
}

@Test func xPostWithTwoKeywordHitsStillFiles() async {
    let metadata = FetchedMetadata(title: "watch the season finale with me", description: nil, source: .x)
    let folder = await KeywordCategorizer().categorize(
        metadata, url: URL(string: "https://x.com/a/status/1")!, folders: Library.defaultFolders)
    #expect(folder == "Shows")
}

@Test func neverReturnsAFolderOutsideTheList() async {
    let metadata = FetchedMetadata(title: "Creamy pasta recipe", description: nil)
    let folder = await KeywordCategorizer().categorize(metadata, url: URL(string: "https://a.com")!, folders: ["Watchlist", "Unsorted"])
    #expect(folder == nil)
    #expect(folder != "Unsorted")
}

@Test func everyDefaultFolderIsFullyWired() throws {
    let fixtureURL = Bundle.module.url(forResource: "accuracy-set", withExtension: "json", subdirectory: "Fixtures")!
    let entries = try JSONDecoder().decode([AccuracyEntry].self, from: Data(contentsOf: fixtureURL))

    for folder in Library.defaultFolders where folder != Library.unsorted {
        #expect(!(KeywordCategorizer.keywords[folder] ?? []).isEmpty, "\(folder) has no keyword table entries")
        #expect(entries.contains { $0.expected == folder }, "\(folder) has no accuracy fixture entries")
        #expect(folderSymbol(for: folder) != "folder", "\(folder) has no distinct symbol")
        #expect(folderColor(for: folder) != folderColor(for: "SomeUnknownFolderName"), "\(folder) has no distinct color")
    }
}

private func file(_ title: String, in folders: [String], url: String = "https://a.com", source: Source = .web) async -> String? {
    await KeywordCategorizer().categorize(FetchedMetadata(title: title, description: nil, source: source),
                                          url: URL(string: url)!, folders: folders)
}

private let technical = ["Developer", "AI", "Design", Library.unsorted]

@Test(arguments: ["Check your email", "Now available in stores", "Meet the captain", "Said the maid"])
func aFolderNameMatchesOnlyAsAWholeWord(title: String) async {
    #expect(await file(title, in: ["AI", Library.unsorted]) == nil)
}

@Test(arguments: ["AI is eating software", "New ai: what changed", "(AI) roundup", "Thoughts on AI"])
func aFolderNameMatchesAtAnyWordBoundary(title: String) async {
    #expect(await file(title, in: ["AI", Library.unsorted]) == "AI")
}

@Test(arguments: ["C++", "R&D", "a.b", "(x)", "[y]", "*"])
func anOddFolderNameNeverCrashesOrLeavesTheList(name: String) async {
    let folders = [name, "Recipes", Library.unsorted]
    let titled = await file("Notes on \(name) today", in: folders)
    #expect(titled == nil || folders.contains(titled!))
    #expect(await file("Nothing related at all", in: folders) == nil)
}

@Test(arguments: ["Build a guide to quick wins", "A rapid summary", "Drag and drop storage", "Trust the process", "Click here"])
func aTechnicalKeywordInsideAnotherWordDoesNotFile(title: String) async {
    #expect(await file(title, in: technical) == nil)
}

@Test(arguments: [("Shipping a new shadcn block", "Design"), ("LLMs, agents and evals", "AI"),
                  ("Our Postgres migration", "Developer"), ("A new typeface for the web", "Design")])
func anXPostWithOneTechnicalHitFiles(title: String, expected: String) async {
    #expect(await file(title, in: technical, url: "https://x.com/a/status/1", source: .x) == expected)
}

@Test func anXPostWithOneChattyHitStillStaysUnfiledBesideTechnicalFolders() async {
    #expect(await file("watch this tonight", in: Library.defaultFolders + ["Developer", "AI", "Design"],
                       url: "https://x.com/a/status/1", source: .x) == nil)
}

@Test func technicalFoldersNeverFileWhenTheyAreNotInTheList() async {
    #expect(await file("Shipping a new shadcn block with an llm agent", in: Library.defaultFolders) == nil)
}

@Test func anOldFolderStillMatchesAKeywordInsideALongerWord() async {
    #expect(await file("We baked bread", in: Library.defaultFolders) == "Recipes")
}

@Test func equalScoresGoToTheFolderFirstInTheSidebar() async {
    let title = "A recipe album"
    #expect(await file(title, in: ["Recipes", "Music", Library.unsorted]) == "Recipes")
    #expect(await file(title, in: ["Music", "Recipes", Library.unsorted]) == "Music")
}
