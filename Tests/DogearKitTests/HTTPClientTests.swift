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

// Serves a canned 2,000-byte body for any request, so the real client's cap
// enforcement can be tested without hitting the network.
private final class StubURLProtocol: URLProtocol {
    static let canned = Data(repeating: 0x41, count: 2_000)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.canned)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class PrivateRedirectURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let target = URL(string: "http://127.0.0.1/private")!
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 302, httpVersion: nil,
            headerFields: ["Location": target.absoluteString])!
        client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
    }

    override func stopLoading() {}
}

private func stubbedClient() -> URLSessionHTTPClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSessionHTTPClient(configuration: config)
}

@Test func realClientThrowsTooLargePastTheLimit() async throws {
    let client = stubbedClient()
    await #expect(throws: HTTPClientError.tooLarge) {
        _ = try await client.data(from: URL(string: "https://1.1.1.1/x")!, limit: 1_000)
    }
}

@Test func realClientReturnsTheWholeBodyUnderTheLimit() async throws {
    let client = stubbedClient()
    let data = try await client.data(from: URL(string: "https://1.1.1.1/x")!, limit: 10_000)
    #expect(data.count == 2_000)
}

@Test(arguments: [
    "http://127.0.0.1/private",
    "http://10.0.0.1/private",
    "http://169.254.1.1/private",
    "http://192.168.1.1/private",
    "http://[::1]/private",
    "http://[fd00::1]/private",
    "http://[fec0::1]/private",
    "http://[64:ff9b:1::1]/private",
])
func blocksPrivateNetworkDestinations(url: String) async {
    let client = stubbedClient()
    await #expect(throws: HTTPClientError.unsafeDestination) {
        _ = try await client.data(from: URL(string: url)!, limit: 10_000)
    }
}

@Test func blocksRedirectsToPrivateNetworkDestinations() async {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [PrivateRedirectURLProtocol.self]
    let client = URLSessionHTTPClient(configuration: config)
    await #expect(throws: HTTPClientError.unsafeDestination) {
        _ = try await client.data(from: URL(string: "https://1.1.1.1/start")!, limit: 10_000)
    }
}
