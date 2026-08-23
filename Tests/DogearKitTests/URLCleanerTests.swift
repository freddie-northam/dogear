import Foundation
import Testing
@testable import DogearKit

@Test func extractsFirstURLFromText() {
    let url = URLCleaner.firstHTTPURL(in: "check this out https://vm.tiktok.com/ZM2/ so good")
    #expect(url?.absoluteString == "https://vm.tiktok.com/ZM2/")
}

@Test func acceptsBareHTTPSURL() {
    #expect(URLCleaner.firstHTTPURL(in: "https://x.com/jack/status/20")?.host == "x.com")
}

@Test func extractsAllURLsInOrderFromMixedText() {
    let text = """
    Recipes to try https://a.com/pasta and https://b.com/soup
    mailto:someone@example.com then http://c.com/bread at the end
    """
    let urls = URLCleaner.allHTTPURLs(in: text).map(\.absoluteString)
    #expect(urls == ["https://a.com/pasta", "https://b.com/soup", "http://c.com/bread"])
}

@Test func allHTTPURLsReturnsEmptyForJunk() {
    #expect(URLCleaner.allHTTPURLs(in: "just words, no links at all").isEmpty)
}

@Test(arguments: ["javascript:alert(1)", "file:///etc/passwd", "data:text/html,hi", "ftp://host/x", "not a url"])
func rejectsNonHTTPSchemes(text: String) {
    #expect(URLCleaner.firstHTTPURL(in: text) == nil)
}

@Test func canonicalStripsTrackingParams() {
    let url = URL(string: "https://a.com/p?utm_source=tw&id=5&utm_campaign=x&fbclid=z&igsh=q&si=r")!
    #expect(URLCleaner.canonicalString(url) == "https://a.com/p?id=5")
}

@Test func canonicalStripsFragmentAndTrailingSlash() {
    let url = URL(string: "https://a.com/p/#section")!
    #expect(URLCleaner.canonicalString(url) == "https://a.com/p")
}

@Test func canonicalKeepsTrailingSlashInsideAQueryValue() {
    let url = URL(string: "https://a.com/p?next=/")!
    #expect(URLCleaner.canonicalString(url) == "https://a.com/p?next=/")
}

@Test func canonicalLowercasesScheme() {
    let url = URL(string: "HTTPS://x.com/jack")!
    #expect(URLCleaner.canonicalString(url) == "https://x.com/jack")
}

@Test func canonicalLowercasesHost() {
    let url = URL(string: "https://X.com/Jack")!
    #expect(URLCleaner.canonicalString(url) == "https://x.com/Jack")
}

@Test func canonicalKeepsTimestampOnNonXHost() {
    let url = URL(string: "https://youtube.com/watch?v=A&t=120")!
    #expect(URLCleaner.canonicalString(url) == "https://youtube.com/watch?v=A&t=120")
}

@Test func canonicalStripsShareAndTimestampOnXHost() {
    let url = URL(string: "https://x.com/a/status/1?s=20&t=xyz")!
    #expect(URLCleaner.canonicalString(url) == "https://x.com/a/status/1")
}
