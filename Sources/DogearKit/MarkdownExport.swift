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
        library.exportSections
            .map { "## \($0.name)\n\n\(Bookmark.markdownList($0.bookmarks))" }
            .joined(separator: "\n\n")
    }
}
