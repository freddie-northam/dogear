import Foundation
import ImageIO

public struct ThumbnailCache: Sendable {
    let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).img")
    }

    @discardableResult
    public func store(_ data: Data, for id: UUID) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            return false
        }
        return (try? data.write(to: fileURL(for: id), options: .atomic)) != nil
    }

    public func exists(for id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: id).path)
    }

    public func remove(for id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }
}
