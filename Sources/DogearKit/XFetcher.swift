import Foundation

public struct XFetcher: MetadataFetcher {
    public init() {}

    public func fetch(_ url: URL, client: HTTPClient) async throws -> FetchedMetadata {
        let data = try await client.data(from: url, limit: FetchLimit.html)
        return try parse(body: data, url: url)
    }

    public func parse(body: Data, url: URL) throws -> FetchedMetadata {
        let html = String(decoding: body, as: UTF8.self)
        let og = OpenGraphParser.parse(html: html)
        guard let text = og.description, !text.isEmpty else {
            throw HTTPClientError.noResponse
        }
        let author = og.title.map { title in
            title.hasSuffix(" on X") ? String(title.dropLast(" on X".count)) : title
        }
        // A text-only tweet's og:image is the author avatar, not tweet media;
        // an avatar makes a misleading thumbnail.
        let thumbnailURL: URL? = og.imageURL.flatMap {
            $0.path.contains("/profile_images/") ? nil : $0
        }
        return FetchedMetadata(
            title: Self.composeTitle(author: author, text: text),
            author: author,
            description: text,
            thumbnailURL: thumbnailURL,
            source: .x
        )
    }

    static func composeTitle(author: String?, text: String) -> String {
        var snippet = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if snippet.count > 80 {
            snippet = String(snippet.prefix(80)) + "…"
        }
        guard let author, !author.isEmpty else { return snippet }
        return "\(author): \(snippet)"
    }
}
