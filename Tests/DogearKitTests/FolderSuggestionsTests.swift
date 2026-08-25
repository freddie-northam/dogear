import Foundation
import Testing
@testable import DogearKit

private func waiting(_ url: String, title: String = "", source: Source = .web) -> Bookmark {
    Bookmark(
        id: UUID(), url: url, title: title.isEmpty ? url : title, author: nil, note: nil,
        folder: Library.unsorted, source: source, createdAt: Date(), doneAt: nil,
        hasThumbnail: false, manuallyFiled: false
    )
}

@Test func suggestsAFolderTheCategorizerAlreadyKnowsHowToFill() async {
    let bookmarks = [
        waiting("https://github.com/apple/swift"),
        waiting("https://github.com/pointfreeco/swift-snapshot-testing"),
        waiting("https://gitlab.com/example/thing"),
    ]
    let plan = await FolderSuggestions.plan(
        for: bookmarks, folders: Library.defaultFolders
    )
    let developer = try! #require(plan.suggestions.first { $0.name == "Developer" })
    #expect(developer.count == 3)
}

@Test func doesNotSuggestAFolderThatAlreadyExists() async {
    let bookmarks = [waiting("https://github.com/apple/swift")]
    let plan = await FolderSuggestions.plan(
        for: bookmarks, folders: Library.defaultFolders + ["Developer"]
    )
    #expect(!plan.suggestions.contains { $0.name == "Developer" })
}

@Test func leavesOutAFolderThatWouldFileNothing() async {
    let bookmarks = [waiting("https://example.com/a-plain-page")]
    let plan = await FolderSuggestions.plan(
        for: bookmarks, folders: Library.defaultFolders
    )
    #expect(plan.suggestions.isEmpty)
}

@Test func countsOnlyBookmarksThatAreStillWaiting() async {
    var done = waiting("https://github.com/apple/swift")
    done.doneAt = Date()
    var filed = waiting("https://github.com/apple/swift-nio")
    filed.folder = "Articles"
    var pinned = waiting("https://github.com/apple/swift-log")
    pinned.manuallyFiled = true
    let plan = await FolderSuggestions.plan(
        for: [done, filed, pinned, waiting("https://github.com/apple/swift-syntax")],
        folders: Library.defaultFolders
    )
    let developer = try! #require(plan.suggestions.first { $0.name == "Developer" })
    // Only the one that is genuinely waiting: done, filed, and manually filed
    // bookmarks are not the app's to move.
    #expect(developer.count == 1)
}

@Test func carriesExamplesSoTheCountCanBeChecked() async {
    let bookmarks = (0..<5).map { waiting("https://github.com/apple/repo\($0)", title: "Repo \($0)") }
    let plan = await FolderSuggestions.plan(
        for: bookmarks, folders: Library.defaultFolders, exampleLimit: 2
    )
    let developer = try! #require(plan.suggestions.first)
    #expect(developer.count == 5)
    #expect(developer.examples.count == 2)
    #expect(developer.examples.allSatisfy { $0.hasPrefix("Repo ") })
}

@Test func ordersTheLargestSuggestionFirst() async {
    var bookmarks = (0..<4).map { waiting("https://github.com/apple/repo\($0)") }
    bookmarks.append(waiting("https://open.spotify.com/track/1", title: "A song"))
    let folders = ["Articles", Library.unsorted]
    let plan = await FolderSuggestions.plan(for: bookmarks, folders: folders)
    #expect(plan.suggestions.first?.name == "Developer")
    #expect(plan.suggestions.first?.count == 4)
    #expect(plan.suggestions.contains { $0.name == "Music" && $0.count == 1 })
}

@Test func suggestsNothingWhenNothingIsWaiting() async {
    let plan = await FolderSuggestions.plan(for: [], folders: Library.defaultFolders)
    #expect(plan.suggestions.isEmpty)
}

// The candidate list is read from the categorizer, so a rule added there is
// offered here without a second list to remember.
@Test func knownFoldersComeFromTheCategorizer() {
    #expect(FolderSuggestions.knownFolders.contains("Developer"))
    #expect(FolderSuggestions.knownFolders.contains("Music"))
    #expect(!FolderSuggestions.knownFolders.contains(Library.unsorted))
}

// Scoring each candidate on its own counted one bookmark under several
// folders, so the suggested counts could add up to more than were waiting.
@Test func neverCountsOneBookmarkUnderTwoFolders() async {
    // A title that scores for more than one of the candidate folders.
    let bookmarks = [
        waiting("https://example.com/1", title: "Building a typescript agent with a design system"),
        waiting("https://example.com/2", title: "A react component library and an llm prompt"),
    ]
    let plan = await FolderSuggestions.plan(
        for: bookmarks, folders: Library.defaultFolders
    )
    let counted = plan.suggestions.reduce(0) { $0 + $1.count }
    #expect(counted <= bookmarks.count)
}
