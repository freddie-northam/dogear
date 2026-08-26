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

@Test func exportSectionsDropsEmptyFoldersAndPutsTheArchiveLast() {
    let library = Library(folders: ["Recipes", "Shows", "Unsorted"], bookmarks: [
        bookmark("https://a.com/old", title: "Cooked", folder: "Recipes", done: true),
        bookmark("https://a.com/new", title: "To Cook", folder: "Recipes"),
        bookmark("https://a.com/tacos", title: "Tacos", folder: "Unsorted"),
    ])
    let sections = library.exportSections
    #expect(sections.map(\.name) == ["Recipes", "Unsorted", "Archive"])
    #expect(sections[0].bookmarks.map(\.title) == ["To Cook"])
    #expect(sections[2].bookmarks.map(\.title) == ["Cooked"])
}

@Test func exportSectionsAreEmptyForAnEmptyLibrary() {
    #expect(Library(folders: Library.defaultFolders, bookmarks: []).exportSections.isEmpty)
}

@Test func bothExportersAgreeOnWhichSectionsExist() {
    let library = Library(folders: ["Recipes", "Shows", "Unsorted"], bookmarks: [
        bookmark("https://a.com/old", title: "Cooked", folder: "Recipes", done: true),
        bookmark("https://a.com/new", title: "To Cook", folder: "Recipes"),
    ])
    // The two exporters used to walk this shape separately and had to agree by
    // hand. They read one list now, so this pins that they still do.
    let markdown = MarkdownExport.export(library)
    let html = BookmarksHTML.export(library)
    for section in library.exportSections {
        #expect(markdown.contains("## \(section.name)"))
        #expect(html.contains("<H3>\(section.name)</H3>"))
    }
    #expect(!markdown.contains("## Shows"))
    #expect(!html.contains("<H3>Shows</H3>"))
}
