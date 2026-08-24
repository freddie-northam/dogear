import Foundation

public enum NotesImportPlanning {
    /// Links not already in the library, by canonical URL, in input order.
    public static func freshURLs(_ found: [URL], existing: Set<String>) -> [URL] {
        found.filter { !existing.contains(URLCleaner.canonicalString($0)) }
    }
}
