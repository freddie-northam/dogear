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
    // Recipes is deliberately excluded from the folder list, so the categorizer
    // must not invent it, and Unsorted is never returned directly by the keyword path.
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

// The folder's own name counts as a keyword, but a substring match let a
// folder named "AI" score on "email" and "available".
@Test func theFolderNameCountsOnlyAsAWholeWord() {
    #expect(KeywordCategorizer.containsWord("ai", in: "ai agents are here"))
    #expect(KeywordCategorizer.containsWord("ai", in: "about ai"))
    #expect(KeywordCategorizer.containsWord("ai", in: "ai"))
    #expect(!KeywordCategorizer.containsWord("ai", in: "check your email"))
    #expect(!KeywordCategorizer.containsWord("ai", in: "available now"))
    #expect(!KeywordCategorizer.containsWord("ai", in: "captain"))
    // A digit or a dash is not a letter, so these still count as the word.
    #expect(KeywordCategorizer.containsWord("ai", in: "ai-native tools"))
    #expect(!KeywordCategorizer.containsWord("", in: "anything"))
}

@Test func aFolderNamedAIDoesNotSwallowEveryEmail() async {
    let folders = ["AI", "Articles", Library.unsorted]
    let metadata = FetchedMetadata(
        title: "The available email templates you should steal", source: .web)
    let folder = await KeywordCategorizer().categorize(
        metadata, url: URL(string: "https://example.com/x")!, folders: folders)
    #expect(folder != "AI")
}

// A technical term in a post means the term. A conversational one may not, so
// only the conversational folders hold X posts to two hits.
@Test func anXPostFilesOnOneTechnicalHit() async {
    let folders = ["Developer", "Shows", Library.unsorted]
    let metadata = FetchedMetadata(
        title: "Alice (@alice): shadcn just shipped something great", source: .x)
    let folder = await KeywordCategorizer().categorize(
        metadata, url: URL(string: "https://x.com/alice/status/1")!, folders: folders)
    #expect(folder == "Developer")
}

@Test func anXPostStillNeedsTwoConversationalHits() async {
    let folders = ["Shows", "Developer", Library.unsorted]
    let metadata = FetchedMetadata(
        title: "Alice (@alice): you have to watch what happens next", source: .x)
    let folder = await KeywordCategorizer().categorize(
        metadata, url: URL(string: "https://x.com/alice/status/2")!, folders: folders)
    #expect(folder != "Shows")
}

@Test func theNewFoldersOnlyFireWhenTheyExist() async {
    let metadata = FetchedMetadata(title: "A typescript framework for agents", source: .web)
    let url = URL(string: "https://example.com/a")!
    let without = await KeywordCategorizer().categorize(
        metadata, url: url, folders: Library.defaultFolders)
    #expect(without == nil)
    let with = await KeywordCategorizer().categorize(
        metadata, url: url, folders: Library.defaultFolders + ["Developer"])
    #expect(with == "Developer")
}
