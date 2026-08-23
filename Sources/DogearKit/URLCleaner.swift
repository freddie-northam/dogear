import Foundation

public enum URLCleaner {
    static let trackingPrefixes = ["utm_"]
    static let trackingNames: Set<String> = ["fbclid", "gclid", "igsh", "si", "s", "t", "ref_src", "ref_url"]

    public static func firstHTTPURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []
        for match in matches {
            guard let url = match.url, let scheme = url.scheme?.lowercased() else { continue }
            if scheme == "http" || scheme == "https" { return url }
        }
        return nil
    }

    public static func canonicalString(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        parts.host = parts.host?.lowercased()
        parts.fragment = nil
        if let items = parts.queryItems {
            let kept = items.filter { item in
                let name = item.name.lowercased()
                if trackingNames.contains(name) { return false }
                return !trackingPrefixes.contains { name.hasPrefix($0) }
            }
            parts.queryItems = kept.isEmpty ? nil : kept
        }
        var result = parts.string ?? url.absoluteString
        if result.hasSuffix("/") { result.removeLast() }
        return result
    }
}
