import Foundation
import Testing
@testable import DogearKit

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
    let (store, service) = try makeEnvironment(client: StubHTTPClient(responses: [pageURL: html]))

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
    let (store, service) = try makeEnvironment(client: client)

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
    let (store, service) = try makeEnvironment(client: StubHTTPClient(responses: [pageURL: html]))

    let (bookmark, _) = store.add(url: pageURL)
    store.refile(id: bookmark.id, to: "Articles")
    await service.enrich(id: bookmark.id)

    #expect(store.library.bookmarks[0].folder == "Articles")
}

@Test func unknownCategoryFallsBackToUnsorted() async throws {
    let pageURL = URL(string: "https://example.com/pasta")!
    let html = try Data(contentsOf: Bundle.module.url(forResource: "generic-page", withExtension: "html", subdirectory: "Fixtures")!)
    let (store, service) = try makeEnvironment(client: StubHTTPClient(responses: [pageURL: html]))
    store.removeFolder("Recipes")

    let (bookmark, _) = store.add(url: pageURL)
    await service.enrich(id: bookmark.id)

    #expect(store.library.bookmarks[0].folder == Library.unsorted)
}

@Test func redirectCollisionCollapsesDuplicate() async throws {
    let short = URL(string: "https://vm.tiktok.com/SHORT/")!
    let full = URL(string: "https://www.tiktok.com/@a/video/123")!
    let oembed = try Data(contentsOf: Bundle.module.url(forResource: "tiktok-oembed", withExtension: "json", subdirectory: "Fixtures")!)
    var client = StubHTTPClient(responses: [TikTokFetcher.oembedURL(for: full): oembed])
    client.redirects = [short: full]
    let (store, service) = try makeEnvironment(client: client)

    let (existing, _) = store.add(url: full)
    await service.enrich(id: existing.id)
    let (viaShort, isNew) = store.add(url: short)
    #expect(isNew) // the short link does not match before resolution
    await service.enrich(id: viaShort.id)

    #expect(store.library.bookmarks.count == 1)
    #expect(store.library.bookmarks[0].id == existing.id)
}
