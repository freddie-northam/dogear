import Foundation

public struct OpenGraphData: Equatable, Sendable {
    public var title: String?
    public var description: String?
    public var imageURL: URL?
    public var siteName: String?
}

public enum OpenGraphParser {
    public static func parse(html: String) -> OpenGraphData {
        var properties: [String: String] = [:]
        // ponytail: regex over string scanning is enough here; fetched HTML is capped at 1 MB.
        // Tag and attribute names are case-insensitive in HTML; attribute values are not.
        let metaPattern = #/(?i)<meta\s+[^>]*>/#
        let attrPattern = #/(?i)(property|name|content)\s*=\s*(?:"([^"]*)"|'([^']*)')/#

        for match in html.matches(of: metaPattern) {
            let tag = String(match.output)
            var property: String?
            var content: String?
            for attr in tag.matches(of: attrPattern) {
                let name = String(attr.output.1).lowercased()
                guard let raw = attr.output.2 ?? attr.output.3 else { continue }
                let value = String(raw)
                if name == "content" { content = value } else { property = value }
            }
            if let property, let content, property.hasPrefix("og:"), properties[property] == nil {
                properties[property] = decodeEntities(content)
            }
        }

        var title = properties["og:title"]
        if title == nil,
           let titleMatch = html.firstMatch(of: #/(?i)<title[^>]*>([^<]*)<\/title>/#) {
            let text = decodeEntities(String(titleMatch.output.1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            title = text.isEmpty ? nil : text
        }

        return OpenGraphData(
            title: title,
            description: properties["og:description"],
            imageURL: properties["og:image"].flatMap(URL.init(string:)),
            siteName: properties["og:site_name"]
        )
    }

    static func decodeEntities(_ text: String) -> String {
        var result = text
        // &amp; is decoded LAST: decoding it first turns "&amp;lt;" (the literal text
        // "&lt;") into "<" on the following pass.
        let entities = [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
            ("&amp;", "&"),
        ]
        for (entity, character) in entities {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}
