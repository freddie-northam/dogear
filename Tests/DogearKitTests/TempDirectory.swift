import Foundation

/// A per-test scratch directory that removes itself. Hold it for the test's
/// lifetime; the directory is gone when the value is deinitialized.
final class TempDirectory {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dogear-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}
