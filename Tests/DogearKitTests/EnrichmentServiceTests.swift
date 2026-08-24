import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DogearKit

private func makePNG(width: Int = 4, height: Int = 4) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let image = context.makeImage()!
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

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

    let (bookmark, _) = store.add(url: pageURL)!
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

    let (bookmark, _) = store.add(url: URL(string: "https://example.com/gone")!)!
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

    let (bookmark, _) = store.add(url: pageURL)!
    store.refile(id: bookmark.id, to: "Articles")
    await service.enrich(id: bookmark.id)

    #expect(store.library.bookmarks[0].folder == "Articles")
}

@Test func unknownCategoryFallsBackToUnsorted() async throws {
    let pageURL = URL(string: "https://example.com/pasta")!
    let html = try Data(contentsOf: Bundle.module.url(forResource: "generic-page", withExtension: "html", subdirectory: "Fixtures")!)
    let (store, service) = try await makeEnvironment(client: StubHTTPClient(responses: [pageURL: html]))
    store.removeFolder("Recipes")

    let (bookmark, _) = store.add(url: pageURL)!
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
    let onTrigger: @MainActor () async -> Void
    private var count = 0

    init(inner: StubHTTPClient, triggerOnCall: Int = 1, onTrigger: @escaping @MainActor () async -> Void) {
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
    let (bookmark, _) = store.add(url: pageURL)!

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
    let (bookmark, _) = store.add(url: pageURL)!

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

// The categorizer guesses "Recipes" for generic-page.html. If that folder is deleted
// during the thumbnail fetch (the second data(from:) call, after the guess was made but
// before it lands), the bookmark must fall back to Unsorted, not resurrect a dead folder.
@MainActor
@Test func folderDeletedDuringThumbnailFetchFallsBackToUnsorted() async throws {
    let pageURL = URL(string: "https://example.com/pasta")!
    let html = try Data(contentsOf: Bundle.module.url(forResource: "generic-page", withExtension: "html", subdirectory: "Fixtures")!)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try BookmarkStore(directory: dir)
    let (bookmark, _) = store.add(url: pageURL)!

    let stub = StubHTTPClient(responses: [pageURL: html])
    let client = InterceptingHTTPClient(inner: stub, triggerOnCall: 2) {
        store.removeFolder("Recipes")
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
    #expect(after.folder == Library.unsorted)
    #expect(!after.manuallyFiled)
}

// Two short links that both resolve to the same target, enriched concurrently: A's
// collision check must not run before B has had a chance to land its own resolved URL,
// or both survive as duplicates. Trigger during A's thumbnail fetch (its second
// data(from:) call, since generic-page.html has an og:image) so B's full enrich(id:)
// completes while A is still mid-flight, before A reaches its own write.
@MainActor
@Test func concurrentRedirectCollisionKeepsOnlyOneSurvivor() async throws {
    let shortA = URL(string: "https://short.example/a")!
    let shortB = URL(string: "https://short.example/b")!
    let target = URL(string: "https://target.example/page")!
    let html = try Data(contentsOf: Bundle.module.url(forResource: "generic-page", withExtension: "html", subdirectory: "Fixtures")!)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try BookmarkStore(directory: dir)
    let (bookmarkA, _) = store.add(url: shortA)!
    let (bookmarkB, _) = store.add(url: shortB)!

    var stub = StubHTTPClient(responses: [target: html])
    stub.redirects = [shortA: target, shortB: target]

    var service: EnrichmentService!
    let client = InterceptingHTTPClient(inner: stub, triggerOnCall: 2) {
        await service.enrich(id: bookmarkB.id)
    }
    service = EnrichmentService(
        store: store,
        metadata: MetadataService(client: client),
        categorizer: KeywordCategorizer(),
        thumbnails: try ThumbnailCache(directory: dir.appendingPathComponent("thumbnails")),
        client: client
    )

    await service.enrich(id: bookmarkA.id)

    #expect(store.library.bookmarks.filter { $0.url == "https://target.example/page" }.count == 1)
}

@Test func redirectCollisionMergesIntoTheSurvivor() async throws {
    let short = URL(string: "https://vm.tiktok.com/SHORT/")!
    let full = URL(string: "https://www.tiktok.com/@a/video/123")!
    let oembed = try Data(contentsOf: Bundle.module.url(forResource: "tiktok-oembed", withExtension: "json", subdirectory: "Fixtures")!)
    var client = StubHTTPClient(responses: [TikTokFetcher.oembedURL(for: full): oembed])
    client.redirects = [short: full]
    let (store, service) = try await makeEnvironment(client: client)

    // S: the survivor, no note, not favourited.
    let (survivor, _) = store.add(url: full)!

    // D: the duplicate, with a note, a star, and a manual folder to preserve.
    let (duplicate, _) = store.add(url: short)!
    var d = store.library.bookmarks.first { $0.id == duplicate.id }!
    d.note = "keep me"
    store.update(d)
    store.toggleFavorite(id: duplicate.id)
    store.refile(id: duplicate.id, to: "Recipes")

    await service.enrich(id: duplicate.id)

    let matches = store.library.bookmarks.filter { $0.url == URLCleaner.canonicalString(full) }
    #expect(matches.count == 1)
    let merged = matches[0]
    #expect(merged.id == survivor.id)
    #expect(merged.note == "keep me")
    #expect(merged.favoritedAt != nil)
    #expect(merged.folder == "Recipes")
    #expect(merged.manuallyFiled)
    #expect(merged.createdAt == min(survivor.createdAt, duplicate.createdAt))
    #expect(merged.doneAt == nil)
}

@Test func redirectCollisionKeepsSurvivorFieldsWhenPresent() async throws {
    let short = URL(string: "https://vm.tiktok.com/SHORT/")!
    let full = URL(string: "https://www.tiktok.com/@a/video/123")!
    let oembed = try Data(contentsOf: Bundle.module.url(forResource: "tiktok-oembed", withExtension: "json", subdirectory: "Fixtures")!)
    var client = StubHTTPClient(responses: [TikTokFetcher.oembedURL(for: full): oembed])
    client.redirects = [short: full]
    let (store, service) = try await makeEnvironment(client: client)

    let (survivor, _) = store.add(url: full)!
    var s = store.library.bookmarks.first { $0.id == survivor.id }!
    s.note = "survivor's note"
    store.update(s)
    store.toggleFavorite(id: survivor.id)
    let survivorFavoritedAt = store.library.bookmarks.first { $0.id == survivor.id }!.favoritedAt

    let (duplicate, _) = store.add(url: short)!
    var d = store.library.bookmarks.first { $0.id == duplicate.id }!
    d.note = "duplicate's note"
    store.update(d)
    store.toggleFavorite(id: duplicate.id)

    await service.enrich(id: duplicate.id)

    let merged = store.library.bookmarks.first { $0.id == survivor.id }!
    #expect(merged.note == "survivor's note")
    #expect(merged.favoritedAt == survivorFavoritedAt)
}

@Test func redirectCollisionBumpsTheSurvivorToTheTop() async throws {
    let short = URL(string: "https://vm.tiktok.com/SHORT/")!
    let full = URL(string: "https://www.tiktok.com/@a/video/123")!
    let oembed = try Data(contentsOf: Bundle.module.url(forResource: "tiktok-oembed", withExtension: "json", subdirectory: "Fixtures")!)
    var client = StubHTTPClient(responses: [TikTokFetcher.oembedURL(for: full): oembed])
    client.redirects = [short: full]
    let (store, service) = try await makeEnvironment(client: client)

    let (survivor, _) = store.add(url: full)!
    let (other, _) = store.add(url: URL(string: "https://example.com/other")!)!
    #expect(store.library.bookmarks.map(\.id) == [other.id, survivor.id])

    let (duplicate, _) = store.add(url: short)!
    #expect(store.library.bookmarks[0].id == duplicate.id)

    await service.enrich(id: duplicate.id)

    #expect(store.library.bookmarks[0].id == survivor.id)
}

@Test func redirectCollisionRemovesTheDuplicateThumbnail() async throws {
    let short = URL(string: "https://vm.tiktok.com/SHORT/")!
    let full = URL(string: "https://www.tiktok.com/@a/video/123")!
    let oembed = try Data(contentsOf: Bundle.module.url(forResource: "tiktok-oembed", withExtension: "json", subdirectory: "Fixtures")!)
    var client = StubHTTPClient(responses: [TikTokFetcher.oembedURL(for: full): oembed])
    client.redirects = [short: full]
    let (store, service) = try await makeEnvironment(client: client)

    _ = store.add(url: full)!
    let (duplicate, _) = store.add(url: short)!
    #expect(await service.thumbnails.store(makePNG(), for: duplicate.id))

    await service.enrich(id: duplicate.id)

    #expect(await !service.thumbnails.exists(for: duplicate.id))
}
