import Foundation
import Testing
@testable import DogearKit

private func fixture(_ name: String) throws -> String {
    let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    return try String(contentsOf: url, encoding: .utf8)
}

@Test func parsesOGTagsRegardlessOfAttributeOrder() throws {
    let data = OpenGraphParser.parse(html: try fixture("generic-page.html"))
    #expect(data.title == "How to Make Fresh Pasta 'Properly'")
    #expect(data.description == "A step-by-step pasta guide")
    #expect(data.imageURL?.absoluteString == "https://img.example.com/pasta.jpg?w=1200&h=630")
    #expect(data.siteName == "Example Cooking")
}

@Test func fallsBackToTitleTag() {
    let data = OpenGraphParser.parse(html: "<html><head><title>Only a &lt;title&gt;</title></head></html>")
    #expect(data.title == "Only a <title>")
}

@Test func survivesMalformedHTML() throws {
    let data = OpenGraphParser.parse(html: try fixture("malformed.html"))
    // No crash, no hang. Whatever parses, parses.
    _ = data
}

@Test func rejectsNonHTTPImageURL() {
    let html = """
    <html><head><meta property="og:image" content="file:///etc/hosts"></head></html>
    """
    let data = OpenGraphParser.parse(html: html)
    #expect(data.imageURL == nil)
}

@Test func emptyInputYieldsNils() {
    let data = OpenGraphParser.parse(html: "")
    #expect(data.title == nil && data.description == nil && data.imageURL == nil)
}

@Test func parsesUppercaseTagAndAttributeNames() {
    let html = """
    <HTML><HEAD>
    <META PROPERTY="og:title" CONTENT="Shouty Page">
    <TITLE>Ignored Fallback</TITLE>
    </HEAD></HTML>
    """
    #expect(OpenGraphParser.parse(html: html).title == "Shouty Page")
}

@Test func fallsBackToAnUppercaseTitleTag() {
    #expect(OpenGraphParser.parse(html: "<HTML><TITLE>Shouty Title</TITLE></HTML>").title == "Shouty Title")
}

@Test func parsesSingleQuotedAttributeValues() {
    let html = "<html><head><meta property='og:title' content='Single Quoted'></head></html>"
    #expect(OpenGraphParser.parse(html: html).title == "Single Quoted")
}

@Test func parsesContentContainingAGreaterThan() {
    let html = "<html><head><meta property=\"og:description\" content=\"5 > 3 tips\"></head></html>"
    #expect(OpenGraphParser.parse(html: html).description == "5 > 3 tips")
}

@Test func propertyWinsOverName() {
    let propertyFirst = "<html><head><meta property=\"og:title\" name=\"twitter:title\" content=\"Real\"></head></html>"
    #expect(OpenGraphParser.parse(html: propertyFirst).title == "Real")

    let nameFirst = "<html><head><meta name=\"twitter:title\" property=\"og:title\" content=\"Real\"></head></html>"
    #expect(OpenGraphParser.parse(html: nameFirst).title == "Real")
}

@Test func singleQuotedContentWithAGreaterThan() {
    let html = "<html><head><meta property='og:title' content='a > b'></head></html>"
    #expect(OpenGraphParser.parse(html: html).title == "a > b")
}

@Test func unquotedGreaterThanStillEndsTheTag() {
    let html = "<html><head><meta property=\"og:title\" content=\"x\">trailing<p></head></html>"
    #expect(OpenGraphParser.parse(html: html).title == "x")
}

@Test func doubleEncodedNamedEntityDecodesFully() {
    // The author wrote the literal text "&lt;", escaping the ampersand as "&amp;".
    // Ruling: sites like LinkedIn double-encode og titles, so a second
    // decode pass runs when the first leaves entities behind. A title that
    // literally discusses "&lt;" loses one level; sloppy double-encoding
    // is far more common than titles about HTML entities.
    #expect(OpenGraphParser.decodeEntities("Fish &amp;lt; Chips") == "Fish < Chips")
}

@Test func decodesApostropheEntity() {
    #expect(OpenGraphParser.decodeEntities("Gordon&apos;s") == "Gordon's")
}

@Test func decodesHexNumericEntity() {
    #expect(OpenGraphParser.decodeEntities("Here&#x2019;s the plan") == "Here\u{2019}s the plan")
}

@Test func decodesDecimalNumericEntity() {
    #expect(OpenGraphParser.decodeEntities("Here&#8217;s the plan") == "Here\u{2019}s the plan")
}

@Test func leavesAnInvalidScalarEntityAsIs() {
    // 55296 is 0xD800, a surrogate: not a valid Unicode scalar.
    #expect(OpenGraphParser.decodeEntities("bad &#55296; scalar") == "bad &#55296; scalar")
}

@Test func doubleEncodedNumericEntityDecodesFully() {
    // The author wrote the literal text "&#8217;", escaping the ampersand.
    #expect(OpenGraphParser.decodeEntities("&amp;#8217;") == "\u{2019}")
}
