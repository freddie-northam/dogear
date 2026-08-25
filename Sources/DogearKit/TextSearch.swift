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

    /// Text prepared once so that many queries can be run against it.
    ///
    /// Search prepares the query and sweeps many bookmarks. Filing is the
    /// other way round: one bookmark's text tested against a few hundred
    /// keywords. Preparing the text once turns that from a per-keyword cost
    /// into a per-bookmark one.
    struct Haystack {
        fileprivate let lowered: String
        fileprivate let bytes: [UInt8]
        fileprivate let isASCII: Bool

        init(_ text: String) {
            lowered = text.lowercased()
            bytes = Array(lowered.utf8)
            isASCII = !bytes.contains { $0 >= 0x80 }
        }
    }

    /// True when prepared text contains the query, ignoring case. Both sides
    /// are lowercased already, so a byte compare is exact for ASCII; anything
    /// else falls back to String, for the reason `matches(_:_:)` gives.
    static func matches(_ haystack: Haystack, _ query: Query) -> Bool {
        guard !query.isEmpty else { return false }
        guard haystack.isASCII, query.isASCII else {
            return haystack.lowered.contains(query.lowered)
        }
        return haystack.bytes.withUnsafeBufferPointer { hay in
            query.bytes.withUnsafeBufferPointer { needle in
                Self.scan(hay, needle) != nil
            }
        }
    }

    /// True when the query appears in prepared text bounded by non-letters, so
    /// "ai" matches "ai agents" but not "email".
    static func containsWord(_ query: Query, in haystack: Haystack) -> Bool {
        guard !query.isEmpty else { return false }
        guard haystack.isASCII, query.isASCII else {
            return KeywordCategorizer.containsWord(query.lowered, in: haystack.lowered)
        }
        return haystack.bytes.withUnsafeBufferPointer { hay in
            query.bytes.withUnsafeBufferPointer { needle in
                var from = 0
                while let start = Self.scan(hay, needle, from: from) {
                    let beforeOK = start == 0 || !Self.isASCIILetter(hay[start - 1])
                    let end = start + needle.count
                    let afterOK = end == hay.count || !Self.isASCIILetter(hay[end])
                    if beforeOK, afterOK { return true }
                    from = start + 1
                }
                return false
            }
        }
    }

    /// Index of the first match at or after `from`, or nil. Both sides are
    /// already lowercase here, so this is a plain byte compare.
    private static func scan(_ haystack: UnsafeBufferPointer<UInt8>,
                             _ needle: UnsafeBufferPointer<UInt8>,
                             from: Int = 0) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        let limit = haystack.count - needle.count
        var start = from
        while start <= limit {
            var offset = 0
            while offset < needle.count, haystack[start + offset] == needle[offset] { offset += 1 }
            if offset == needle.count { return start }
            start += 1
        }
        return nil
    }

    private static func isASCIILetter(_ byte: UInt8) -> Bool {
        (byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z"))
            || (byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z"))
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
    /// `FetchedMetadata.fieldLimit` characters and a typed query is short, so
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
