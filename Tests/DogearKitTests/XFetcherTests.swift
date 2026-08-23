import Foundation
import Testing
@testable import DogearKit

@Test func composesTitleFromAuthorAndTweetText() async throws {
    let fixtureURL = Bundle.module.url(forResource: "x-page", withExtension: "html", subdirectory: "Fixtures")!
    let tweetURL = URL(string: "https://x.com/jack/status/20")!
    let stub = StubHTTPClient(responses: [tweetURL: try Data(contentsOf: fixtureURL)])

    let metadata = try await XFetcher().fetch(tweetURL, client: stub)
    #expect(metadata.source == .x)
    #expect(metadata.author?.contains("jack") == true)
    #expect(metadata.author?.contains(" on X") != true)
    #expect(metadata.title?.contains("just setting up my twttr") == true)
    #expect(metadata.description == "just setting up my twttr")
}

@Test func truncatesLongTweetTextInTitle() {
    let long = String(repeating: "word ", count: 40)
    let title = XFetcher.composeTitle(author: "someone", text: long)
    #expect(title.count <= "someone: ".count + 81) // 80 chars + ellipsis
    #expect(title.hasSuffix("…"))
}

@Test func throwsWhenNoOGDescription() async {
    let tweetURL = URL(string: "https://x.com/a/status/1")!
    let stub = StubHTTPClient(responses: [tweetURL: Data("<html><head></head></html>".utf8)])
    await #expect(throws: Error.self) {
        _ = try await XFetcher().fetch(tweetURL, client: stub)
    }
}
