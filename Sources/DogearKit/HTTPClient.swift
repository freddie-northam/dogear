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
    func fetch(_ url: URL, limit: Int) async throws -> (data: Data, finalURL: URL)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let configuration: URLSessionConfiguration

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        config.httpAdditionalHeaders = ["User-Agent": DogearUserAgent]
        self.init(configuration: config)
    }

    public init(configuration: URLSessionConfiguration) {
        self.configuration = configuration
    }

    public func data(from url: URL, limit: Int) async throws -> Data {
        try await load(url, limit: limit).data
    }

    public func fetch(_ url: URL, limit: Int) async throws -> (data: Data, finalURL: URL) {
        try await load(url, limit: limit)
    }

    // Chunked (not byte-by-byte) reads with the cap enforced as chunks arrive, so an
    // oversized response is cancelled mid-download rather than fully buffered first.
    // A `URLSessionDataDelegate` is the only API that exposes chunk-level delivery;
    // one delegate per session, so each call gets its own ephemeral session.
    private func load(_ url: URL, limit: Int) async throws -> (data: Data, finalURL: URL) {
        let delegate = BufferingDelegate(limit: limit)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: url)
        return try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            task.resume()
        }
    }
}

private final class BufferingDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private var buffer = Data()
    private var finished = false
    var continuation: CheckedContinuation<(data: Data, finalURL: URL), Error>?

    init(limit: Int) {
        self.limit = limit
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            finish(.failure(HTTPClientError.noResponse))
            completionHandler(.cancel)
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            finish(.failure(HTTPClientError.badStatus(http.statusCode)))
            completionHandler(.cancel)
            return
        }
        buffer.reserveCapacity(min(limit, Int(http.expectedContentLength.clamped())))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        if buffer.count > limit {
            finish(.failure(HTTPClientError.tooLarge))
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
            return
        }
        let finalURL = task.currentRequest?.url ?? task.originalRequest?.url
        guard let finalURL else {
            finish(.failure(HTTPClientError.noResponse))
            return
        }
        finish(.success((buffer, finalURL)))
    }

    // Guards against a double-resume: a `tooLarge` cancel triggers `didCompleteWithError`
    // too, and that second call must be a no-op.
    private func finish(_ result: Result<(data: Data, finalURL: URL), Error>) {
        guard !finished, let continuation else { return }
        finished = true
        continuation.resume(with: result)
    }
}

private extension Int64 {
    func clamped() -> Int64 { self < 0 ? 0 : self }
}
