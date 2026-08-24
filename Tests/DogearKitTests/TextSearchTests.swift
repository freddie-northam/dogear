import Foundation
import Testing
@testable import DogearKit

private func matches(_ haystack: String, _ query: String) -> Bool {
    TextSearch.matches(haystack, TextSearch.Query(query))
}

@Test func findsASubstringAnywhereInTheText() {
    #expect(matches("carbonara recipe", "carbonara"))
    #expect(matches("carbonara recipe", "recipe"))
    #expect(matches("carbonara recipe", "ara rec"))
    #expect(!matches("carbonara recipe", "risotto"))
}

@Test func ignoresCaseInBothDirections() {
    #expect(matches("CARBONARA", "carbonara"))
    #expect(matches("carbonara", "CARBONARA"))
    #expect(matches("CarBonAra", "bOnA"))
}

@Test func matchesTheWholeTextAndItsEdges() {
    #expect(matches("abc", "abc"))
    #expect(matches("abc", "a"))
    #expect(matches("abc", "c"))
}

@Test func rejectsAQueryLongerThanTheText() {
    #expect(!matches("ab", "abc"))
}

@Test func anEmptyQueryMatchesNothing() {
    #expect(!matches("anything", ""))
    #expect(TextSearch.Query("").isEmpty)
}

@Test func aNilFieldNeverMatches() {
    #expect(!TextSearch.matches(nil, TextSearch.Query("a")))
}

@Test func handlesNonASCIITextWithAnASCIIQuery() {
    #expect(matches("Café København", "kobenhavn") == false)
    #expect(matches("Café København", "caf"))
    #expect(matches("Café København", "benhavn"))
}

// The byte scan folds A-Z only, so a query that carries an accent takes the
// Unicode path. Both directions of case must still work there.
@Test func foldsCaseForNonASCIIQueries() {
    #expect(matches("CAFÉ NOIR", "café"))
    #expect(matches("café noir", "CAFÉ"))
    #expect(matches("Grüße", "grüße"))
    #expect(!matches("Café", "cafét"))
}

// The same word can be stored as one character or as a letter plus a
// combining accent. Page metadata arrives in both spellings, so a query
// typed in one must find a title written in the other.
@Test func matchesEitherSpellingOfAnAccentedWord() {
    #expect(matches("cafe\u{0301} noir", "café"))
    #expect(matches("café noir", "cafe\u{0301}"))
}

// A multi-byte character must not be matched from the middle of its bytes.
@Test func doesNotMatchAPartialMultiByteCharacter() {
    #expect(!matches("é", "\u{00A9}"))
}

@Test func matchesRepeatedPrefixesCorrectly() {
    #expect(matches("aaab", "aab"))
    #expect(!matches("aaa", "aab"))
}

