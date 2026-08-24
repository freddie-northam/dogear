import Darwin
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
    case unsafeDestination
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
        // ponytail: URLSession resolves again after this preflight. Move enrichment
        // into a sandboxed helper if DNS rebinding becomes a demonstrated risk.
        let allowed = await Task.detached { NetworkDestinationPolicy.allows(url) }.value
        guard allowed else { throw HTTPClientError.unsafeDestination }
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
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, NetworkDestinationPolicy.allows(url) else {
            finish(.failure(HTTPClientError.unsafeDestination))
            completionHandler(nil)
            return
        }
        completionHandler(request)
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

enum NetworkDestinationPolicy {
    static func allows(_ url: URL) -> Bool {
        guard URLCleaner.isCapturable(url), let host = url.host, !host.isEmpty else { return false }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return false }
        defer { freeaddrinfo(first) }

        var found = false
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor {
            guard let address = info.pointee.ai_addr else { return false }
            found = true
            if !isPublic(address, family: info.pointee.ai_family) { return false }
            cursor = info.pointee.ai_next
        }
        return found
    }

    private static func isPublic(_ address: UnsafePointer<sockaddr>, family: Int32) -> Bool {
        if family == AF_INET {
            var value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            return withUnsafeBytes(of: &value) { isPublicIPv4(Array($0)) }
        }
        if family == AF_INET6 {
            var value = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
            return withUnsafeBytes(of: &value) { isPublicIPv6(Array($0)) }
        }
        return false
    }

    private static func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return false }
        let (a, b, c) = (bytes[0], bytes[1], bytes[2])
        if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
        if a == 100 && (64...127).contains(b) { return false }
        if a == 169 && b == 254 { return false }
        if a == 172 && (16...31).contains(b) { return false }
        if a == 192 && (b == 168 || (b == 0 && c == 0) || (b == 0 && c == 2)) { return false }
        if a == 198 && (b == 18 || b == 19 || (b == 51 && c == 100)) { return false }
        if a == 203 && b == 0 && c == 113 { return false }
        return true
    }

    private static func isPublicIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return false }
        if bytes.allSatisfy({ $0 == 0 }) || bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 {
            return false
        }
        if bytes[0] & 0xFE == 0xFC || bytes[0] == 0xFF { return false }
        if bytes[0] == 0xFE && (bytes[1] & 0xC0 == 0x80 || bytes[1] & 0xC0 == 0xC0) {
            return false
        }
        if bytes.prefix(12) == Array(repeating: 0, count: 10) + [0xFF, 0xFF] {
            return isPublicIPv4(Array(bytes.suffix(4)))
        }
        if Array(bytes.prefix(4)) == [0x20, 0x01, 0x0D, 0xB8] { return false }
        if Array(bytes.prefix(6)) == [0x00, 0x64, 0xFF, 0x9B, 0x00, 0x01] { return false }
        return true
    }
}

private extension Int64 {
    func clamped() -> Int64 { self < 0 ? 0 : self }
}
