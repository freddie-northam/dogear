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
    #expect(!html.contains("<b>title"))
}

@Test func exportRoundTripsBackThroughTheImporter() {
    let library = Library(folders: ["Recipes", "Unsorted"], bookmarks: [
        bookmark("https://a.com/p?x=1&y=2", title: "Pasta", folder: "Recipes"),
        bookmark("https://b.com/tacos", title: "Tacos", folder: "Unsorted"),
        bookmark("https://c.com/old", title: "Old", folder: "Recipes", done: true),
        bookmark("https://d.com/q?s=\"x\"", title: "d.com/q", folder: "Unsorted"),
    ])
    let recovered = BookmarksHTML.links(in: BookmarksHTML.export(library)).map(\.absoluteString)
    #expect(Set(recovered) == ["https://a.com/p?x=1&y=2", "https://b.com/tacos", "https://c.com/old",
                               "https://d.com/q?s=%22x%22"])
}

@Test func linksReadsOnlyTheHrefOfEachBookmark() {
    let html = """
        <DT><a href="https://a.com/1" ADD_DATE="1">see https://not-a-bookmark.com in a.com/2</a>
        <DD>Notes mention https://also-not.com
        <DT><A HREF="https://b.com/x?a=1&amp;b=2">B</A>
        <DT><A HREF="place:sort=8">Firefox smart folder</A>
        <DT><A HREF = 'https://c.com/single'>C</A>
        <DT><A HREF="https://en.wikipedia.org/wiki/Bob&#39;s_Burgers">D</A>
        <DT><A data-href="https://not-a-bookmark.com/data" HREF="https://e.com/real">E</A>
        """
    #expect(BookmarksHTML.links(in: html).map(\.absoluteString) == [
        "https://a.com/1", "https://b.com/x?a=1&b=2", "https://c.com/single",
        "https://en.wikipedia.org/wiki/Bob's_Burgers", "https://e.com/real",
    ])
}

@Test func exportOfAnEmptyLibraryIsStillAValidBookmarkFile() {
    let html = BookmarksHTML.export(Library(folders: Library.defaultFolders, bookmarks: []))
    #expect(html.hasPrefix("<!DOCTYPE NETSCAPE-Bookmark-file-1>"))
    #expect(html.contains("<DL><p>"))
    #expect(html.contains("</DL><p>"))
}
