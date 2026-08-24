import Foundation

/// Case-insensitive substring matching for the library search field.
///
/// `title.lowercased().contains(query)` reads well and costs about 36 ms for
/// one keystroke over 20,000 bookmarks: `String.contains` compares grapheme
/// clusters, and every field allocates a lowercased copy first. The search
/// field recomputes on every keystroke, so that is two dropped frames per
/// character typed.
///
/// This scans UTF-8 bytes when both sides are plain ASCII, which is almost
/// every search, and hands anything else to String, which is the only thing
/// that knows two spellings of an accented word are the same text.
enum TextSearch {
    /// A query, prepared once for a whole sweep instead of once per field.
    struct Query {
        fileprivate let lowered: String
        fileprivate let bytes: [UInt8]
        /// True when the lowercased query is pure ASCII. A query with any
        /// other character cannot be matched byte by byte.
        fileprivate let isASCII: Bool

        init(_ text: String) {
            lowered = text.lowercased()
            bytes = Array(lowered.utf8)
            isASCII = lowered.utf8.allSatisfy { $0 < 0x80 }
        }

        var isEmpty: Bool { bytes.isEmpty }
    }

    /// True when `haystack` contains the query, ignoring case.
    ///
    /// The byte scan runs only when the query and the text are both ASCII,
    /// where folding A-Z gives exactly the answer Unicode lowercasing gives.
    /// Everything else goes to String. Bytes cannot tell that "cafe" plus a
    /// combining accent is the same word as "café", and cannot tell that the
    /// Kelvin sign lowercases to a plain "k", so a byte scan over text like
    /// that would answer differently depending on how the page spelled it.
    static func matches(_ haystack: String, _ query: Query) -> Bool {
        guard !query.isEmpty else { return false }
        if query.isASCII, let found = scanASCII(haystack, query.bytes) {
            return found
        }
        return haystack.lowercased().contains(query.lowered)
    }

    static func matches(_ haystack: String?, _ query: Query) -> Bool {
        guard let haystack else { return false }
        return matches(haystack, query)
    }

    /// Scans `haystack` for `needle`, folding A-Z. Returns nil when the text
    /// is not pure ASCII, which means the caller must use the String path.
    ///
    /// ponytail: a plain O(haystack * needle) scan. Titles are capped at
    /// `OpenGraphParser.titleLimit` characters and a typed query is short, so
    /// the quadratic worst case is bounded small. Boyer-Moore if either of
    /// those stops being true.
    private static func scanASCII(_ haystack: String, _ needle: [UInt8]) -> Bool? {
        var haystack = haystack
        return haystack.withUTF8 { buffer -> Bool? in
            // One pass to reject non-ASCII text. Cheaper than the match below,
            // and it keeps the byte path honest.
            for byte in buffer where byte >= 0x80 { return nil }
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
