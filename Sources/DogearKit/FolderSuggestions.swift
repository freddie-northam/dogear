import Foundation

/// A folder Dogear does not have yet, and what making it would file.
public struct FolderSuggestion: Equatable, Sendable {
    /// The folder to create.
    public let name: String
    /// How many waiting bookmarks would move into it straight away.
    public let count: Int
    /// A few of those bookmarks, so the count is something you can check
    /// rather than something you have to trust.
    public let examples: [String]

    public init(name: String, count: Int, examples: [String]) {
        self.name = name
        self.count = count
        self.examples = examples
    }
}

/// Finds folders worth making, by asking what the categorizer already knows.
///
/// A rule like "a github.com link belongs in Developer" does nothing while no
/// such folder exists, and says nothing either: the link waits in Unsorted and
/// the reason never reaches the user. This turns that silence into an offer
/// with a number on it.
public enum FolderSuggestions {
    /// Folders the categorizer can file into, whether or not a library has them.
    /// Read from the categorizer itself, so a rule added there shows up here
    /// without anyone remembering to update a second list.
    static var knownFolders: [String] {
        var seen: [String] = []
        for folder in KeywordCategorizer.domainHints.map(\.folder)
            + KeywordCategorizer.keywords.keys
        where !seen.contains(folder) {
            seen.append(folder)
        }
        return seen.sorted()
    }

    /// Suggests folders for the bookmarks waiting in Unsorted.
    ///
    /// Each candidate is scored by running the real categorizer with that
    /// folder added, so a suggestion cannot promise a placement the app would
    /// not actually make. Suggestions come back with the largest first, and a
    /// candidate that would file nothing is left out.
    public static func suggest(
        for bookmarks: [Bookmark],
        folders: [String],
        categorizer: Categorizer = KeywordCategorizer(),
        exampleLimit: Int = 3
    ) async -> [FolderSuggestion] {
        let waiting = bookmarks.filter {
            $0.folder == Library.unsorted && !$0.isDone && !$0.manuallyFiled
        }
        guard !waiting.isEmpty else { return [] }

        let candidates = knownFolders.filter { !folders.contains($0) }
        guard !candidates.isEmpty else { return [] }

        // Every candidate is offered at once, and each bookmark goes to the
        // one folder it fits best. Scoring the candidates separately counted
        // a link about a typescript agent under both Developer and AI, so the
        // numbers could add up to more than the folder holds, and it cost one
        // pass over the library per candidate instead of one in total.
        var matched: [String: [Bookmark]] = [:]
        let offered = folders.filter { $0 != Library.unsorted } + candidates
        for bookmark in waiting {
            guard let url = URL(string: bookmark.url) else { continue }
            let metadata = FetchedMetadata(
                title: bookmark.title, author: bookmark.author,
                description: bookmark.note, source: bookmark.source
            )
            guard let guess = await categorizer.categorize(metadata, url: url, folders: offered),
                  candidates.contains(guess) else { continue }
            matched[guess, default: []].append(bookmark)
        }

        var suggestions: [FolderSuggestion] = []
        for candidate in candidates {
            guard let found = matched[candidate], !found.isEmpty else { continue }
            suggestions.append(FolderSuggestion(
                name: candidate,
                count: found.count,
                examples: found.prefix(exampleLimit).map(\.title)
            ))
        }
        // Largest first, then by name, so the order never depends on how a
        // Dictionary happened to iterate.
        return suggestions.sorted {
            $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count
        }
    }
}
