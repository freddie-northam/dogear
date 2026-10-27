import Foundation

/// Reads TikTok metadata from the JSON that TikTok embeds in every video and profile page.
public struct TikTokFetcher: MetadataFetcher {
    public init() {}

    public func fetch(_ url: URL, client: HTTPClient) async throws -> FetchedMetadata {
        try parse(body: try await client.data(from: url, limit: FetchLimit.html), url: url)
    }

    // Not the public oEmbed endpoint: it rate-limits, and it can answer 200 with no title or author.
    public func parse(body: Data, url: URL) throws -> FetchedMetadata {
        guard let json = Self.rehydrationJSON(in: String(decoding: body, as: UTF8.self)) else {
            throw HTTPClientError.noResponse
        }
        let scope = try JSONDecoder().decode(Rehydration.self, from: Data(json.utf8)).scope
        let metadata: FetchedMetadata
        if let item = scope.video?.itemInfo?.itemStruct {
            let caption = item.desc?.trimmingCharacters(in: .whitespacesAndNewlines)
            metadata = FetchedMetadata(
                title: caption?.isEmpty == false ? caption : nil,
                author: item.author?.nickname,
                description: caption,
                thumbnailURL: Self.capturable(item.video?.cover),
                source: .tiktok
            )
        } else if let user = scope.user?.userInfo?.user {
            metadata = FetchedMetadata(
                title: user.nickname,
                author: user.nickname,
                description: user.signature,
                thumbnailURL: Self.capturable(user.avatarLarger),
                source: .tiktok
            )
        } else {
            throw HTTPClientError.noResponse
        }
        guard metadata.title != nil || metadata.author != nil else { throw HTTPClientError.noResponse }
        return metadata
    }

    static func rehydrationJSON(in html: String) -> Substring? {
        guard let tag = html.range(of: #"<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__""#),
              let open = html[tag.upperBound...].range(of: ">"),
              let close = html[open.upperBound...].range(of: "</script>") else { return nil }
        return html[open.upperBound..<close.lowerBound]
    }

    private static func capturable(_ string: String?) -> URL? {
        string.flatMap(URL.init(string:)).flatMap { URLCleaner.isCapturable($0) ? $0 : nil }
    }

    // Only the fields Dogear reads. TikTok's page carries many more, and decoding ignores them.
    private struct Rehydration: Decodable {
        let scope: Scope
        enum CodingKeys: String, CodingKey { case scope = "__DEFAULT_SCOPE__" }

        struct Scope: Decodable {
            let video: VideoDetail?
            let user: UserDetail?
            enum CodingKeys: String, CodingKey {
                case video = "webapp.video-detail"
                case user = "webapp.user-detail"
            }
        }
        struct VideoDetail: Decodable { let itemInfo: ItemInfo? }
        struct ItemInfo: Decodable { let itemStruct: Item }
        struct Item: Decodable {
            let desc: String?
            let author: Author?
            let video: Video?
        }
        struct Author: Decodable { let nickname: String? }
        struct Video: Decodable { let cover: String? }
        struct UserDetail: Decodable { let userInfo: UserInfo? }
        struct UserInfo: Decodable { let user: User }
        struct User: Decodable {
            let nickname: String?
            let signature: String?
            let avatarLarger: String?
        }
    }
}
