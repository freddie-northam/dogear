import Foundation
import Testing
@testable import DogearKit

@Test func bookmarkRoundTripsThroughJSON() throws {
    let bookmark = Bookmark(
        id: UUID(), url: "https://example.com/a", title: "A",
        author: "Author", note: nil, folder: "Recipes", source: .web,
        createdAt: Date(timeIntervalSince1970: 1_000_000), doneAt: nil,
        hasThumbnail: false, manuallyFiled: false
    )
    let library = Library(folders: Library.defaultFolders, bookmarks: [bookmark])
    let data = try JSONEncoder().encode(library)
    let decoded = try JSONDecoder().decode(Library.self, from: data)
    #expect(decoded == library)
}

@Test func defaultFoldersMatchSpec() {
    #expect(Library.defaultFolders == ["Recipes", "Restaurants", "Shows", "Music", "Articles", "Unsorted"])
}

private func makeBookmark(title: String, url: String) -> Bookmark {
    Bookmark(
        id: UUID(), url: url, title: title, author: nil, note: nil,
        folder: Library.unsorted, source: .web, createdAt: Date(), doneAt: nil,
        hasThumbnail: false, manuallyFiled: false
    )
}

@Test func markdownLinkFormatsTitleAndURL() {
    let bookmark = makeBookmark(title: "Creamy pasta", url: "https://a.com/pasta")
    #expect(bookmark.markdownLink == "[Creamy pasta](https://a.com/pasta)")
}

@Test func markdownLinkReplacesSquareBracketsInTheTitle() {
    let bookmark = makeBookmark(title: "[2024] Best ramen [ranked]", url: "https://a.com/ramen")
    #expect(bookmark.markdownLink == "[(2024) Best ramen (ranked)](https://a.com/ramen)")
}

@Test func markdownListProducesOneBulletPerBookmark() {
    let list = Bookmark.markdownList([
        makeBookmark(title: "A", url: "https://a.com/1"),
        makeBookmark(title: "B", url: "https://a.com/2"),
    ])
    #expect(list == "- [A](https://a.com/1)\n- [B](https://a.com/2)")
}
