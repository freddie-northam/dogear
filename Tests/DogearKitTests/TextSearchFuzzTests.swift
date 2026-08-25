import Foundation
import Testing
@testable import DogearKit

// The byte scanner replaced `lowercased().contains(...)`. These tests hold it
// to that reference: for text the scanner claims, its answer must be the same
// answer String would have given. A difference here is a filing or a search
// result that silently changed.

private struct FuzzGenerator: RandomNumberGenerator {
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

/// A small alphabet on purpose: short strings drawn from few letters collide
/// constantly, which is what produces repeated prefixes, overlapping matches
/// and off-by-one boundaries. Random long text would almost never match.
private let fuzzAlphabet = Array("aAbB c1-")

private func fuzzString(_ rng: inout FuzzGenerator, maxLength: Int) -> String {
    let length = Int(rng.next() % UInt64(maxLength + 1))
    return String((0..<length).map { _ in fuzzAlphabet[Int(rng.next() % UInt64(fuzzAlphabet.count))] })
}

@Test func byteScanAgreesWithStringOnEveryASCIICase() {
    var rng = FuzzGenerator(seed: 0xBADC_0FFE)
    var checked = 0
    for _ in 0..<20000 {
        let text = fuzzString(&rng, maxLength: 24)
        let needle = fuzzString(&rng, maxLength: 6)
        let query = TextSearch.Query(needle)
        guard !query.isEmpty else { continue }
        let expected = text.lowercased().contains(needle.lowercased())
        #expect(TextSearch.matches(text, query) == expected,
                "text \(text.debugDescription) needle \(needle.debugDescription)")
        // The prepared form must give the same answer as the direct one.
        #expect(TextSearch.matches(TextSearch.Haystack(text), query) == expected,
                "prepared disagreed: \(text.debugDescription) / \(needle.debugDescription)")
        checked += 1
    }
    #expect(checked > 15000)
}

/// The reference for whole-word matching, written the slow obvious way.
private func referenceContainsWord(_ word: String, in haystack: String) -> Bool {
    guard !word.isEmpty else { return false }
    let hay = Array(haystack.lowercased())
    let needle = Array(word.lowercased())
    guard hay.count >= needle.count else { return false }
    for start in 0...(hay.count - needle.count) {
        guard Array(hay[start..<start + needle.count]) == needle else { continue }
        let beforeOK = start == 0 || !hay[start - 1].isLetter
        let end = start + needle.count
        let afterOK = end == hay.count || !hay[end].isLetter
        if beforeOK, afterOK { return true }
    }
    return false
}

@Test func wholeWordMatchAgreesWithTheObviousImplementation() {
    var rng = FuzzGenerator(seed: 0x5EED_1234)
    for _ in 0..<20000 {
        let text = fuzzString(&rng, maxLength: 20)
        let word = fuzzString(&rng, maxLength: 4)
        guard !word.isEmpty else { continue }
        let expected = referenceContainsWord(word, in: text)
        #expect(KeywordCategorizer.containsWord(word.lowercased(), in: text.lowercased()) == expected,
                "string form: \(text.debugDescription) / \(word.debugDescription)")
        #expect(TextSearch.containsWord(TextSearch.Query(word), in: TextSearch.Haystack(text)) == expected,
                "byte form: \(text.debugDescription) / \(word.debugDescription)")
    }
}

// Text that is not plain ASCII must fall back to String, so the answer stays
// whatever String says, including canonical equivalence.
@Test func nonASCIITextKeepsStringSemantics() {
    let cases: [(String, String)] = [
        ("cafe\u{301} noir", "café"), ("caf\u{e9} noir", "cafe\u{301}"),
        ("\u{212A}elvin", "k"), ("Grüße", "GRÜSSE"), ("İstanbul", "i̇stanbul"),
        ("日本語のタイトル", "本語"), ("emoji 🎉 party", "🎉"),
        ("ＦＵＬＬＷＩＤＴＨ", "ｆｕｌｌ"),
    ]
    for (text, needle) in cases {
        let expected = text.lowercased().contains(needle.lowercased())
        #expect(TextSearch.matches(text, TextSearch.Query(needle)) == expected,
                "direct: \(text.debugDescription) / \(needle.debugDescription)")
        #expect(TextSearch.matches(TextSearch.Haystack(text), TextSearch.Query(needle)) == expected,
                "prepared: \(text.debugDescription) / \(needle.debugDescription)")
    }
}

@Test func survivesHostileText() {
    let hostile = [
        "", " ", "\0", "\u{FEFF}zero width", "a\u{0}b", String(repeating: "a", count: 100_000),
        "\u{202E}reversed", "line\nbreak\r\nhere", "\t\t\t", "🏳️‍🌈👨‍👩‍👧‍👦",
        "\u{1F600}\u{1F600}", "%00%2e%2e", "'; DROP TABLE --", "<script>alert(1)</script>",
    ]
    for text in hostile {
        for needle in ["a", "zero", "drop", "🏳️‍🌈", ""] {
            let query = TextSearch.Query(needle)
            // No crash, and the two forms must never disagree.
            let direct = TextSearch.matches(text, query)
            let prepared = TextSearch.matches(TextSearch.Haystack(text), query)
            #expect(direct == prepared, "\(text.prefix(20).debugDescription) / \(needle.debugDescription)")
        }
    }
}
