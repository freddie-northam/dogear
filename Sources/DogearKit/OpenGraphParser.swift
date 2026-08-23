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
        let metaPattern = #/(?i)<meta\s+(?:[^>"']|"[^"]*"|'[^']*')*>/#
        let attrPattern = #/(?i)(property|name|content)\s*=\s*(?:"([^"]*)"|'([^']*)')/#

        for match in html.matches(of: metaPattern) {
            let tag = String(match.output)
            var propertyAttr: String?
            var nameAttr: String?
            var content: String?
            for attr in tag.matches(of: attrPattern) {
                let name = String(attr.output.1).lowercased()
                guard let raw = attr.output.2 ?? attr.output.3 else { continue }
                let value = String(raw)
                switch name {
                case "content": if content == nil { content = value }
                case "property": if propertyAttr == nil { propertyAttr = value }
                default: if nameAttr == nil { nameAttr = value }
                }
            }
            let property = propertyAttr ?? nameAttr
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
        // ponytail: sites like LinkedIn double-encode og titles ("&amp;#39;"),
        // so the decode runs a second pass when the first leaves entities
        // behind. The cost: a title that literally discusses "&lt;" decodes
        // one level too far. Sloppy double-encoding is far more common.
        let once = decodeEntitiesOnce(text)
        guard once.contains("&"), once.firstMatch(of: #/&(#x?[0-9a-fA-F]+|[a-z]+);/#) != nil else {
            return once
        }
        return decodeEntitiesOnce(once)
    }

    private static func decodeEntitiesOnce(_ text: String) -> String {
        var result = text
        // &amp; is decoded LAST: decoding it first turns "&amp;lt;" (the literal text
        // "&lt;") into "<" and "&amp;#8217;" into "'" on a following pass.
        let entities = [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&apos;", "'"), ("&nbsp;", " "),
        ]
        for (entity, character) in entities {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        // Numeric entities, decimal and hex. An invalid scalar (a surrogate,
        // or out of range) stays as literal text.
        result = result.replacing(#/&#([xX][0-9a-fA-F]+|[0-9]+);/#) { match in
            let body = match.output.1
            let isHex = body.hasPrefix("x") || body.hasPrefix("X")
            let value = isHex ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            guard let value, let scalar = Unicode.Scalar(value) else {
                return String(match.output.0)
            }
            return String(Character(scalar))
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}
