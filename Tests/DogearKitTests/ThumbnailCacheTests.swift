import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DogearKit

private func makePNG() -> Data {
    let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
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
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let cache = try ThumbnailCache(directory: dir)
    let id = UUID()
    #expect(cache.store(makePNG(), for: id))
    #expect(cache.exists(for: id))
    cache.remove(for: id)
    #expect(!cache.exists(for: id))
}

@Test func rejectsNonImageData() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let cache = try ThumbnailCache(directory: dir)
    let id = UUID()
    #expect(!cache.store(Data("<html>error page</html>".utf8), for: id))
    #expect(!cache.exists(for: id))
}
