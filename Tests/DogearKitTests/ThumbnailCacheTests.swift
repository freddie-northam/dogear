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

@Test func imageForReturnsNilWithoutAFile() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let cache = try ThumbnailCache(directory: dir)
    #expect(cache.image(for: UUID()) == nil)
}

@Test func imageForReadsAndThenCaches() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let cache = try ThumbnailCache(directory: dir)
    let id = UUID()
    #expect(cache.store(makePNG(), for: id))
    #expect(cache.image(for: id) != nil)
    #expect(cache.image(for: id) != nil)
    cache.remove(for: id)
    #expect(cache.image(for: id) == nil)
}

@Test func storeInvalidatesTheDecodedCache() throws {
    let temp = TempDirectory()
    let dir = temp.url
    let cache = try ThumbnailCache(directory: dir)
    let id = UUID()
    #expect(cache.store(makePNG(width: 4, height: 4), for: id))
    let first = try #require(cache.image(for: id))
    #expect(first.size.width == 4)
    #expect(cache.store(makePNG(width: 40, height: 40), for: id))
    let second = try #require(cache.image(for: id))
    #expect(second.size.width == 40)
    #expect(second.size.width != first.size.width)
}
