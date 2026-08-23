import Foundation

public protocol Categorizer: Sendable {
    func categorize(_ metadata: FetchedMetadata, url: URL, folders: [String]) async -> String?
}

public struct KeywordCategorizer: Categorizer {
    public init() {}

    // Keyword tables for the default folders. Scoring: the folder with the
    // most keyword hits wins; ties go to the first folder in the user's list.
    static let keywords: [String: [String]] = [
        "Recipes": ["recipe", "ingredient", "bake", "baking", "cook", "cooking", "meal prep",
                    "air fryer", "one-pan", "sourdough", "dessert", "homemade", "from scratch", "vegan"],
        "Restaurants": ["restaurant", "eat in", "where to eat", "brunch", "omakase", "taqueria",
                        "tasting menu", "michelin", "reservation", "izakaya", "cafe", "bakery",
                        "steakhouse", "pizzeria", "street food", "food tour", "bar and grill",
                        "spots in", "places near", "worth the trip", "dining"],
        "Music": ["song", "album", "playlist", "track", "listen", "remix", "setlist",
                  "vinyl", "mixtape", "new single"],
        "Shows": ["episode", "season", "series", "binge", "watch", "streaming", "stream",
                  "netflix", "hbo", "trailer", "anime", "k-drama", "documentary", "film",
                  "movie", "tv", "finale"],
        "Articles": ["article", "essay", "op-ed", "opinion", "explained", "explainer", "deep dive",
                     "long read", "blog post", "writeup", "analysis", "research", "a field guide",
                     "history of", "notes on", "writing"],
    ]

    // Ordered, longest domain first: the first match wins, so a more specific domain is
    // always tested before any suffix of it. No pair overlaps today, but a Dictionary
    // iterates in an unspecified order, so the first overlap added would pick at random.
    // The Code entries are opt-in: they only fire when the user has a folder named Code.
    static let domainHints: [(domain: String, folder: String)] = [
        ("open.spotify.com", "Music"),
        ("music.apple.com", "Music"), ("maps.app.goo.gl", "Restaurants"), ("maps.google.com", "Restaurants"),
        ("soundcloud.com", "Music"), ("maps.apple.com", "Restaurants"), ("primevideo.com", "Shows"),
        ("bandcamp.com", "Music"), ("substack.com", "Articles"),
        ("youtube.com", "Shows"), ("netflix.com", "Shows"),
        ("hbomax.com", "Shows"), ("medium.com", "Articles"), ("github.com", "Code"), ("gitlab.com", "Code"),
        ("imdb.com", "Shows"),
    ]

    public func categorize(_ metadata: FetchedMetadata, url: URL, folders: [String]) async -> String? {
        let haystack = [metadata.title, metadata.description, metadata.author]
            .compactMap { $0 }.joined(separator: " ").lowercased()

        if let host = url.host?.lowercased() {
            for (domain, folder) in Self.domainHints
            where (host == domain || host.hasSuffix("." + domain)) && folders.contains(folder) {
                return folder
            }
        }

        // Tweets are conversational, so one stray keyword ("watch this",
        // a "recipe" metaphor) misfiles them: X posts need two hits.
        let minimumScore = metadata.source == .x ? 2 : 1
        var best: (folder: String, score: Int)?
        for folder in folders where folder != Library.unsorted {
            var score = Self.keywords[folder, default: []].filter { haystack.contains($0) }.count
            // ponytail: substring folder-name match, word-boundary matching if short names misfile.
            if haystack.contains(folder.lowercased()) { score += 1 }
            if score >= minimumScore, score > (best?.score ?? 0) { best = (folder, score) }
        }
        return best?.folder
    }
}
