import Foundation
import Testing
@testable import DogearKit

@Test func userAgentIsThePinnedBrowserString() {
    #expect(DogearUserAgent.contains("Safari"))
    #expect(!DogearUserAgent.contains("CFNetwork"))
}

@Test func stubClientReturnsCannedDataAndRecords() async throws {
    let stub = StubHTTPClient(responses: [
        URL(string: "https://a.com/x")!: Data("hello".utf8)
    ])
    let data = try await stub.data(from: URL(string: "https://a.com/x")!, limit: 1_000_000)
    #expect(String(decoding: data, as: UTF8.self) == "hello")
    #expect(await stub.requestedURLs() == [URL(string: "https://a.com/x")!])
}

@Test func stubClientThrowsForUnknownURL() async {
    let stub = StubHTTPClient(responses: [:])
    await #expect(throws: HTTPClientError.self) {
        _ = try await stub.data(from: URL(string: "https://missing.com")!, limit: 100)
    }
}

@Test func stubClientEnforcesLimit() async {
    let url = URL(string: "https://a.com/big")!
    let stub = StubHTTPClient(responses: [url: Data(count: 2_000)])
    await #expect(throws: HTTPClientError.tooLarge) {
        _ = try await stub.data(from: url, limit: 1_000)
    }
}
