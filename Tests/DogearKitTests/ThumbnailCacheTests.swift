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

@Test @MainActor func coldListThumbnailLoadingYieldsTheMainActor() async throws {
    let temp = TempDirectory()
    let writer = try ThumbnailCache(directory: temp.url)
    let ids = (0..<12).map { _ in UUID() }
    for id in ids {
        #expect(writer.store(makePNG(width: 600, height: 600), for: id))
    }
    let cold = try ThumbnailCache(directory: temp.url)

    let signal = AsyncStream.makeStream(of: Void.self)
    let start = ContinuousClock.now
    let loading = Task { @MainActor in
        signal.continuation.yield()
        var count = 0
        for id in ids {
            if await cold.loadImage(for: id) != nil { count += 1 }
        }
        return count
    }
    for await _ in signal.stream.prefix(1) { break }
    let elapsed = ContinuousClock.now - start

    if ProcessInfo.processInfo.environment["PERF"] != nil {
        // Two frames allow CI scheduling noise while staying below the 48 ms synchronous baseline.
        #expect(elapsed < .milliseconds(32))
    }
    #expect(await loading.value == ids.count)
}

@Test @MainActor func cancelledColdLoadReturnsNil() async throws {
    let temp = TempDirectory()
    let writer = try ThumbnailCache(directory: temp.url)
    let id = UUID()
    #expect(writer.store(makePNG(width: 600, height: 600), for: id))
    let cold = try ThumbnailCache(directory: temp.url)

    let loading = Task { @MainActor in
        withUnsafeCurrentTask { $0?.cancel() }
        return await cold.loadImage(for: id) != nil
    }

    #expect(await loading.value == false)
}
