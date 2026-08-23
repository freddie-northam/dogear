import Foundation

public enum URLCleaner {
    static let trackingPrefixes = ["utm_"]
    static let trackingNames: Set<String> = ["fbclid", "gclid", "igsh", "si"]
    static let xHostTrackingNames: Set<String> = ["s", "t", "ref_src", "ref_url"]
    static let xHosts: Set<String> = ["x.com", "twitter.com"]

    public static func firstHTTPURL(in text: String) -> URL? {
        allHTTPURLs(in: text).first
    }

    /// Every http(s) link in the text, in order of appearance. Other schemes are dropped.
    public static func allHTTPURLs(in text: String) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []
        return matches.compactMap { match in
            guard let url = match.url, let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return nil }
            return url
        }
    }

    public static func canonicalString(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        parts.fragment = nil
        // Strip the trailing slash from the path only: doing it on the serialized
        // string truncates a query value that legitimately ends in "/".
        if parts.path.hasSuffix("/") { parts.path.removeLast() }
        let isXHost = xHosts.contains { host in
            parts.host == host || (parts.host?.hasSuffix("." + host) ?? false)
        }
        if let items = parts.queryItems {
            let kept = items.filter { item in
                let name = item.name.lowercased()
                if trackingNames.contains(name) { return false }
                if isXHost && xHostTrackingNames.contains(name) { return false }
                return !trackingPrefixes.contains { name.hasPrefix($0) }
            }
            parts.queryItems = kept.isEmpty ? nil : kept
        }
        return parts.string ?? url.absoluteString
    }
}
