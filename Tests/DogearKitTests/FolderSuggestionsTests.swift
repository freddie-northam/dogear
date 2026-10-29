import Foundation
import Testing
@testable import DogearKit

private func storeWithUnsorted(_ titles: [String], folders extra: [String] = []) throws -> (BookmarkStore, TempDirectory) {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    extra.forEach(store.addFolder)
    for (i, title) in titles.enumerated() { _ = store.addForTesting(urlString: "https://a.com/\(i)", title: title) }
    return (store, temp)
}

private let developerTitles = ["Our Postgres migration", "A Rust compiler trick", "Docker for beginners", "Kubernetes at home"]
private let aiTitles = ["LLM evals in practice", "Agents and prompts", "Fine-tuning a small model"]

@Test func suggestsOnlyFoldersTheLibraryLacksInAnyCase() async throws {
    let (store, _) = try storeWithUnsorted(developerTitles + aiTitles, folders: ["ai"])
    let suggestions = await FolderSuggestions.suggest(for: store.library)
    #expect(suggestions.map(\.folder) == ["Developer"])
}

@Test func eachLinkCountsOnceAndOnlyUnsortedWaitingLinksCount() async throws {
    let (store, _) = try storeWithUnsorted(developerTitles + aiTitles + ["Docker and LLM agents together"])
    let done = store.addForTesting(urlString: "https://a.com/done", title: "Postgres tips")
    store.markDone(id: done.id)
    let filed = store.addForTesting(urlString: "https://a.com/filed", title: "Postgres in Recipes")
    store.refile(id: filed.id, to: "Recipes")
    let suggestions = await FolderSuggestions.suggest(for: store.library)
    let ids = suggestions.flatMap(\.ids)
    #expect(Set(ids).count == ids.count)
    #expect(!ids.contains(done.id) && !ids.contains(filed.id))
    #expect(ids.count == 8)
}

@Test func aFolderThatTwoLinksWouldFillIsNotSuggested() async throws {
    let (store, _) = try storeWithUnsorted(developerTitles + ["A new typeface", "Figma tips"])
    #expect(await FolderSuggestions.suggest(for: store.library).map(\.folder) == ["Developer"])
}

@Test func suggestionsComeLargestFirstAndTheSameEachRun() async throws {
    let (store, _) = try storeWithUnsorted(aiTitles + developerTitles)
    let first = await FolderSuggestions.suggest(for: store.library)
    #expect(first.map(\.folder) == ["Developer", "AI"])
    #expect(await FolderSuggestions.suggest(for: store.library) == first)
}

@Test func acceptCreatesTheFolderAndFilesOnlyLinksStillInUnsorted() async throws {
    let (store, _) = try storeWithUnsorted(developerTitles)
    let before = store.library
    let suggestion = try #require(await FolderSuggestions.suggest(for: store.library).first)
    #expect(store.library == before)
    store.refile(id: suggestion.ids[0], to: "Articles")
    #expect(store.accept([suggestion]) == 3)
    #expect(store.library.folders.contains("Developer"))
    #expect(store.bookmarks(in: "Developer").count == 3)
    #expect(store.library.bookmarks.first { $0.id == suggestion.ids[0] }?.folder == "Articles")
}

@Test(arguments: KeywordCategorizer.keywords.keys.sorted())
func everyFolderDogearCanSuggestHasItsOwnIconAndColor(folder: String) {
    #expect(folderSymbol(for: folder) != folderSymbol(for: "SomeUnknownFolderName"))
    #expect(folderColor(for: folder) != folderColor(for: "SomeUnknownFolderName"))
}
