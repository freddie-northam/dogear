import Foundation

public struct GenericFetcher: MetadataFetcher {
    public init() {}

    public func fetch(_ url: URL, client: HTTPClient) async throws -> FetchedMetadata {
        let data = try await client.data(from: url, limit: FetchLimit.html)
        let og = OpenGraphParser.parse(html: String(decoding: data, as: UTF8.self))
        guard og.title != nil else { throw HTTPClientError.noResponse }
        return FetchedMetadata(
            title: og.title,
            author: og.siteName,
            description: og.description,
            thumbnailURL: og.imageURL,
            source: .web
        )
    }
}
