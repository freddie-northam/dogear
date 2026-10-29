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

@Test func storesValidImageAndReportsExists() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let cache = try ThumbnailCache(directory: dir)
    let id = UUID()
    #expect(cache.store(makePNG(), for: id))
    #expect(cache.exists(for: id))
    cache.remove(for: id)
    #expect(!cache.exists(for: id))
}

@Test func downsamplesLargeImagesTo600Pixels() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let cache = try ThumbnailCache(directory: dir)
    let id = UUID()
    #expect(cache.store(makePNG(width: 900, height: 300), for: id))
    let stored = try Data(contentsOf: cache.fileURL(for: id))
    let source = CGImageSourceCreateWithData(stored as CFData, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    #expect(max(image.width, image.height) <= 600)
}

@Test func rejectsNonImageData() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let cache = try ThumbnailCache(directory: dir)
    let id = UUID()
    #expect(!cache.store(Data("<html>error page</html>".utf8), for: id))
    #expect(!cache.exists(for: id))
}

@Test func loadReturnsNilAndCachesNothingWithoutAFile() async throws {
    let temp = TempDirectory()
    let cache = try ThumbnailCache(directory: temp.url)
    let id = UUID()
    #expect(await cache.loadImage(for: id) == nil)
    #expect(cache.cachedImage(for: id) == nil)
}

@Test func loadReturnsNilAndCachesNothingForACorruptFile() async throws {
    let temp = TempDirectory()
    let cache = try ThumbnailCache(directory: temp.url)
    let id = UUID()
    try Data("not a jpeg".utf8).write(to: cache.fileURL(for: id))
    #expect(await cache.loadImage(for: id) == nil)
    #expect(cache.cachedImage(for: id) == nil)
}

@Test func theMemoryReadNeverTouchesTheFileButALoadFillsIt() async throws {
    let temp = TempDirectory()
    let cache = try ThumbnailCache(directory: temp.url)
    let id = UUID()
    #expect(cache.store(makePNG(), for: id))
    #expect(cache.cachedImage(for: id) == nil)
    let loaded = try #require(await cache.loadImage(for: id))
    #expect(cache.cachedImage(for: id) === loaded)
    #expect(await cache.loadImage(for: id) === loaded)
}

@Test func aCancelledLoadReturnsNilAndCachesNothing() async throws {
    let temp = TempDirectory()
    let cache = try ThumbnailCache(directory: temp.url)
    let id = UUID()
    #expect(cache.store(makePNG(), for: id))
    let result = await Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return await cache.loadImage(for: id)
    }.value
    #expect(result == nil)
    #expect(cache.cachedImage(for: id) == nil)
}

@Test func removeDropsTheDecodedImage() async throws {
    let temp = TempDirectory()
    let cache = try ThumbnailCache(directory: temp.url)
    let id = UUID()
    #expect(cache.store(makePNG(), for: id))
    #expect(await cache.loadImage(for: id) != nil)
    cache.remove(for: id)
    #expect(cache.cachedImage(for: id) == nil)
    #expect(await cache.loadImage(for: id) == nil)
}

@Test func storeInvalidatesTheDecodedCache() async throws {
    let temp = TempDirectory()
    let cache = try ThumbnailCache(directory: temp.url)
    let id = UUID()
    #expect(cache.store(makePNG(width: 4, height: 4), for: id))
    let first = try #require(await cache.loadImage(for: id))
    #expect(first.width == 4)
    #expect(cache.store(makePNG(width: 40, height: 40), for: id))
    #expect(cache.cachedImage(for: id) == nil)
    let second = try #require(await cache.loadImage(for: id))
    #expect(second.width == 40)
}

@Test func theDecodedCacheEvictsPastItsLimit() async throws {
    let temp = TempDirectory()
    let cache = try ThumbnailCache(directory: temp.url)
    let ids = (0..<ThumbnailCache.decodedLimit + 20).map { _ in UUID() }
    for id in ids {
        #expect(cache.store(makePNG(), for: id))
        #expect(await cache.loadImage(for: id) != nil)
    }
    #expect(ids.filter { cache.cachedImage(for: $0) != nil }.count < ids.count)
}
