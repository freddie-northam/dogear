import Foundation
import Testing
@testable import DogearKit

private var canaryEnabled: Bool {
    ProcessInfo.processInfo.environment["CANARY"] != nil
}

@Test(.enabled(if: canaryEnabled)) func tikTokPageDataStillWorks() async throws {
    let url = URL(string: "https://www.tiktok.com/@gordonramsayofficial/video/7510682972576746775")!
    // The service path, the one a capture runs, so the canary also covers the 1 MB page limit.
    let metadata = try #require(await MetadataService(client: URLSessionHTTPClient()).fetch(for: url).metadata)
    #expect(metadata.source == .tiktok)
    #expect(metadata.author == "Gordon Ramsay")
    #expect(metadata.title != nil)
    #expect(metadata.thumbnailURL != nil)
}

@Test(.enabled(if: canaryEnabled)) func xOpenGraphStillWorks() async throws {
    let url = URL(string: "https://x.com/jack/status/20")!
    let metadata = try await XFetcher().fetch(url, client: URLSessionHTTPClient())
    #expect(metadata.description == "just setting up my twttr")
    #expect(metadata.author?.contains("jack") == true)
}
