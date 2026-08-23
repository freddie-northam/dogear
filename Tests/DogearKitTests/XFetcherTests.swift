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

private func xHTML(image: String) -> Data {
    Data("""
    <html><head>
    <meta property="og:title" content="jack on X">
    <meta property="og:description" content="just setting up my twttr">
    <meta property="og:image" content="\(image)">
    </head></html>
    """.utf8)
}

@Test func dropsAvatarOGImage() async throws {
    let tweetURL = URL(string: "https://x.com/a/status/2")!
    let stub = StubHTTPClient(responses: [
        tweetURL: xHTML(image: "https://pbs.twimg.com/profile_images/123/me_400x400.jpg"),
    ])
    let metadata = try await XFetcher().fetch(tweetURL, client: stub)
    #expect(metadata.thumbnailURL == nil)
}

@Test func keepsTweetMediaOGImage() async throws {
    let tweetURL = URL(string: "https://x.com/a/status/3")!
    let stub = StubHTTPClient(responses: [
        tweetURL: xHTML(image: "https://pbs.twimg.com/media/Fabc123.jpg"),
    ])
    let metadata = try await XFetcher().fetch(tweetURL, client: stub)
    #expect(metadata.thumbnailURL?.absoluteString == "https://pbs.twimg.com/media/Fabc123.jpg")
}

@Test func throwsWhenNoOGDescription() async {
    let tweetURL = URL(string: "https://x.com/a/status/1")!
    let stub = StubHTTPClient(responses: [tweetURL: Data("<html><head></head></html>".utf8)])
    await #expect(throws: Error.self) {
        _ = try await XFetcher().fetch(tweetURL, client: stub)
    }
}
