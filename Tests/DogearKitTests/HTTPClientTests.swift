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

private func stubbedClient() -> URLSessionHTTPClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSessionHTTPClient(configuration: config)
}

@Test func realClientThrowsTooLargePastTheLimit() async throws {
    let client = stubbedClient()
    await #expect(throws: HTTPClientError.tooLarge) {
        _ = try await client.data(from: URL(string: "https://93.184.215.14/x")!, limit: 1_000)
    }
}

@Test func realClientReturnsTheWholeBodyUnderTheLimit() async throws {
    let client = stubbedClient()
    let data = try await client.data(from: URL(string: "https://93.184.215.14/x")!, limit: 10_000)
    #expect(data.count == 2_000)
}

@Test(arguments: [
    "127.0.0.1", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.1", "169.254.169.254",
    "0.0.0.0", "100.64.0.1", "224.0.0.1", "::1", "::", "fc00::1", "fd12::1", "fe80::1",
    "::ffff:127.0.0.1", "::ffff:192.168.0.1",
])
func aPrivateAddressIsNotPublic(address: String) {
    #expect(NetworkDestination.isPublic(address: address) == false)
}

@Test(arguments: ["8.8.8.8", "172.15.0.1", "172.32.0.1", "100.128.0.1", "93.184.215.14", "2606:4700::1111"])
func aPublicAddressIsPublic(address: String) {
    #expect(NetworkDestination.isPublic(address: address))
}

@Test(arguments: ["http://127.0.0.1:8080/", "http://localhost/", "http://[::1]/", "http://192.168.1.1/admin"])
func theRealClientRefusesAPrivateDestination(url: String) async {
    await #expect(throws: HTTPClientError.privateDestination) {
        _ = try await stubbedClient().data(from: URL(string: url)!, limit: 1_000)
    }
}

@Test func theRealClientRefusesANameThatDoesNotResolve() async {
    await #expect(throws: HTTPClientError.privateDestination) {
        _ = try await stubbedClient().data(from: URL(string: "https://no-such-host.invalid/")!, limit: 1_000)
    }
}

private final class RedirectingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let target = URL(string: "http://192.168.1.1/admin")!
        let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil,
                                       headerFields: ["Location": target.absoluteString])!
        client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
    }

    override func stopLoading() {}
}

@Test func theRealClientRefusesARedirectToAPrivateDestination() async {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RedirectingURLProtocol.self]
    await #expect(throws: HTTPClientError.privateDestination) {
        _ = try await URLSessionHTTPClient(configuration: config)
            .data(from: URL(string: "https://93.184.215.14/")!, limit: 1_000)
    }
}
