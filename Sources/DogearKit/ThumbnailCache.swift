import Foundation
import ImageIO
import UniformTypeIdentifiers

public final class ThumbnailCache: @unchecked Sendable {
    public let directory: URL
    // NSCache is thread-safe, so sharing it across the @unchecked Sendable
    // boundary is safe without extra locking.
    private let decoded: NSCache<NSUUID, CGImage> = {
        let cache = NSCache<NSUUID, CGImage>()
        cache.countLimit = decodedLimit
        return cache
    }()

    public static let maxPixelSize = 600
    /// A decoded 600 pixel thumbnail holds about 1 MB, so the cache stays near 100 MB.
    public static let decodedLimit = 100

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).img")
    }

    /// The decoded image if it is in memory. It never reads the file, so a view body can call it.
    public func cachedImage(for id: UUID) -> CGImage? {
        decoded.object(forKey: id as NSUUID)
    }

    /// Reads and decodes the file off the caller's actor, then caches the image.
    /// It returns nil without a read when the task is already cancelled.
    public nonisolated func loadImage(for id: UUID) async -> CGImage? {
        if let cached = cachedImage(for: id) { return cached }
        guard !Task.isCancelled,
              let source = CGImageSourceCreateWithURL(fileURL(for: id) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        decoded.setObject(image, forKey: id as NSUUID)
        return image
    }

    /// Decodes, downsamples to `maxPixelSize`, and stores as JPEG. Data that
    /// does not decode as an image stores nothing.
    @discardableResult
    public func store(_ data: Data, for id: UUID) -> Bool {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maxPixelSize,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return false
        }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            encoded, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return false }
        let wrote = (try? (encoded as Data).write(to: fileURL(for: id), options: .atomic)) != nil
        if wrote { decoded.removeObject(forKey: id as NSUUID) }
        return wrote
    }

    public func exists(for id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: id).path)
    }

    public func remove(for id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
        decoded.removeObject(forKey: id as NSUUID)
    }
}
