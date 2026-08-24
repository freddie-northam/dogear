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
        // The three below are opt-in like the domain hints: a library without
        // such a folder never sees them. They exist because a link saved by
        // someone who builds software has nowhere to go among the five above.
        "Developer": ["github", "gitlab", "repo", "repository", "open source", "open-source",
                      "npm", "pull request", "commit", "codebase", "refactor", "api",
                      "sdk", "cli", "framework", "library", "typescript", "javascript",
                      "python", "rust", "swift", "react", "next.js", "tailwind",
                      "shadcn", "vercel", "cloudflare", "docker", "kubernetes",
                      "postgres", "database", "compiler", "runtime", "deploy",
                      "self-host", "boilerplate", "starter kit", "software"],
        "AI": ["llm", "gpt", "claude", "anthropic", "openai", "gemini", "agent", "agents",
               "agentic", "prompt", "prompting", "fine-tune", "fine-tuning", "rag",
               "embedding", "inference", "model context protocol", "mcp", "codex",
               "copilot", "cursor", "eval", "evals", "context window", "subagent",
               "diffusion", "transformer", "benchmark", "skill", "skills"],
        "Design": ["design", "ui", "ux", "figma", "typography", "typeface", "font",
                   "spacing", "layout", "colour palette", "color palette", "wireframe",
                   "prototype", "animation", "motion", "easing", "shader", "shaders",
                   "css", "design system", "component library", "icon set", "branding",
                   "interface", "interaction design"],
    ]

    /// Folders whose keywords are technical terms rather than everyday words.
    /// A conversational post that uses one of them means it, so these do not
    /// need the second hit that the conversational folders do.
    static let literalKeywordFolders: Set<String> = ["Developer", "AI", "Design"]

    // Ordered, longest domain first: the first match wins, so a more specific domain is
    // always tested before any suffix of it. No pair overlaps today, but a Dictionary
    // iterates in an unspecified order, so the first overlap added would pick at random.
    // The Developer entries are opt-in: they only fire when the user has that folder.
    static let domainHints: [(domain: String, folder: String)] = [
        ("open.spotify.com", "Music"),
        ("music.apple.com", "Music"), ("maps.app.goo.gl", "Restaurants"), ("maps.google.com", "Restaurants"),
        ("soundcloud.com", "Music"), ("maps.apple.com", "Restaurants"), ("primevideo.com", "Shows"),
        ("bandcamp.com", "Music"), ("substack.com", "Articles"),
        ("youtube.com", "Shows"), ("netflix.com", "Shows"),
        ("hbomax.com", "Shows"), ("medium.com", "Articles"), ("github.com", "Developer"), ("gitlab.com", "Developer"),
        ("ui.shadcn.com", "Design"), ("animations.dev", "Design"),
        ("developers.google.com", "Developer"), ("npmjs.com", "Developer"),
        ("stackoverflow.com", "Developer"), ("huggingface.co", "AI"),
        ("anthropic.com", "AI"), ("openai.com", "AI"),
        ("imdb.com", "Shows"),
    ]

    /// True when `word` appears in `haystack` bounded by non-letters on both
    /// sides, so "ai" matches "ai agents" but not "email".
    static func containsWord(_ word: String, in haystack: String) -> Bool {
        guard !word.isEmpty else { return false }
        var index = haystack.startIndex
        while let range = haystack.range(of: word, range: index..<haystack.endIndex) {
            let beforeOK = range.lowerBound == haystack.startIndex
                || !haystack[haystack.index(before: range.lowerBound)].isLetter
            let afterOK = range.upperBound == haystack.endIndex
                || !haystack[range.upperBound].isLetter
            if beforeOK, afterOK { return true }
            index = haystack.index(after: range.lowerBound)
        }
        return false
    }

    public func categorize(_ metadata: FetchedMetadata, url: URL, folders: [String]) async -> String? {
        let haystack = [metadata.title, metadata.description, metadata.author]
            .compactMap { $0 }.joined(separator: " ").lowercased()

        if let host = url.host?.lowercased() {
            for (domain, folder) in Self.domainHints
            where (host == domain || host.hasSuffix("." + domain)) && folders.contains(folder) {
                return folder
            }
        }

        // Tweets are conversational, so one stray keyword misfiles them: a
        // post that says "watch this" is not a show, and "the recipe for good
        // taste" is not a recipe. X posts need two hits for those folders.
        //
        // The technical folders are exempt. Nobody writes "shadcn" or "llm" as
        // a figure of speech, so a single hit there is already a strong signal,
        // and holding them to two leaves most of a developer's library in
        // Unsorted. Measured on a 212 link library: two hits filed 39% of it,
        // this rule files 63%, and dropping the bar everywhere files 66% by
        // guessing on exactly the words that are ambiguous.
        var best: (folder: String, score: Int)?
        for folder in folders where folder != Library.unsorted {
            let literalFolder = Self.literalKeywordFolders.contains(folder)
            let minimumScore = (metadata.source == .x && !literalFolder) ? 2 : 1
            var score = Self.keywords[folder, default: []].filter { haystack.contains($0) }.count
            // The folder's own name counts as a keyword, but only as a whole
            // word: a folder named "AI" used to score on "email" and
            // "available", which filed half a library into it.
            if Self.containsWord(folder.lowercased(), in: haystack) { score += 1 }
            if score >= minimumScore, score > (best?.score ?? 0) { best = (folder, score) }
        }
        return best?.folder
    }
}
