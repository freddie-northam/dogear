import Foundation
import Testing
@testable import DogearKit

private var canaryEnabled: Bool {
    ProcessInfo.processInfo.environment["CANARY"] != nil
}

@Test(.enabled(if: canaryEnabled)) func tikTokOEmbedStillWorks() async throws {
    let url = URL(string: "https://www.tiktok.com/@gordonramsayofficial/video/7510682972576746775")!
    let metadata = try await TikTokFetcher().fetch(url, client: URLSessionHTTPClient())
    #expect(metadata.author != nil)
    #expect(metadata.title != nil)
}

@Test(.enabled(if: canaryEnabled)) func xOpenGraphStillWorks() async throws {
    let url = URL(string: "https://x.com/jack/status/20")!
    let metadata = try await XFetcher().fetch(url, client: URLSessionHTTPClient())
    #expect(metadata.description == "just setting up my twttr")
    #expect(metadata.author?.contains("jack") == true)
}
