import Foundation
import Testing
@testable import DogearKit

@MainActor
private func makeEnvironment(client: StubHTTPClient) throws -> (BookmarkStore, EnrichmentService) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try BookmarkStore(directory: dir)
    let service = EnrichmentService(
        store: store,
        metadata: MetadataService(client: client),
        categorizer: KeywordCategorizer(),
        thumbnails: try ThumbnailCache(directory: dir.appendingPathComponent("thumbnails")),
        client: client
    )
    return (store, service)
}

@Test func enrichesTitleAuthorSourceAndCategory() async throws {
    let pageURL = URL(string: "https://example.com/pasta")!
    let html = try Data(contentsOf: Bundle.module.url(forResource: "generic-page", withExtension: "html", subdirectory: "Fixtures")!)
    let (store, service) = try await makeEnvironment(client: StubHTTPClient(responses: [pageURL: html]))

    let (bookmark, _) = store.add(url: pageURL)
    await service.enrich(id: bookmark.id)

    let enriched = store.library.bookmarks[0]
    #expect(enriched.title == "How to Make Fresh Pasta 'Properly'")
    #expect(enriched.folder == "Recipes")
    #expect(!enriched.manuallyFiled)
}

@Test func networkFailureLeavesBareBookmark() async throws {
    var client = StubHTTPClient(responses: [:])
    client.failEverything = true
    let (store, service) = try await makeEnvironment(client: client)

    let (bookmark, _) = store.add(url: URL(string: "https://example.com/gone")!)
    await service.enrich(id: bookmark.id)

    let after = store.library.bookmarks[0]
    #expect(after.folder == Library.unsorted)
    #expect(after.title == "example.com/gone")
    // The bookmark persisted: the offline integration requirement.
    #expect(store.library.bookmarks.count == 1)
}

@Test func manualRefileIsNeverOverwritten() async throws {
    let pageURL = URL(string: "https://example.com/pasta")!
    let html = try Data(contentsOf: Bundle.module.url(forResource: "generic-page", withExtension: "html", subdirectory: "Fixtures")!)
    let (store, service) = try await makeEnvironment(client: StubHTTPClient(responses: [pageURL: html]))

    let (bookmark, _) = store.add(url: pageURL)
    store.refile(id: bookmark.id, to: "Articles")
    await service.enrich(id: bookmark.id)

    #expect(store.library.bookmarks[0].folder == "Articles")
}

@Test func unknownCategoryFallsBackToUnsorted() async throws {
    let pageURL = URL(string: "https://example.com/pasta")!
    let html = try Data(contentsOf: Bundle.module.url(forResource: "generic-page", withExtension: "html", subdirectory: "Fixtures")!)
    let (store, service) = try await makeEnvironment(client: StubHTTPClient(responses: [pageURL: html]))
    store.removeFolder("Recipes")

    let (bookmark, _) = store.add(url: pageURL)
    await service.enrich(id: bookmark.id)

    #expect(store.library.bookmarks[0].folder == Library.unsorted)
}

// Wraps a StubHTTPClient and runs a closure on the Nth `data(from:limit:)` call (1-based),
// so tests can simulate a concurrent store edit landing during a specific await inside
// enrichment: call 1 is the metadata.fetch's page download, call 2 is the thumbnail
// download that happens after enrichment's post-fetch re-read.
// @unchecked Sendable: `count` is only ever touched serially, from the single MainActor
// task driving enrich() in these tests, never concurrently.
private final class InterceptingHTTPClient: HTTPClient, @unchecked Sendable {
    let inner: StubHTTPClient
    let triggerOnCall: Int
    let onTrigger: @MainActor () -> Void
    private var count = 0

    init(inner: StubHTTPClient, triggerOnCall: Int = 1, onTrigger: @escaping @MainActor () -> Void) {
        self.inner = inner
        self.triggerOnCall = triggerOnCall
        self.onTrigger = onTrigger
    }

    func data(from url: URL, limit: Int) async throws -> Data {
        count += 1
        if count == triggerOnCall { await onTrigger() }
        return try await inner.data(from: url, limit: limit)
    }

    func resolvedURL(for url: URL) async throws -> URL {
        try await inner.resolvedURL(for: url)
    }
}

@MainActor
@Test func concurrentRefileDuringFetchIsNotReverted() async throws {
    let pageURL = URL(string: "https://example.com/pasta")!
    let html = try Data(contentsOf: Bundle.module.url(forResource: "generic-page", withExtension: "html", subdirectory: "Fixtures")!)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try BookmarkStore(directory: dir)
    let (bookmark, _) = store.add(url: pageURL)

    let stub = StubHTTPClient(responses: [pageURL: html])
    let client = InterceptingHTTPClient(inner: stub, triggerOnCall: 1) {
        store.refile(id: bookmark.id, to: "Articles")
    }
    let service = EnrichmentService(
        store: store,
        metadata: MetadataService(client: client),
        categorizer: KeywordCategorizer(),
        thumbnails: try ThumbnailCache(directory: dir.appendingPathComponent("thumbnails")),
        client: client
    )

    await service.enrich(id: bookmark.id)

    let after = store.library.bookmarks[0]
    #expect(after.folder == "Articles")
    #expect(after.manuallyFiled)
}

// generic-page.html has an og:image, so enrichment makes a second data(from:) call (the
// thumbnail download) after its post-fetch re-read. A refile landing during that second
// await must survive too.
@MainActor
@Test func concurrentRefileDuringThumbnailFetchIsNotReverted() async throws {
    let pageURL = URL(string: "https://example.com/pasta")!
    let html = try Data(contentsOf: Bundle.module.url(forResource: "generic-page", withExtension: "html", subdirectory: "Fixtures")!)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try BookmarkStore(directory: dir)
    let (bookmark, _) = store.add(url: pageURL)

    let stub = StubHTTPClient(responses: [pageURL: html])
    let client = InterceptingHTTPClient(inner: stub, triggerOnCall: 2) {
        store.refile(id: bookmark.id, to: "Articles")
    }
    let service = EnrichmentService(
        store: store,
        metadata: MetadataService(client: client),
        categorizer: KeywordCategorizer(),
        thumbnails: try ThumbnailCache(directory: dir.appendingPathComponent("thumbnails")),
        client: client
    )

    await service.enrich(id: bookmark.id)

    let after = store.library.bookmarks[0]
    #expect(after.folder == "Articles")
    #expect(after.manuallyFiled)
}

@Test func redirectCollisionCollapsesDuplicate() async throws {
    let short = URL(string: "https://vm.tiktok.com/SHORT/")!
    let full = URL(string: "https://www.tiktok.com/@a/video/123")!
    let oembed = try Data(contentsOf: Bundle.module.url(forResource: "tiktok-oembed", withExtension: "json", subdirectory: "Fixtures")!)
    var client = StubHTTPClient(responses: [TikTokFetcher.oembedURL(for: full): oembed])
    client.redirects = [short: full]
    let (store, service) = try await makeEnvironment(client: client)

    let (existing, _) = store.add(url: full)
    await service.enrich(id: existing.id)
    let (viaShort, isNew) = store.add(url: short)
    #expect(isNew) // the short link does not match before resolution
    await service.enrich(id: viaShort.id)

    #expect(store.library.bookmarks.count == 1)
    #expect(store.library.bookmarks[0].id == existing.id)
}
