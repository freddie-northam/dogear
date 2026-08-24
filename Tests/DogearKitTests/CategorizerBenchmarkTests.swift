import Foundation
import Testing
@testable import DogearKit

// Benchmarks the filing paths a user waits on: enrichment files one bookmark,
// File These for Me files a whole Unsorted folder, and Suggest Folders scores
// every waiting bookmark against every folder worth proposing.
// `BENCH=1 swift test -c release -Xswiftc -enable-testing --filter filingHotPaths`

private struct BenchGenerator: RandomNumberGenerator {
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

/// Titles shaped like the ones a real library holds: mostly X posts with an
/// author prefix, some page titles, a few bare hosts.
private func benchBookmarks(count: Int) -> [Bookmark] {
    var rng = BenchGenerator(seed: 0xF11E_D000)
    let words = ["shipping", "the", "new", "agent", "design", "system", "with", "claude",
                 "and", "a", "little", "typescript", "why", "nobody", "talks", "about",
                 "shaders", "today", "just", "crossed", "presets", "including", "this",
                 "repo", "for", "building", "faster", "apps", "on", "macos", "recipe"]
    var out: [Bookmark] = []
    for i in 0..<count {
        let body = (0..<12).map { _ in words.randomElement(using: &rng)! }.joined(separator: " ")
        let isX = i % 4 != 0
        out.append(Bookmark(
            id: UUID(),
            url: isX ? "https://x.com/user\(i % 50)/status/\(i)" : "https://site\(i % 60).example.com/p/\(i)",
            title: isX ? "Person \(i % 50) (@handle\(i % 50)): \(body)" : body,
            author: isX ? "@handle\(i % 50)" : nil,
            note: nil, folder: Library.unsorted, source: isX ? .x : .web,
            createdAt: Date(timeIntervalSince1970: Double(i)), doneAt: nil,
            hasThumbnail: false, manuallyFiled: false))
    }
    return out
}

private func benchReport(_ label: String, iterations: Int, _ body: () async -> Void) async {
    await body()
    let start = ContinuousClock.now
    for _ in 0..<iterations { await body() }
    let total = ContinuousClock.now - start
    let each = (Double(total.components.seconds) * 1000
        + Double(total.components.attoseconds) / 1e15) / Double(iterations)
    print("BENCH " + label.padding(toLength: 34, withPad: " ", startingAt: 0)
        + String(format: "%9.3f ms", each))
}

@Test func filingHotPaths() async throws {
    guard ProcessInfo.processInfo.environment["BENCH"] != nil else { return }
    let folders = ["Recipes", "Restaurants", "Shows", "Music", "Articles", Library.unsorted]
    let categorizer = KeywordCategorizer()

    for count in [200, 1000, 5000] {
        let bookmarks = benchBookmarks(count: count)
        print("BENCH ===== n=\(count) waiting =====")

        let one = bookmarks[count / 2]
        let oneURL = URL(string: one.url)!
        let oneMeta = FetchedMetadata(title: one.title, author: one.author,
                                      description: one.note, source: one.source)
        await benchReport("categorize one bookmark", iterations: 200) {
            _ = await categorizer.categorize(oneMeta, url: oneURL, folders: folders)
        }

        await benchReport("File These for Me (whole folder)", iterations: 3) {
            for b in bookmarks {
                guard let url = URL(string: b.url) else { continue }
                let md = FetchedMetadata(title: b.title, author: b.author,
                                         description: b.note, source: b.source)
                _ = await categorizer.categorize(md, url: url, folders: folders)
            }
        }

        await benchReport("Suggest Folders (scoring pass)", iterations: 1) {
            _ = await FolderSuggestions.suggest(for: bookmarks, folders: folders)
        }
    }
}
