import Foundation

/// Writes the library as a Netscape bookmark file, which every browser imports.
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

    /// The http(s) link of every bookmark in a bookmark file, in file order.
    /// It reads only `HREF` values, so a title or a note that looks like a link never becomes a bookmark.
    public static func links(in html: String) -> [URL] {
        html.matches(of: #/(?i)\shref\s*=\s*(?:"([^"]*)"|'([^']*)')/#)
            .compactMap { match in (match.1 ?? match.2).flatMap { URL(string: unescaped(String($0))) } }
            .filter(URLCleaner.isCapturable)
    }

    static func unescaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
