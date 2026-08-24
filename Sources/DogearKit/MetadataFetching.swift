import Foundation

public struct FetchedMetadata: Equatable, Sendable {
    public var title: String?
    public var author: String?
    public var description: String?
    public var thumbnailURL: URL?
    public var source: Source

    public init(title: String? = nil, author: String? = nil, description: String? = nil,
                thumbnailURL: URL? = nil, source: Source = .web) {
        self.title = title
        self.author = author
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.source = source
    }

    func bounded() -> FetchedMetadata {
        FetchedMetadata(
            title: Self.clean(title, limit: 512),
            author: Self.clean(author, limit: 256),
            description: Self.clean(description, limit: 2_048),
            thumbnailURL: thumbnailURL,
            source: source
        )
    }

    private static let unsafeText = CharacterSet.controlCharacters.union(
        CharacterSet(charactersIn: "\u{061C}\u{200E}\u{200F}\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}")
    )

    private static func clean(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let cleaned = value.components(separatedBy: unsafeText)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(limit))
    }
}

public protocol MetadataFetcher: Sendable {
    // Whether this fetcher's metadata comes from the page body itself (true, the
    // default) or from its own separate endpoint (false, e.g. TikTok's oEmbed).
    static var parsesPageBody: Bool { get }

    func fetch(_ url: URL, client: HTTPClient) async throws -> FetchedMetadata
    func parse(body: Data, url: URL) throws -> FetchedMetadata
}

public extension MetadataFetcher {
    static var parsesPageBody: Bool { true }

    func parse(body: Data, url: URL) throws -> FetchedMetadata {
        throw HTTPClientError.noResponse
    }
}
