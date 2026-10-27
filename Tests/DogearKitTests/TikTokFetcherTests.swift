import Foundation
import Testing
@testable import DogearKit

private func page(_ name: String) throws -> Data {
    try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures")!)
}

@Test func parsesRealVideoPage() throws {
    let url = URL(string: "https://www.tiktok.com/@gordonramsayofficial/video/7510682972576746775")!
    let metadata = try TikTokFetcher().parse(body: page("tiktok-video"), url: url)
    #expect(metadata.source == .tiktok)
    #expect(metadata.author == "Gordon Ramsay")
    #expect(metadata.title == "Let me cook I guess 😉 #holyairball")
    #expect(metadata.thumbnailURL?.host == "p16-common-sign.tiktokcdn-eu.com")
}

@Test func parsesRealProfilePage() throws {
    let url = URL(string: "https://www.tiktok.com/@gordonramsayofficial")!
    let metadata = try TikTokFetcher().parse(body: page("tiktok-profile"), url: url)
    #expect(metadata.source == .tiktok)
    #expect(metadata.title == "Gordon Ramsay")
    #expect(metadata.description == "I cook sometimes too.....")
    #expect(metadata.thumbnailURL != nil)
}

@Test func throwsOnRemovedVideo() {
    let url = URL(string: "https://www.tiktok.com/@gordonramsayofficial/video/1")!
    #expect(throws: Error.self) { try TikTokFetcher().parse(body: page("tiktok-missing"), url: url) }
}

@Test func throwsOnPageWithoutTikTokData() {
    let url = URL(string: "https://www.tiktok.com/@a/video/1")!
    #expect(throws: Error.self) { try TikTokFetcher().parse(body: page("generic-page"), url: url) }
}

@Test func rejectsNonHTTPThumbnailURL() throws {
    let body = Data(#"""
    <script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">{"__DEFAULT_SCOPE__":{"webapp.video-detail":{"statusCode":0,"itemInfo":{"itemStruct":{"desc":"A video","author":{"nickname":"A"},"video":{"cover":"file:///etc/hosts"}}}}}}</script>
    """#.utf8)
    let metadata = try TikTokFetcher().parse(body: body, url: URL(string: "https://www.tiktok.com/@a/video/2")!)
    #expect(metadata.title == "A video")
    #expect(metadata.thumbnailURL == nil)
}
