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

    func resolvedURL(for url: URL) async throws -> URL {
        if failEverything { throw HTTPClientError.noResponse }
        // Match on canonical form: a bookmark's URL is already canonicalized (e.g. trailing
        // slash stripped) by the time enrichment re-resolves it, so exact URL equality would
        // miss a redirect keyed on the pre-canonicalization URL.
        let needle = URLCleaner.canonicalString(url)
        if let match = redirects.first(where: { URLCleaner.canonicalString($0.key) == needle }) {
            return match.value
        }
        return url
    }

    func requestedURLs() async -> [URL] { await log.all() }
}
