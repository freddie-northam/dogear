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
        let resolved = (try? await client.resolvedURL(for: url)) ?? url
        let fetcher = Self.fetcher(forHost: resolved.host)
        let metadata = try? await fetcher.fetch(resolved, client: client)
        return (resolved, metadata)
    }
}
