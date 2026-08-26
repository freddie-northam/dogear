import Foundation

/// Writes the library as a Netscape bookmark file, the format every browser
/// imports. Dogear can already read one; this is the door back out, so a
/// library is never trapped in the app.
public enum BookmarksHTML {
    /// The whole library, one section per folder in the user's own order,
    /// with the archive last. Notes travel as `DD` lines, which browsers keep
    /// as the bookmark description.
    public static func export(_ library: Library) -> String {
        var lines = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<!-- This file was written by Dogear. -->",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Bookmarks</TITLE>",
            "<H1>Bookmarks</H1>",
            "<DL><p>",
        ]
        for section in library.exportSections {
            lines.append(contentsOf: self.section(named: section.name, items: section.bookmarks))
        }
        lines.append("</DL><p>")
        return lines.joined(separator: "\n") + "\n"
    }

    static func section(named name: String, items: [Bookmark]) -> [String] {
        var lines = ["    <DT><H3>\(escaped(name))</H3>", "    <DL><p>"]
        for bookmark in items {
            let addDate = String(Int(bookmark.createdAt.timeIntervalSince1970))
            lines.append("        <DT><A HREF=\"\(escaped(bookmark.url))\" ADD_DATE=\"\(addDate)\">"
                + "\(escaped(bookmark.title))</A>")
            if let note = bookmark.note, !note.isEmpty {
                lines.append("        <DD>\(escaped(note.singleLine))")
            }
        }
        lines.append("    </DL><p>")
        return lines
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
