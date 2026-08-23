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
    #expect(entries.count == 40)

    let categorizer = KeywordCategorizer()
    var correct = 0
    for entry in entries {
        let metadata = FetchedMetadata(title: entry.title, description: entry.description)
        let folder = await categorizer.categorize(metadata, url: URL(string: entry.url)!, folders: Library.defaultFolders)
        if folder == entry.expected { correct += 1 }
    }
    let accuracy = Double(correct) / Double(entries.count)
    #expect(accuracy >= 0.7, "accuracy \(accuracy) (\(correct)/40)")
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

@Test func githubFilesToCodeWhenTheFolderExists() async {
    let metadata = FetchedMetadata(title: "swiftlang/swift", description: nil)
    let folder = await KeywordCategorizer().categorize(
        metadata, url: URL(string: "https://github.com/swiftlang/swift")!,
        folders: ["Code", Library.unsorted])
    #expect(folder == "Code")
}

@Test func githubStaysUnfiledWithoutACodeFolder() async {
    let metadata = FetchedMetadata(title: "swiftlang/swift", description: nil)
    let folder = await KeywordCategorizer().categorize(
        metadata, url: URL(string: "https://github.com/swiftlang/swift")!,
        folders: Library.defaultFolders)
    #expect(folder == nil)
}

@Test func neverReturnsAFolderOutsideTheList() async {
    let metadata = FetchedMetadata(title: "Creamy pasta recipe", description: nil)
    let folder = await KeywordCategorizer().categorize(metadata, url: URL(string: "https://a.com")!, folders: ["Watchlist", "Unsorted"])
    #expect(folder == nil || folder == "Watchlist" || folder == "Unsorted")
}
