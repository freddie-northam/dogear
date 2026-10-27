import Foundation

final class TempDirectory {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dogear-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}
