import Foundation

public struct FetchedMetadata: Equatable, Sendable {
    /// The longest title or author Dogear keeps. A page controls both, and
    /// nothing else bounds them: the fetch cap covers the whole document, so
    /// a megabyte of title arrives intact and then sits in every list row,
    /// every search sweep and the library file. Two hundred characters is
    /// longer than any title a person reads.
    ///
    /// The cap lives here because every fetcher returns one of these, so one
    /// guard covers the oEmbed endpoints and the page parser alike.
    public static let fieldLimit = 200

    public var title: String?
    public var author: String?
    public var description: String?
    public var thumbnailURL: URL?
    public var source: Source

    public init(title: String? = nil, author: String? = nil, description: String? = nil,
                thumbnailURL: URL? = nil, source: Source = .web) {
        self.title = title.map(Self.capped)
        self.author = author.map(Self.capped)
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.source = source
    }

    private static func capped(_ text: String) -> String {
        guard text.count > fieldLimit else { return text }
        return String(text.prefix(fieldLimit)) + "\u{2026}"
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
