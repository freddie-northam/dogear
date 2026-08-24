import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A `final class` (not a struct) because it wraps an `NSCache`: the app
/// creates exactly one instance in `AppModel` and shares it by reference.
public final class ThumbnailCache: @unchecked Sendable {
    let directory: URL
    // NSCache is thread-safe, so sharing it across the @unchecked Sendable
    // boundary is safe without extra locking.
    private let decoded = NSCache<NSUUID, NSImage>()

    /// Cards render at ~220 points, so 600 pixels covers Retina with room to
    /// spare; full-size og:images measured 200 MB across a real library.
    static let maxPixelSize = 600

    public init(directory: URL) throws {
        self.directory = directory
        decoded.countLimit = 48
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).img")
    }

    /// Decoded image for display, read from the file once and cached
    /// thereafter so repeated view body evaluations don't re-decode JPEGs.
    public func image(for id: UUID) -> NSImage? {
        if let cached = decoded.object(forKey: id as NSUUID) { return cached }
        guard let image = NSImage(contentsOf: fileURL(for: id)) else { return nil }
        decoded.setObject(image, forKey: id as NSUUID)
        return image
    }

    /// Loads a cold thumbnail without making SwiftUI's main actor decode it.
    @MainActor
    public func loadImage(for id: UUID) async -> NSImage? {
        if let cached = decoded.object(forKey: id as NSUUID) { return cached }
        let url = fileURL(for: id)
        let loading = Task.detached(priority: .utility) { () -> CGImage? in
            guard !Task.isCancelled else { return nil }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            guard !Task.isCancelled else { return nil }
            return CGImageSourceCreateImageAtIndex(
                source, 0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
        let cgImage = await withTaskCancellationHandler {
            await loading.value
        } onCancel: {
            loading.cancel()
        }
        guard !Task.isCancelled, let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
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
