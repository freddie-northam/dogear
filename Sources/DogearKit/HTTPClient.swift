import Foundation

public let DogearUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

public enum FetchLimit {
    public static let html = 1_000_000
    public static let thumbnail = 10_000_000
}

public enum HTTPClientError: Error, Equatable {
    case tooLarge
    case badStatus(Int)
    case noResponse
    case privateDestination
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
        guard NetworkDestination.allows(url) else { throw HTTPClientError.privateDestination }
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

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, NetworkDestination.allows(url) else {
            finish(.failure(HTTPClientError.privateDestination))
            completionHandler(nil)
            task.cancel()
            return
        }
        completionHandler(request)
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

/// Decides whether Dogear may send a request to a host.
/// A saved page can name, or redirect to, a router or a local server, and a fetch of it acts with the user's network access.
public enum NetworkDestination {
    /// True when the host resolves, and every address it resolves to is public.
    /// ponytail: blocking `getaddrinfo` on a pool thread, and URLSession resolves the name again, so DNS rebinding gets through. Pin the address in the request if that matters.
    static func allows(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { return false }
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let list else { return false }
        defer { freeaddrinfo(list) }
        return sequence(first: list, next: { $0.pointee.ai_next }).allSatisfy { entry in
            guard let address = entry.pointee.ai_addr else { return false }
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                return address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    withUnsafeBytes(of: $0.pointee.sin_addr) { isPublic(Array($0)) }
                }
            case AF_INET6:
                return address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    withUnsafeBytes(of: $0.pointee.sin6_addr) { isPublic(Array($0)) }
                }
            default:
                return false
            }
        }
    }

    /// True for a numeric IPv4 or IPv6 address outside every private, local, and reserved range.
    static func isPublic(address: String) -> Bool {
        var v4 = in_addr()
        if inet_pton(AF_INET, address, &v4) == 1 { return withUnsafeBytes(of: v4) { isPublic(Array($0)) } }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, address, &v6) == 1 { return withUnsafeBytes(of: v6) { isPublic(Array($0)) } }
        return false
    }

    private static func isPublic(_ b: [UInt8]) -> Bool {
        if b.count == 4 {
            switch (b[0], b[1], b[2]) {
            case (0, _, _), (10, _, _), (127, _, _), (169, 254, _), (192, 168, _),
                 (192, 0, 0), (192, 0, 2), (198, 51, 100), (203, 0, 113):
                return false
            case (100, let x, _) where x & 0xC0 == 64: return false
            case (172, let x, _) where x & 0xF0 == 16: return false
            case (198, let x, _) where x & 0xFE == 18: return false
            default: return b[0] < 224
            }
        }
        // These IPv6 forms carry an IPv4 address: mapped (::ffff:0:0/96), NAT64 (64:ff9b::/96), and 6to4 (2002::/16).
        if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF { return isPublic(Array(b[12...])) }
        if b[0..<12] == [0, 0x64, 0xFF, 0x9B, 0, 0, 0, 0, 0, 0, 0, 0] { return isPublic(Array(b[12...])) }
        if b[0] == 0x20 && b[1] == 0x02 { return isPublic(Array(b[2..<6])) }
        // Only global unicast (2000::/3) is public, less Teredo (2001::/32) and documentation (2001:db8::/32).
        if b[0..<4] == [0x20, 0x01, 0, 0] || b[0..<4] == [0x20, 0x01, 0x0D, 0xB8] { return false }
        return b[0] & 0xE0 == 0x20
    }
}
