import Foundation

public struct TikTokFetcher: MetadataFetcher {
    public init() {}

    static func oembedURL(for url: URL) -> URL {
        var parts = URLComponents(string: "https://www.tiktok.com/oembed")!
        parts.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return parts.url!
    }

    private struct OEmbed: Decodable {
        let title: String?
        let author_name: String?
        let thumbnail_url: String?
    }

    public func fetch(_ url: URL, client: HTTPClient) async throws -> FetchedMetadata {
        let data = try await client.data(from: Self.oembedURL(for: url), limit: FetchLimit.html)
        let oembed = try JSONDecoder().decode(OEmbed.self, from: data)
        guard oembed.title != nil || oembed.author_name != nil else {
            throw HTTPClientError.noResponse
        }
        return FetchedMetadata(
            title: oembed.title?.trimmingCharacters(in: .whitespacesAndNewlines),
            author: oembed.author_name,
            description: oembed.title,
            thumbnailURL: oembed.thumbnail_url.flatMap(URL.init(string:)).flatMap { URLCleaner.isCapturable($0) ? $0 : nil },
            source: .tiktok
        )
    }
}
