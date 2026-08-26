import Foundation
import Testing
@testable import DogearKit

private func bookmark(_ url: String, title: String, folder: String, done: Bool = false) -> Bookmark {
    Bookmark(id: UUID(), url: url, title: title, author: nil, note: nil,
             folder: folder, source: .web, createdAt: Date(timeIntervalSince1970: 1000),
             doneAt: done ? Date(timeIntervalSince1970: 2000) : nil,
             hasThumbnail: false, manuallyFiled: false)
}

@Test func markdownExportSectionsFollowTheUsersFolderOrder() throws {
    let library = Library(folders: ["Recipes", "Shows", "Unsorted"], bookmarks: [
        bookmark("https://a.com/show", title: "A Show", folder: "Shows"),
        bookmark("https://a.com/pasta", title: "Pasta", folder: "Recipes"),
    ])
    let markdown = MarkdownExport.export(library)
    let recipes = try #require(markdown.range(of: "## Recipes"))
    let shows = try #require(markdown.range(of: "## Shows"))
    #expect(recipes.lowerBound < shows.lowerBound)
    #expect(markdown.contains("- [Pasta](<https://a.com/pasta>)"))
}

@Test func markdownExportSkipsAnEmptyFolder() {
    let library = Library(folders: ["Recipes", "Shows", "Unsorted"], bookmarks: [
        bookmark("https://a.com/pasta", title: "Pasta", folder: "Recipes"),
    ])
    let markdown = MarkdownExport.export(library)
    #expect(markdown.contains("## Recipes"))
    #expect(!markdown.contains("## Shows"))
}

@Test func markdownExportPutsDoneBookmarksUnderArchiveLast() throws {
    let library = Library(folders: ["Recipes", "Unsorted"], bookmarks: [
        bookmark("https://a.com/old", title: "Cooked", folder: "Recipes", done: true),
        bookmark("https://a.com/new", title: "To Cook", folder: "Recipes"),
    ])
    let markdown = MarkdownExport.export(library)
    let recipes = try #require(markdown.range(of: "## Recipes"))
    let archive = try #require(markdown.range(of: "## Archive"))
    #expect(recipes.lowerBound < archive.lowerBound)
    let recipesSection = markdown[recipes.upperBound..<archive.lowerBound]
    #expect(recipesSection.contains("To Cook"))
    #expect(!recipesSection.contains("Cooked"))
}

@Test func markdownExportOfAFolderWhoseItemsAreAllDoneOmitsTheFolder() {
    let library = Library(folders: ["Recipes", "Unsorted"], bookmarks: [
        bookmark("https://a.com/old", title: "Cooked", folder: "Recipes", done: true),
    ])
    let markdown = MarkdownExport.export(library)
    #expect(!markdown.contains("## Recipes"))
    #expect(markdown.contains("## Archive"))
}

@Test func markdownExportOfAnEmptyLibraryIsEmpty() {
    #expect(MarkdownExport.export(Library(folders: Library.defaultFolders, bookmarks: [])).isEmpty)
}

@Test func markdownExportEscapesATitleThatWouldBreakTheLink() {
    let library = Library(folders: ["Recipes"], bookmarks: [
        bookmark("https://a.com/p", title: "A [bracketed] title", folder: "Recipes"),
    ])
    // Bookmark.markdownLink owns this rule; the export must not undo it.
    #expect(MarkdownExport.export(library).contains("- [A (bracketed) title](<https://a.com/p>)"))
}
