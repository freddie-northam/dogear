import Foundation
import Testing
@testable import DogearKit

@Test func freshURLsDropsAlreadySavedLinksCanonically() {
    let found = [
        URL(string: "https://Example.com/a/")!,
        URL(string: "https://b.com/x")!,
    ]
    // Already saved under its canonical form (lowercase host, no trailing slash).
    let existing: Set<String> = ["https://example.com/a"]
    let fresh = NotesImportPlanning.freshURLs(found, existing: existing)
    #expect(fresh.map(\.absoluteString) == ["https://b.com/x"])
}

@Test func freshURLsPreservesInputOrder() {
    let found = [
        URL(string: "https://a.com/1")!,
        URL(string: "https://b.com/2")!,
        URL(string: "https://c.com/3")!,
    ]
    let fresh = NotesImportPlanning.freshURLs(found, existing: [])
    #expect(fresh.map(\.absoluteString) == ["https://a.com/1", "https://b.com/2", "https://c.com/3"])
}
