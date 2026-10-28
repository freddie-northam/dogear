import Foundation

public protocol Categorizer: Sendable {
    func categorize(_ metadata: FetchedMetadata, url: URL, folders: [String]) async -> String?
}

public struct KeywordCategorizer: Categorizer {
    public init() {}

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
        "Developer": ["github", "gitlab", "repo", "repository", "open source", "open-source", "npm",
                      "pull request", "codebase", "refactor", "api", "sdk", "cli", "framework",
                      "typescript", "javascript", "python", "rust", "swift", "react", "next.js",
                      "tailwind", "vercel", "cloudflare", "docker", "kubernetes", "postgres",
                      "database", "compiler", "runtime", "self-host", "boilerplate", "software"],
        "AI": ["llm", "llms", "gpt", "claude", "anthropic", "openai", "gemini", "agent", "agents",
               "agentic", "prompt", "prompting", "fine-tune", "fine-tuning", "rag", "embedding",
               "embeddings", "inference", "model context protocol", "mcp", "codex", "copilot",
               "eval", "evals", "context window", "subagent", "diffusion", "transformer"],
        "Design": ["design", "ui", "ux", "figma", "typography", "typeface", "font", "fonts",
                   "colour palette", "color palette", "wireframe", "prototype", "animation",
                   "motion", "easing", "shader", "shaders", "css", "design system", "shadcn",
                   "component library", "icon set", "branding", "interaction design"],
    ]

    /// Their keywords are technical terms: they match only as whole words, and one hit is enough, even on X.
    static let technicalFolders: Set<String> = ["Developer", "AI", "Design"]

    // Ordered, longest domain first: the first match wins, so a more specific domain is
    // always tested before any suffix of it. No pair overlaps today, but a Dictionary
    // iterates in an unspecified order, so the first overlap added would pick at random.
    static let domainHints: [(domain: String, folder: String)] = [
        ("stackoverflow.com", "Developer"), ("open.spotify.com", "Music"), ("music.apple.com", "Music"),
        ("maps.app.goo.gl", "Restaurants"), ("maps.google.com", "Restaurants"), ("soundcloud.com", "Music"),
        ("maps.apple.com", "Restaurants"), ("primevideo.com", "Shows"), ("huggingface.co", "AI"),
        ("anthropic.com", "AI"), ("bandcamp.com", "Music"), ("substack.com", "Articles"),
        ("youtube.com", "Shows"), ("netflix.com", "Shows"), ("hbomax.com", "Shows"),
        ("medium.com", "Articles"), ("github.com", "Developer"), ("gitlab.com", "Developer"),
        ("openai.com", "AI"), ("npmjs.com", "Developer"), ("imdb.com", "Shows"),
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
            let technical = Self.technicalFolders.contains(folder)
            let matches: (String) -> Bool = technical ? { Self.containsWord($0, in: haystack) } : { haystack.contains($0) }
            var score = Self.keywords[folder, default: []].filter(matches).count
            if Self.containsWord(folder.lowercased(), in: haystack) { score += 1 }
            let minimumScore = metadata.source == .x && !technical ? 2 : 1
            if score >= minimumScore, score > (best?.score ?? 0) { best = (folder, score) }
        }
        return best?.folder
    }

    /// True when `word` is in `text` with no letter right before or after it, so "ai" is not in "email".
    static func containsWord(_ word: String, in text: String) -> Bool {
        var start = text.startIndex
        while let range = text.range(of: word, range: start..<text.endIndex) {
            let before = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter
            let after = range.upperBound == text.endIndex || !text[range.upperBound].isLetter
            if before && after { return true }
            start = text.index(after: range.lowerBound)
        }
        return false
    }
}
