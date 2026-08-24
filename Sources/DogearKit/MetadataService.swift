import Foundation

public struct MetadataService: Sendable {
    let client: HTTPClient

    public init(client: HTTPClient) {
        self.client = client
    }

    static func fetcher(forHost host: String?) -> MetadataFetcher {
        guard let host = host?.lowercased() else { return GenericFetcher() }
        if host == "tiktok.com" || host.hasSuffix(".tiktok.com") { return TikTokFetcher() }
        if ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"].contains(host) {
            return XFetcher()
        }
        return GenericFetcher()
    }

    public func fetch(for url: URL) async -> (resolvedURL: URL, metadata: FetchedMetadata?) {
        guard let fetched = try? await client.fetch(url, limit: FetchLimit.html) else {
            return (url, nil)
        }
        let fetcher = Self.fetcher(forHost: fetched.finalURL.host)
        let metadata: FetchedMetadata?
        if type(of: fetcher).parsesPageBody {
            metadata = try? fetcher.parse(body: fetched.data, url: fetched.finalURL)
        } else {
            metadata = try? await fetcher.fetch(fetched.finalURL, client: client)
        }
        return (fetched.finalURL, metadata)
    }
}
