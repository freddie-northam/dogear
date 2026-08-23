import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ThumbnailCache: Sendable {
    let directory: URL

    /// Cards render at ~220 points, so 600 pixels covers Retina with room to
    /// spare; full-size og:images measured 200 MB across a real library.
    static let maxPixelSize = 600

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).img")
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
        return (try? (encoded as Data).write(to: fileURL(for: id), options: .atomic)) != nil
    }

    public func exists(for id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: id).path)
    }

    public func remove(for id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }
}
