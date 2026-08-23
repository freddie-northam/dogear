import Foundation

public let DogearUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

public enum FetchLimit {
    public static let html = 1_000_000       // 1 MB
    public static let thumbnail = 10_000_000 // 10 MB
}

public enum HTTPClientError: Error, Equatable {
    case tooLarge
    case badStatus(Int)
    case noResponse
}

public protocol HTTPClient: Sendable {
    func data(from url: URL, limit: Int) async throws -> Data
    func resolvedURL(for url: URL) async throws -> URL
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        config.httpAdditionalHeaders = ["User-Agent": DogearUserAgent]
        session = URLSession(configuration: config)
    }

    public func data(from url: URL, limit: Int) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse else { throw HTTPClientError.noResponse }
        guard (200..<300).contains(http.statusCode) else { throw HTTPClientError.badStatus(http.statusCode) }
        var data = Data()
        data.reserveCapacity(min(limit, Int(http.expectedContentLength.clamped())))
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit { throw HTTPClientError.tooLarge }
        }
        return data
    }

    public func resolvedURL(for url: URL) async throws -> URL {
        // URLSession follows redirects by default; the response URL is the final one.
        // A GET, not a HEAD: some shorteners (t.co) reject HEAD. bytes(for:) hands
        // back the response before the body, so cancel instead of draining it.
        let (bytes, response) = try await session.bytes(from: url)
        bytes.task.cancel()
        return response.url ?? url
    }
}

private extension Int64 {
    func clamped() -> Int64 { self < 0 ? 0 : self }
}
