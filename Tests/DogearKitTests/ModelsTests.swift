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
    #expect(Library.defaultFolders == ["Recipes", "Restaurants", "Shows", "Articles", "Unsorted"])
}
