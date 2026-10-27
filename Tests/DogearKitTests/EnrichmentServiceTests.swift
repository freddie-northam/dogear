import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Synchronization
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

/// Lets a client callback reach a service that is built after the client.
@MainActor private final class ServiceSlot {
    var service: EnrichmentService?
}

private final class InterceptingHTTPClient: HTTPClient {
    let inner: StubHTTPClient
    let triggerOnCall: Int
    let onTrigger: @MainActor @Sendable () async -> Void
    private let count = Mutex(0)

    init(inner: StubHTTPClient, triggerOnCall: Int = 1, onTrigger: @escaping @MainActor @Sendable () async -> Void) {
        self.inner = inner
        self.triggerOnCall = triggerOnCall
        self.onTrigger = onTrigger
    }

    private func bumpAndMaybeTrigger() async {
        if count.withLock({ $0 += 1; return $0 }) == triggerOnCall { await onTrigger() }
    }

    func data(from url: URL, limit: Int) async throws -> Data {
        await bumpAndMaybeTrigger()
        return try await inner.data(from: url, limit: limit)
    }

    func fetch(_ url: URL, limit: Int) async throws -> (data: Data, finalURL: URL) {
        await bumpAndMaybeTrigger()
        return try await inner.fetch(url, limit: limit)
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

    let slot = ServiceSlot()
    let client = InterceptingHTTPClient(inner: stub, triggerOnCall: 2) {
        await slot.service?.enrich(id: bookmarkB.id)
    }
    let service = EnrichmentService(
        store: store,
        metadata: MetadataService(client: client),
        categorizer: KeywordCategorizer(),
        thumbnails: try ThumbnailCache(directory: dir.appendingPathComponent("thumbnails")),
        client: client
    )
    slot.service = service

    await service.enrich(id: bookmarkA.id)

    #expect(store.library.bookmarks.filter { $0.url == "https://target.example/page" }.count == 1)
}

@Test func redirectCollisionMergesIntoTheSurvivor() async throws {
    let short = URL(string: "https://vm.tiktok.com/SHORT/")!
    let full = URL(string: "https://www.tiktok.com/@a/video/123")!
    let page = try Data(contentsOf: Bundle.module.url(forResource: "tiktok-video", withExtension: "html", subdirectory: "Fixtures")!)
    var client = StubHTTPClient(responses: [full: page])
    client.redirects = [short: full]
    let (store, service) = try await makeEnvironment(client: client)

    let (survivor, _) = store.add(url: full)!

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
    let page = try Data(contentsOf: Bundle.module.url(forResource: "tiktok-video", withExtension: "html", subdirectory: "Fixtures")!)
    var client = StubHTTPClient(responses: [full: page])
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
    let page = try Data(contentsOf: Bundle.module.url(forResource: "tiktok-video", withExtension: "html", subdirectory: "Fixtures")!)
    var client = StubHTTPClient(responses: [full: page])
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
    let page = try Data(contentsOf: Bundle.module.url(forResource: "tiktok-video", withExtension: "html", subdirectory: "Fixtures")!)
    var client = StubHTTPClient(responses: [full: page])
    client.redirects = [short: full]
    let (store, service) = try await makeEnvironment(client: client)

    _ = store.add(url: full)!
    let (duplicate, _) = store.add(url: short)!
    #expect(await service.thumbnails.store(makePNG(), for: duplicate.id))

    await service.enrich(id: duplicate.id)

    #expect(await !service.thumbnails.exists(for: duplicate.id))
}

@Test func redirectCollisionKeepsEveryStoredFieldOnTheSurvivor() async throws {
    let short = URL(string: "https://vm.tiktok.com/SHORT/")!
    let full = URL(string: "https://www.tiktok.com/@a/video/123")!
    let page = try Data(contentsOf: Bundle.module.url(forResource: "tiktok-video", withExtension: "html", subdirectory: "Fixtures")!)
    var client = StubHTTPClient(responses: [full: page])
    client.redirects = [short: full]
    let (store, service) = try await makeEnvironment(client: client)

    let (survivor, _) = store.add(url: full)!
    store.markShown(id: survivor.id)
    let shownAt = store.library.bookmarks.first { $0.id == survivor.id }?.lastShownAt

    let (duplicate, _) = store.add(url: short)!
    await service.enrich(id: duplicate.id)

    let merged = try #require(store.library.bookmarks.first { $0.id == survivor.id })
    #expect(store.library.bookmarks.count == 1)
    #expect(merged.lastShownAt == shownAt)
}

@Test func enrichLeavesAPlaceAlone() async throws {
    let (store, service) = try await makeEnvironment(client: StubHTTPClient(responses: [:]))
    let place = Place(name: "Kagari", address: "Ginza, Tokyo", latitude: 35.6, longitude: 139.7)
    let saved = try #require(store.add(places: [place], to: "Restaurants").first)

    await service.enrich(id: saved.id)

    let after = try #require(store.library.bookmarks.first { $0.id == saved.id })
    #expect(after.title == "Kagari")
    #expect(after.folder == "Restaurants")
    #expect(after.place == place)
}

@Test func redirectCollisionMergesEvenWhenTheFetchFindsNoMetadata() async throws {
    let short = URL(string: "https://short.example/a")!
    let target = URL(string: "https://target.example/page")!
    var client = StubHTTPClient(responses: [target: Data("<html></html>".utf8)])
    client.redirects = [short: target]
    let (store, service) = try await makeEnvironment(client: client)

    let (survivor, _) = store.add(url: target)!
    let (duplicate, _) = store.add(url: short)!
    var d = try #require(store.library.bookmarks.first { $0.id == duplicate.id })
    d.note = "keep me"
    store.update(d)

    await service.enrich(id: duplicate.id)

    let matches = store.library.bookmarks.filter { $0.url == URLCleaner.canonicalString(target) }
    #expect(matches.map(\.id) == [survivor.id])
    #expect(matches.first?.note == "keep me")
}
