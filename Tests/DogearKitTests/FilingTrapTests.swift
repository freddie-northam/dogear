import Foundation
import Testing
@testable import DogearKit

/// Cases chosen because they are the ones that go wrong: a folder name hiding
/// inside another word, a keyword used as a metaphor, a domain that merely
/// looks like a hinted one, a title that tries to give instructions. Each has
/// one right answer, and `null` means the link must stay in Unsorted.
private struct FilingTrap: Decodable {
    let note: String
    let url: String
    let title: String
    let source: String
    let expected: String?
}

@Test func filesEveryTrapCaseCorrectly() async throws {
    let url = Bundle.module.url(
        forResource: "filing-traps", withExtension: "json", subdirectory: "Fixtures")!
    let traps = try JSONDecoder().decode([FilingTrap].self, from: Data(contentsOf: url))
    #expect(traps.count >= 20)

    // The folders a library gets after taking every suggestion, so the new
    // folders and the original ones compete on the same footing.
    let folders = ["Recipes", "Restaurants", "Shows", "Music", "Articles",
                   "Developer", "AI", "Design", Library.unsorted]
    let categorizer = KeywordCategorizer()

    var failures: [String] = []
    for trap in traps {
        let source = Source(rawValue: trap.source) ?? .web
        let metadata = FetchedMetadata(title: trap.title, source: source)
        let answer = await categorizer.categorize(
            metadata, url: URL(string: trap.url)!, folders: folders)
        if answer != trap.expected {
            failures.append("\(trap.note)\n    got \(answer ?? "nil"), wanted \(trap.expected ?? "nil")")
        }
    }
    #expect(failures.isEmpty, Comment(rawValue: "\n" + failures.joined(separator: "\n")))
}

/// Two folders can score the same, and the answer is then decided by where
/// they sit in the sidebar rather than by the title. That is worth pinning
/// down: it means reordering folders can change where new links are filed.
@Test func aTieIsBrokenByFolderOrder() async {
    let categorizer = KeywordCategorizer()
    // "AI" scores one, "software" scores one for Developer.
    let metadata = FetchedMetadata(title: "Why AI changes how we write software", source: .web)
    let url = URL(string: "https://example.com/tie")!

    let developerFirst = await categorizer.categorize(
        metadata, url: url, folders: ["Developer", "AI", Library.unsorted])
    let aiFirst = await categorizer.categorize(
        metadata, url: url, folders: ["AI", "Developer", Library.unsorted])

    #expect(developerFirst == "Developer")
    #expect(aiFirst == "AI")
}
