import Foundation

/// Case-insensitive substring matching for the library search field.
///
/// `title.lowercased().contains(query)` reads well and costs about 36 ms for
/// one keystroke over 20,000 bookmarks: `String.contains` compares grapheme
/// clusters, and every field allocates a lowercased copy first. The search
/// field recomputes on every keystroke, so that is two dropped frames per
/// character typed.
///
/// This scans UTF-8 bytes instead, and it prepares the query once for the
/// whole sweep rather than once per field.
enum TextSearch {
    /// A query, prepared for repeated matching.
    struct Query {
        fileprivate let lowered: String
        fileprivate let bytes: [UInt8]
        /// True when the query is pure ASCII, so a byte-level A-Z fold gives
        /// the same answer Unicode lowercasing would. A query that carries any
        /// other character takes the slower, fully correct path below.
        fileprivate let isASCII: Bool

        init(_ text: String) {
            lowered = text.lowercased()
            bytes = Array(lowered.utf8)
            isASCII = lowered.utf8.allSatisfy { $0 < 0x80 }
        }

        var isEmpty: Bool { bytes.isEmpty }
    }

    /// True when `haystack` contains the query, ignoring case.
    static func matches(_ haystack: String, _ query: Query) -> Bool {
        guard !query.isEmpty else { return false }
        if query.isASCII {
            return scan(haystack, query.bytes)
        }
        // A query that carries an accent needs more than case folding. Two
        // spellings of the same word, "café" and "cafe" plus a combining
        // accent, are equal text and different bytes, and only String knows
        // that. Rare enough to pay full price for.
        return haystack.lowercased().contains(query.lowered)
    }

    static func matches(_ haystack: String?, _ query: Query) -> Bool {
        guard let haystack else { return false }
        return matches(haystack, query)
    }

    // ponytail: a plain O(haystack * needle) scan. Bookmark titles and URLs
    // are short and search queries have almost no repeated prefix, so the
    // worst case never arrives. Boyer-Moore if that ever stops being true.
    private static func scan(_ haystack: String, _ needle: [UInt8]) -> Bool {
        var haystack = haystack
        return haystack.withUTF8 { buffer in
            guard buffer.count >= needle.count else { return false }
            let limit = buffer.count - needle.count
            var start = 0
            while start <= limit {
                var offset = 0
                while offset < needle.count {
                    var byte = buffer[start + offset]
                    if byte >= UInt8(ascii: "A"), byte <= UInt8(ascii: "Z") { byte += 32 }
                    if byte != needle[offset] { break }
                    offset += 1
                }
                if offset == needle.count { return true }
                start += 1
            }
            return false
        }
    }
}
