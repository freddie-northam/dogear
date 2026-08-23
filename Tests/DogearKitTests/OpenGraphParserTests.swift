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

@Test func doesNotDoubleDecodeAnEscapedAmpersand() {
    // The author wrote the literal text "&lt;", escaping the ampersand as "&amp;".
    #expect(OpenGraphParser.decodeEntities("Fish &amp;lt; Chips") == "Fish &lt; Chips")
}

@Test func decodesApostropheEntity() {
    #expect(OpenGraphParser.decodeEntities("Gordon&apos;s") == "Gordon's")
}
