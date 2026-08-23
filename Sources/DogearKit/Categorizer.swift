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
        "Shows": ["episode", "season", "series", "binge", "watch", "streaming", "stream",
                  "netflix", "hbo", "trailer", "anime", "k-drama", "documentary", "film",
                  "movie", "tv", "finale"],
        "Articles": ["article", "essay", "op-ed", "opinion", "explained", "explainer", "deep dive",
                     "long read", "blog post", "writeup", "analysis", "research", "a field guide",
                     "history of", "notes on", "writing"],
    ]

    static let domainHints: [String: String] = [
        "netflix.com": "Shows", "primevideo.com": "Shows", "hbomax.com": "Shows",
        "youtube.com": "Shows", "imdb.com": "Shows",
        "maps.google.com": "Restaurants", "maps.apple.com": "Restaurants",
        "substack.com": "Articles", "medium.com": "Articles",
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

        var best: (folder: String, score: Int)?
        for folder in folders where folder != Library.unsorted {
            var score = Self.keywords[folder, default: []].filter { haystack.contains($0) }.count
            if haystack.contains(folder.lowercased()) { score += 1 }
            if score > (best?.score ?? 0) { best = (folder, score) }
        }
        return best?.folder
    }
}
