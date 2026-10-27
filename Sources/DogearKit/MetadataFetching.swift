import Foundation

public struct FetchedMetadata: Equatable, Sendable {
    public static let titleLimit = 512
    public static let authorLimit = 256
    public static let descriptionLimit = 2048

    public var title: String?
    public var author: String?
    public var description: String?
    public var thumbnailURL: URL?
    public var source: Source

    public init(title: String? = nil, author: String? = nil, description: String? = nil,
                thumbnailURL: URL? = nil, source: Source = .web) {
        self.title = Self.bounded(title, to: Self.titleLimit)
        self.author = Self.bounded(author, to: Self.authorLimit)
        self.description = Self.bounded(description, to: Self.descriptionLimit)
        self.thumbnailURL = thumbnailURL
        self.source = source
    }

    /// A page writes these fields, so they are untrusted. Direction controls can make a title read as something else.
    /// A control character becomes a space, so "Foo\nBar" keeps its word break.
    private static func bounded(_ text: String?, to limit: Int) -> String? {
        guard let text else { return nil }
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !scalar.properties.isBidiControl {
            scalars.append(scalar.properties.generalCategory == .control ? " " : scalar)
        }
        return String(String(scalars).trimmingCharacters(in: .whitespaces).prefix(limit))
    }
}

public protocol MetadataFetcher: Sendable {
    func fetch(_ url: URL, client: HTTPClient) async throws -> FetchedMetadata
    func parse(body: Data, url: URL) throws -> FetchedMetadata
}
