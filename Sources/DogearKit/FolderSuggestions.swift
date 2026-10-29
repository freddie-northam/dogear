import Foundation

/// A folder the library lacks, and the Unsorted links the keyword rules would file into it.
public struct FolderSuggestion: Equatable, Sendable {
    public let folder: String
    public let ids: [UUID]
}

public enum FolderSuggestions {
    /// A folder needs this many links before it is worth a suggestion.
    static let minimumLinks = 3

    /// Runs the keyword rules on each waiting Unsorted link, with every folder the rules know and the library lacks.
    /// A link goes to one folder at most. Largest first.
    public static func suggest(for library: Library) async -> [FolderSuggestion] {
        let existing = Set(library.folders.map { $0.lowercased() })
        let candidates = KeywordCategorizer.keywords.keys.filter { !existing.contains($0.lowercased()) }.sorted()
        var ids: [String: [UUID]] = [:]
        for bookmark in library.bookmarks where bookmark.folder == Library.unsorted && !bookmark.isDone {
            guard let url = URL(string: bookmark.url) else { continue }
            let metadata = FetchedMetadata(title: bookmark.title, author: bookmark.author,
                                           description: bookmark.note, source: bookmark.source)
            if let folder = await KeywordCategorizer().categorize(metadata, url: url, folders: library.folders + candidates),
               candidates.contains(folder) {
                ids[folder, default: []].append(bookmark.id)
            }
        }
        return ids.filter { $0.value.count >= minimumLinks }
            .map { FolderSuggestion(folder: $0.key, ids: $0.value) }
            .sorted { ($0.ids.count, $1.folder) > ($1.ids.count, $0.folder) }
    }
}

extension BookmarkStore {
    /// Creates each folder, then files the links that are still in Unsorted. Returns how many it filed.
    public func accept(_ suggestions: [FolderSuggestion]) -> Int {
        suggestions.forEach { addFolder($0.folder) }
        return autoFile(suggestions.flatMap { suggestion in suggestion.ids.map { (id: $0, folder: suggestion.folder) } })
    }
}
