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
        let metaPattern = #/<meta\s+[^>]*>/#
        let attrPattern = #/(property|name|content)\s*=\s*"([^"]*)"/#

        for match in html.matches(of: metaPattern) {
            let tag = String(match.output)
            var property: String?
            var content: String?
            for attr in tag.matches(of: attrPattern) {
                let name = String(attr.output.1)
                let value = String(attr.output.2)
                if name == "content" { content = value } else { property = value }
            }
            if let property, let content, property.hasPrefix("og:"), properties[property] == nil {
                properties[property] = decodeEntities(content)
            }
        }

        var title = properties["og:title"]
        if title == nil,
           let titleMatch = html.firstMatch(of: #/<title[^>]*>([^<]*)<\/title>/#) {
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
        let entities = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&nbsp;", " "),
        ]
        for (entity, character) in entities {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }
}
