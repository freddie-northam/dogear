import Foundation

/// Ranks command titles against what the user typed in the command menu.
public enum CommandMatch {
    /// Returns the indices of matching titles, best first. A blank query returns every index.
    public static func rank(_ titles: [String], query: String) -> [Int] {
        let needle = fold(query).trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return Array(titles.indices) }
        let scored: [(index: Int, score: Int)] = titles.enumerated().compactMap { index, title in
            score(fold(title), needle).map { (index, $0) }
        }
        // Sorting on the index too keeps ties in their original order.
        return scored.sorted { ($0.score, $0.index) < ($1.score, $1.index) }.map(\.index)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func score(_ title: String, _ needle: String) -> Int? {
        if title.hasPrefix(needle) { return 0 }
        let words = title.split(separator: " ")
        if words.contains(where: { $0.hasPrefix(needle) }) { return 1 }
        if String(words.compactMap(\.first)).hasPrefix(needle) { return 2 }
        return title.contains(needle) ? 3 : nil
    }
}
