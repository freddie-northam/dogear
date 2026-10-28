import Foundation
import Testing
@testable import DogearKit

/// Prints the median time of each hot path at three library sizes. It asserts nothing: the PERF tests hold the ceilings.
@Test func storeHotPaths() throws {
    guard ProcessInfo.processInfo.environment["BENCH"] != nil else { return }
    let clock = ContinuousClock()
    func median(_ runs: Int = 7, _ body: () throws -> Void) rethrows -> Duration {
        try (0..<runs).map { _ in try clock.measure(body) }.sorted()[runs / 2]
    }
    func ms(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 2)))
    }

    print("bookmarks | launch | star click | first search | keystroke | paste of 100")
    for count in [1_000, 5_000, 20_000] {
        let temp = TempDirectory()
        let store = try BookmarkStore(directory: temp.url)
        for i in 0..<count {
            _ = store.addForTesting(urlString: "https://example\(i % 300).com/post/\(i)",
                                    title: i % 4 == 0 ? "Crème brûlée \(i)" : "Garlic pasta \(i)",
                                    note: i % 5 == 0 ? "make for game night" : nil)
        }
        store.saveNow()
        let id = store.library.bookmarks[0].id

        let launch = try median(3) { _ = try BookmarkStore(directory: temp.url) }
        let star = median { store.toggleFavorite(id: id) }
        let firstSearch = median {
            store.toggleFavorite(id: id)
            _ = store.search("pasta")
        }
        let keystroke = median { _ = store.search("past") }
        var batch = 0
        let paste = median {
            batch += 1
            _ = store.add(urls: (0..<100).map { URL(string: "https://new.com/\(batch)/\($0)")! }, duplicates: .resave)
        }
        store.flush()
        print("\(count) | \([launch, star, firstSearch, keystroke, paste].map(ms).joined(separator: " | "))")
    }
}
