import Foundation
import Testing
@testable import DogearKit

@Test func parsesRealOEmbedFixture() async throws {
    let fixtureURL = Bundle.module.url(forResource: "tiktok-oembed", withExtension: "json", subdirectory: "Fixtures")!
    let videoURL = URL(string: "https://www.tiktok.com/@gordonramsayofficial/video/7510682972576746775")!
    let oembedURL = TikTokFetcher.oembedURL(for: videoURL)
    let stub = StubHTTPClient(responses: [oembedURL: try Data(contentsOf: fixtureURL)])

    let metadata = try await TikTokFetcher().fetch(videoURL, client: stub)
    #expect(metadata.source == .tiktok)
    #expect(metadata.author == "Gordon Ramsay")
    #expect(metadata.title?.contains("cook") == true)
    #expect(metadata.thumbnailURL != nil)
}

@Test func throwsOnErrorJSON() async {
    let videoURL = URL(string: "https://www.tiktok.com/@x/video/1")!
    let stub = StubHTTPClient(responses: [
        TikTokFetcher.oembedURL(for: videoURL): Data(#"{"message":"Something went wrong","code":400}"#.utf8)
    ])
    await #expect(throws: Error.self) {
        _ = try await TikTokFetcher().fetch(videoURL, client: stub)
    }
}

@Test func buildsOEmbedURLWithTheVideoURLAsAQueryValue() {
    let url = TikTokFetcher.oembedURL(for: URL(string: "https://www.tiktok.com/@a/video/1")!)
    #expect(url.absoluteString == "https://www.tiktok.com/oembed?url=https://www.tiktok.com/@a/video/1")
}
