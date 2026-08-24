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
