import Foundation
import Testing
@testable import DogearKit

private func bookmark(_ url: String, title: String, folder: String,
                      note: String? = nil, done: Bool = false) -> Bookmark {
    Bookmark(id: UUID(), url: url, title: title, author: nil, note: note,
             folder: folder, source: .web, createdAt: Date(timeIntervalSince1970: 1000),
             doneAt: done ? Date(timeIntervalSince1970: 2000) : nil,
             hasThumbnail: false, manuallyFiled: false)
}

@Test func exportGroupsBookmarksByFolderInTheUsersOrder() {
    let library = Library(folders: ["Recipes", "Shows", "Unsorted"], bookmarks: [
        bookmark("https://a.com/show", title: "A Show", folder: "Shows"),
        bookmark("https://a.com/pasta", title: "Pasta", folder: "Recipes"),
    ])
    let html = BookmarksHTML.export(library)
    let recipes = try! #require(html.range(of: "<H3>Recipes</H3>"))
    let shows = try! #require(html.range(of: "<H3>Shows</H3>"))
    #expect(recipes.lowerBound < shows.lowerBound)
    #expect(html.contains(">Pasta</A>"))
    #expect(html.contains(">A Show</A>"))
}

@Test func exportSkipsAnEmptyFolder() {
    let library = Library(folders: ["Recipes", "Shows", "Unsorted"], bookmarks: [
        bookmark("https://a.com/pasta", title: "Pasta", folder: "Recipes"),
    ])
    let html = BookmarksHTML.export(library)
    #expect(html.contains("<H3>Recipes</H3>"))
    #expect(!html.contains("<H3>Shows</H3>"))
}

@Test func exportPutsDoneBookmarksInAnArchiveSectionLast() {
    let library = Library(folders: ["Recipes", "Unsorted"], bookmarks: [
        bookmark("https://a.com/old", title: "Cooked", folder: "Recipes", done: true),
        bookmark("https://a.com/new", title: "To Cook", folder: "Recipes"),
    ])
    let html = BookmarksHTML.export(library)
    let recipes = try! #require(html.range(of: "<H3>Recipes</H3>"))
    let archive = try! #require(html.range(of: "<H3>Archive</H3>"))
    #expect(recipes.lowerBound < archive.lowerBound)
    // A done bookmark leaves its folder section, exactly as it leaves the app.
    let recipesSection = html[recipes.upperBound..<archive.lowerBound]
    #expect(recipesSection.contains("To Cook"))
    #expect(!recipesSection.contains("Cooked"))
}

@Test func exportWritesTheNoteAsADescription() {
    let library = Library(folders: ["Recipes"], bookmarks: [
        bookmark("https://a.com/p", title: "Pasta", folder: "Recipes", note: "Halve the salt.\nUse bronze cut."),
    ])
    let html = BookmarksHTML.export(library)
    #expect(html.contains("<DD>Halve the salt. Use bronze cut."))
}

@Test func exportEscapesMarkupInTitlesFoldersAndURLs() {
    let library = Library(folders: ["Fish & <Chips>"], bookmarks: [
        bookmark("https://a.com/p?x=1&y=2", title: "A \"quoted\" <b>title</b>", folder: "Fish & <Chips>"),
    ])
    let html = BookmarksHTML.export(library)
    #expect(html.contains("<H3>Fish &amp; &lt;Chips&gt;</H3>"))
    #expect(html.contains("&quot;quoted&quot; &lt;b&gt;title&lt;/b&gt;"))
    #expect(html.contains("HREF=\"https://a.com/p?x=1&amp;y=2\""))
    // Nothing the user typed may close a tag or an attribute.
    #expect(!html.contains("<b>title"))
}

@Test func exportRoundTripsBackThroughTheImporter() {
    let library = Library(folders: ["Recipes", "Unsorted"], bookmarks: [
        bookmark("https://a.com/p?x=1&y=2", title: "Pasta", folder: "Recipes"),
        bookmark("https://b.com/tacos", title: "Tacos", folder: "Unsorted"),
        bookmark("https://c.com/old", title: "Old", folder: "Recipes", done: true),
    ])
    let recovered = URLCleaner.allHTTPURLs(inHTML: BookmarksHTML.export(library)).map(\.absoluteString)
    #expect(recovered.contains("https://a.com/p?x=1&y=2"))
    #expect(recovered.contains("https://b.com/tacos"))
    #expect(recovered.contains("https://c.com/old"))
}

@Test func exportOfAnEmptyLibraryIsStillAValidBookmarkFile() {
    let html = BookmarksHTML.export(Library(folders: Library.defaultFolders, bookmarks: []))
    #expect(html.hasPrefix("<!DOCTYPE NETSCAPE-Bookmark-file-1>"))
    #expect(html.contains("<DL><p>"))
    #expect(html.contains("</DL><p>"))
}
