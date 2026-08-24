import Foundation
import Testing
@testable import DogearKit

// A store-level benchmark over a generated library, for the hot paths a user
// feels: a keystroke in the search field, a click on a star, a paste of many
// links. Prints a table; asserts nothing. Run it with `BENCH=1 swift test
// --filter storeHotPaths`, and read the numbers next to the frame budget: a
// 60 Hz frame is 16.7 ms, and SwiftUI needs most of that for itself.
//
// The dataset is generated from a fixed seed, so two runs measure the same
// library and a before/after comparison is real.

/// SplitMix64. Small, fast, and seeded, which is the point: `SystemRandom`
/// would change the dataset between runs and hide small wins in the noise.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let benchWords = [
    "recipe", "pasta", "carbonara", "review", "essay", "swift", "concurrency",
    "menu", "london", "podcast", "album", "guide", "notes", "deep",
    "dive", "kubernetes", "garden", "tomato", "film", "criterion", "interview",
]

private func benchLibrary(count: Int, accentedShare: Int = 0) -> Library {
    var rng = SeededGenerator(seed: 0xD09E_A401)
    var bookmarks: [Bookmark] = []
    bookmarks.reserveCapacity(count)
    for i in 0..<count {
        var title = (0..<6).map { _ in benchWords.randomElement(using: &rng)! }.joined(separator: " ")
        // Search has two paths: a byte scan for plain ASCII text, and String
        // for anything else. `accentedShare` sets how much of the library
        // takes the slower path, so the table shows both ends of the range a
        // real library sits between.
        if accentedShare > 0, i % accentedShare == 0 {
            title = title.replacingOccurrences(of: "e", with: "\u{e9}")
        }
        bookmarks.append(Bookmark(
            id: UUID(),
            url: "https://site\(i % 400).example.com/\(benchWords.randomElement(using: &rng)!)/\(i)",
            title: title,
            author: i % 3 == 0 ? "author\(i % 97)" : nil,
            note: i % 7 == 0 ? "note \(title)" : nil,
            folder: Library.defaultFolders[i % Library.defaultFolders.count],
            source: .web,
            createdAt: Date(timeIntervalSince1970: Double(i)),
            doneAt: i % 11 == 0 ? Date() : nil,
            hasThumbnail: false,
            manuallyFiled: false,
            favoritedAt: i % 13 == 0 ? Date() : nil
        ))
    }
    return Library(folders: Library.defaultFolders, bookmarks: bookmarks,
                   schemaVersion: Library.currentSchemaVersion)
}

private func benchReport(_ label: String, iterations: Int, _ body: () -> Void) {
    body() // Warm the caches, so the first run does not skew the mean.
    let start = ContinuousClock.now
    for _ in 0..<iterations { body() }
    let total = ContinuousClock.now - start
    let each = (Double(total.components.seconds) * 1000
        + Double(total.components.attoseconds) / 1e15) / Double(iterations)
    print("BENCH " + label.padding(toLength: 32, withPad: " ", startingAt: 0)
        + String(format: "%9.3f ms", each))
}

@Test func storeHotPaths() throws {
    guard ProcessInfo.processInfo.environment["BENCH"] != nil else { return }
    for count in [1000, 5000, 20000] {
        let temp = TempDirectory()
        let dir = temp.url
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(benchLibrary(count: count))
        try data.write(to: dir.appendingPathComponent("library.json"))
        print("BENCH ===== n=\(count)  library.json=\(data.count / 1024) KB =====")

        let store = try BookmarkStore(directory: dir)
        let id = store.library.bookmarks[count / 2].id
        let urls = (0..<100).map { URL(string: "https://new\($0).example.com/x")! }

        benchReport("load", iterations: 5) { _ = try? BookmarkStore(directory: dir) }
        benchReport("saveNow", iterations: 10) { store.saveNow() }
        benchReport("toggleFavorite (1 click)", iterations: 10) { store.toggleFavorite(id: id) }
        benchReport("search hit", iterations: 20) { _ = store.search("carbonara") }
        benchReport("search miss", iterations: 20) { _ = store.search("zzzz") }

        // The same searches over a library where one title in three carries an
        // accent, so a third of the sweep takes the String path.
        let mixedDir = TempDirectory()
        let mixed = try JSONEncoder().encode(benchLibrary(count: count, accentedShare: 3))
        try mixed.write(to: mixedDir.url.appendingPathComponent("library.json"))
        let mixedStore = try BookmarkStore(directory: mixedDir.url)
        benchReport("search hit (1/3 accented)", iterations: 20) { _ = mixedStore.search("carbonara") }
        benchReport("search miss (1/3 accented)", iterations: 20) { _ = mixedStore.search("zzzz") }
        benchReport("counts()", iterations: 20) { _ = store.counts() }
        benchReport("bookmarks(in:)", iterations: 20) { _ = store.bookmarks(in: "Recipes") }
        benchReport("archive()", iterations: 10) { _ = store.archive() }
        benchReport("pick()", iterations: 10) { _ = store.pick() }
        benchReport("add(urls:) x100", iterations: 1) { _ = store.add(urls: urls) }
    }
}
