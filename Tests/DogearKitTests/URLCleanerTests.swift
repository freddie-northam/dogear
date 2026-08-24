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

@Test func extractsURLsFromNotesStyleHTML() {
    let html = """
    <div><a href="https://a.com/recipe?id=1&amp;u=2">Great recipe</a></div>
    <div>plain text https://b.com/x end</div>
    """
    #expect(URLCleaner.allHTTPURLs(inHTML: html).map(\.absoluteString)
        == ["https://a.com/recipe?id=1&u=2", "https://b.com/x"])
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

@Test func canonicalKeepsPercentEncodedPathSeparators() {
    let url = URL(string: "https://a.com/a%2Fb/")!
    #expect(URLCleaner.canonicalString(url) == "https://a.com/a%2Fb")
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

@Test func trimsExtractedURLAtHTMLMarkup() {
    let urls = URLCleaner.allHTTPURLs(in: "see https://a.com/tools/</div> and https://b.com/x\"&gt;")
    #expect(urls.first?.absoluteString == "https://a.com/tools/")
    #expect(urls.count >= 1)
    for url in urls {
        #expect(!url.absoluteString.contains("%3C"))
        #expect(!url.absoluteString.contains("\""))
    }
}

@Test func keepsApostrophesInExtractedURLs() {
    let urls = URLCleaner.allHTTPURLs(in: "read https://en.wikipedia.org/wiki/It%27s_a_Wonderful_Life and https://a.com/don't-stop")
    #expect(urls.count == 2)
    #expect(urls[0].absoluteString.contains("%27"))
    #expect(urls[1].absoluteString.contains("'") || urls[1].absoluteString.contains("%27"))
}

@Test func extractsLinksFromANetscapeBookmarkFile() {
    let html = """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <TITLE>Bookmarks</TITLE>
    <DL><p>
        <DT><H3>Reading</H3>
        <DL><p>
            <DT><A HREF="https://a.com/one?x=1&amp;y=2" ADD_DATE="1700000000">One</A>
            <DT><A HREF="https://b.com/two">Two</A>
        </DL><p>
    </DL><p>
    """
    let urls = URLCleaner.allHTTPURLs(inHTML: html).map(\.absoluteString)
    #expect(urls == ["https://a.com/one?x=1&y=2", "https://b.com/two"])
}

@Test func canonicalUnifiesTwitterHostsToX() {
    let a = URLCleaner.canonicalString(URL(string: "https://twitter.com/jack/status/20")!)
    let b = URLCleaner.canonicalString(URL(string: "https://x.com/jack/status/20")!)
    let c = URLCleaner.canonicalString(URL(string: "https://mobile.twitter.com/jack/status/20")!)
    #expect(a == b)
    #expect(c == b)
}
