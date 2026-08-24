import Foundation
import Testing
@testable import DogearKit

@Test func routesTikTokHostsToTikTokFetcher() {
    #expect(MetadataService.fetcher(forHost: "www.tiktok.com") is TikTokFetcher)
    #expect(MetadataService.fetcher(forHost: "vm.tiktok.com") is TikTokFetcher)
}

@Test func routesXHostsToXFetcher() {
    #expect(MetadataService.fetcher(forHost: "x.com") is XFetcher)
    #expect(MetadataService.fetcher(forHost: "twitter.com") is XFetcher)
    #expect(MetadataService.fetcher(forHost: "mobile.twitter.com") is XFetcher)
}

@Test func routesEverythingElseToGeneric() {
    #expect(MetadataService.fetcher(forHost: "example.com") is GenericFetcher)
    #expect(MetadataService.fetcher(forHost: nil) is GenericFetcher)
}

@Test func resolvesShortLinkThenRoutesByFinalHost() async throws {
    let short = URL(string: "https://vm.tiktok.com/ZM2/")!
    let full = URL(string: "https://www.tiktok.com/@a/video/123")!
    let fixtureURL = Bundle.module.url(forResource: "tiktok-oembed", withExtension: "json", subdirectory: "Fixtures")!
    // The TikTok page body itself is irrelevant (TikTokFetcher doesn't parse it, it
    // calls the oEmbed endpoint), but the single-fetch flow still GETs it to learn the
    // resolved host, so it must be stubbed too.
    var stub = StubHTTPClient(responses: [
        full: Data(),
        TikTokFetcher.oembedURL(for: full): try Data(contentsOf: fixtureURL),
    ])
    stub.redirects = [short: full]

    let result = await MetadataService(client: stub).fetch(for: short)
    #expect(result.resolvedURL == full)
    #expect(result.metadata?.source == .tiktok)
}

@Test func fetchesTheResolvedPageExactlyOnce() async throws {
    let short = URL(string: "https://short.example/a")!
    let page = URL(string: "https://target.example/page")!
    let fixtureURL = Bundle.module.url(forResource: "generic-page", withExtension: "html", subdirectory: "Fixtures")!
    var stub = StubHTTPClient(responses: [page: try Data(contentsOf: fixtureURL)])
    stub.redirects = [short: page]

    let result = await MetadataService(client: stub).fetch(for: short)
    #expect(result.resolvedURL == page)
    #expect(result.metadata?.title == "How to Make Fresh Pasta 'Properly'")
    let requested = await stub.requestedURLs()
    #expect(requested.filter { $0 == page }.count == 1)
}

@Test func failureYieldsNilMetadataNotAnError() async {
    var stub = StubHTTPClient(responses: [:])
    stub.failEverything = true
    let url = URL(string: "https://example.com/x")!
    let result = await MetadataService(client: stub).fetch(for: url)
    #expect(result.resolvedURL == url)
    #expect(result.metadata == nil)
}

@Test func genericFetcherParsesFixture() async throws {
    let fixtureURL = Bundle.module.url(forResource: "generic-page", withExtension: "html", subdirectory: "Fixtures")!
    let pageURL = URL(string: "https://example.com/pasta")!
    let stub = StubHTTPClient(responses: [pageURL: try Data(contentsOf: fixtureURL)])
    let metadata = try await GenericFetcher().fetch(pageURL, client: stub)
    #expect(metadata.title == "How to Make Fresh Pasta 'Properly'")
    #expect(metadata.author == "Example Cooking") // og:site_name maps to author
    #expect(metadata.source == .web)
}

@Test func genericFetcherThrowsWhenNoTitleParses() async throws {
    let fixtureURL = Bundle.module.url(forResource: "malformed", withExtension: "html", subdirectory: "Fixtures")!
    let pageURL = URL(string: "https://example.com/malformed")!
    let stub = StubHTTPClient(responses: [pageURL: try Data(contentsOf: fixtureURL)])
    await #expect(throws: HTTPClientError.self) {
        _ = try await GenericFetcher().fetch(pageURL, client: stub)
    }
}

// A page controls its own title and site name. Both are capped where every
// fetcher returns them, so no fetcher can be the one that forgets.
@Test func capsARunawayTitleAndAuthor() {
    let long = String(repeating: "a", count: 5000)
    let metadata = FetchedMetadata(title: long, author: long, source: .web)
    let title = try! #require(metadata.title)
    let author = try! #require(metadata.author)
    #expect(title.count == FetchedMetadata.fieldLimit + 1)
    #expect(author.count == FetchedMetadata.fieldLimit + 1)
    #expect(title.hasSuffix("\u{2026}"))
}

@Test func leavesNormalMetadataAlone() {
    let metadata = FetchedMetadata(title: "A short title", author: "example.com", source: .web)
    #expect(metadata.title == "A short title")
    #expect(metadata.author == "example.com")
}

@Test func capsMetadataFromAnOEmbedEndpointToo() {
    // TikTok and X build their metadata from their own endpoints, not from a
    // parsed page, so the cap has to hold for them by construction.
    let long = String(repeating: "b", count: 5000)
    let metadata = FetchedMetadata(title: long, author: long, source: .tiktok)
    #expect(metadata.title?.count == FetchedMetadata.fieldLimit + 1)
    #expect(metadata.author?.count == FetchedMetadata.fieldLimit + 1)
}
