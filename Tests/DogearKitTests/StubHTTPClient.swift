import Foundation
@testable import DogearKit

actor RequestLog {
    private var urls: [URL] = []
    func record(_ url: URL) { urls.append(url) }
    func all() -> [URL] { urls }
}

struct StubHTTPClient: HTTPClient {
    let responses: [URL: Data]
    var redirects: [URL: URL] = [:]
    var failEverything = false
    private let log = RequestLog()

    init(responses: [URL: Data]) {
        self.responses = responses
    }

    func data(from url: URL, limit: Int) async throws -> Data {
        await log.record(url)
        if failEverything { throw HTTPClientError.noResponse }
        guard let data = responses[url] else { throw HTTPClientError.badStatus(404) }
        if data.count > limit { throw HTTPClientError.tooLarge }
        return data
    }

    func fetch(_ url: URL, limit: Int) async throws -> (data: Data, finalURL: URL) {
        // Match on canonical form, same as resolvedURL: a redirect keyed on the
        // pre-canonicalization URL must still match.
        let needle = URLCleaner.canonicalString(url)
        let finalURL = redirects.first(where: { URLCleaner.canonicalString($0.key) == needle })?.value ?? url
        await log.record(finalURL)
        if failEverything { throw HTTPClientError.noResponse }
        guard let data = responses[finalURL] ?? responses[url] else { throw HTTPClientError.badStatus(404) }
        if data.count > limit { throw HTTPClientError.tooLarge }
        return (data, finalURL)
    }

    func requestedURLs() async -> [URL] { await log.all() }
}
