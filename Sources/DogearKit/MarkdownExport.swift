import Foundation

/// Writes the library as a markdown list, one heading per folder. The
/// counterpart to `BookmarksHTML`: that one is for another app to read, this
/// one is for a person.
public enum MarkdownExport {
    /// One section per folder in the user's own order, empty folders skipped,
    /// the archive last. A folder whose bookmarks are all done contributes
    /// nothing here and its items appear under Archive, exactly as they do in
    /// the app.
    public static func export(_ library: Library) -> String {
        var sections: [String] = []
        for folder in library.folders {
            let items = library.bookmarks.filter { $0.folder == folder && !$0.isDone }
            guard !items.isEmpty else { continue }
            sections.append("## \(folder)\n\n\(Bookmark.markdownList(items))")
        }
        let archived = library.bookmarks.filter(\.isDone)
        if !archived.isEmpty {
            sections.append("## Archive\n\n\(Bookmark.markdownList(archived))")
        }
        return sections.joined(separator: "\n\n")
    }
}
