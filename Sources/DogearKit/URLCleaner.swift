import Foundation

public enum URLCleaner {
    static let trackingPrefixes = ["utm_"]
    static let trackingNames: Set<String> = ["fbclid", "gclid", "igsh", "si"]
    static let xHostTrackingNames: Set<String> = ["s", "t", "ref_src", "ref_url"]
    static let xHosts: Set<String> = ["x.com", "twitter.com"]

    // One shared detector: creating an NSDataDetector compiles a regex, which is
    // too costly to repeat on every keystroke. Matching itself is thread-safe.
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    public static func firstHTTPURL(in text: String) -> URL? {
        allHTTPURLs(in: text).first
    }

    /// Every http(s) link in the text, in order of appearance. Other schemes are dropped.
    public static func allHTTPURLs(in text: String) -> [URL] {
        let range = NSRange(text.startIndex..., in: text)
        let matches = linkDetector?.matches(in: text, options: [], range: range) ?? []
        return matches.compactMap { match in
            guard let url = match.url, let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return nil }
            // A bare "item.id" in a code snippet looks like an Indonesian domain to
            // the detector. Skip it when the text carried no scheme and no path.
            if isCodeIdentifier(matchedText: String(text[Range(match.range, in: text)!]), url: url) {
                return nil
            }
            // The detector can run past HTML that follows a link with no
            // whitespace, like "example.com/a</div>", and it percent-encodes
            // the markup. Cut the URL at the first markup character, in
            // literal or percent-encoded form.
            return trimmedAtMarkup(url)
        }
    }

    /// A scheme-less bare host of one short lowercase label plus a two-letter
    /// TLD, with no path or query, is a code identifier like "result.id" far
    /// more often than a saved website. Real bare domains ("booking.com",
    /// "impeccable.style") have longer TLDs or labels and pass through.
    static func isCodeIdentifier(matchedText: String, url: URL) -> Bool {
        guard !matchedText.contains("://"),
              url.path.isEmpty || url.path == "/", url.query == nil,
              let host = url.host?.lowercased() else { return false }
        let parts = host.split(separator: ".")
        guard parts.count == 2, parts[1].count == 2,
              (1...8).contains(parts[0].count),
              parts[0].allSatisfy({ $0.isLetter && $0.isLowercase }) else { return false }
        return true
    }

    static let markupMarkers = ["<", ">", "\"", "%3C", "%3E", "%22", "%3c", "%3e"]

    static func trimmedAtMarkup(_ url: URL) -> URL? {
        let text = url.absoluteString
        var cut = text.endIndex
        for marker in markupMarkers {
            if let found = text.range(of: marker)?.lowerBound, found < cut { cut = found }
        }
        guard cut != text.endIndex else { return url }
        return URL(string: String(text[..<cut]))
    }

    /// Extraction for HTML bodies, like Apple Notes exports. HTML escapes "&"
    /// as "&amp;" inside href values, and the detector would keep the escaped
    /// form and corrupt the query string. Unescape it, then reuse the text path.
    /// ponytail: only &amp; is unescaped; other entities rarely appear inside URLs.
    public static func allHTTPURLs(inHTML html: String) -> [URL] {
        allHTTPURLs(in: html.replacingOccurrences(of: "&amp;", with: "&"))
    }

    public static func canonicalString(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        parts.user = nil
        parts.password = nil
        // The same tweet arrives as twitter.com or x.com depending on where
        // the link was copied; one host keeps them one bookmark.
        if let host = parts.host,
           host == "twitter.com" || host == "www.twitter.com" || host == "mobile.twitter.com" {
            parts.host = "x.com"
        }
        parts.fragment = nil
        // Strip the trailing slash from the path only: doing it on the serialized
        // string truncates a query value that legitimately ends in "/". Work on the
        // percent-encoded path, because reading `path` decodes %2F into a real
        // separator and would rewrite the path to a different resource.
        if parts.percentEncodedPath.hasSuffix("/") { parts.percentEncodedPath.removeLast() }
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

    public static func displayHost(for url: URL) -> String {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return "Other" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public static func siteName(for url: URL) -> String {
        let host = displayHost(for: url)
        if host == "github.com" || host.hasSuffix(".github.com") { return "GitHub" }
        if host == "x.com" || host.hasSuffix(".x.com")
            || host == "twitter.com" || host.hasSuffix(".twitter.com") { return "X" }
        if host == "tiktok.com" || host.hasSuffix(".tiktok.com") { return "TikTok" }
        return host
    }

    /// The one rule for what may become or remain a bookmark URL.
    public static func isCapturable(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return (scheme == "http" || scheme == "https")
            && url.host?.isEmpty == false
            && url.user == nil
            && url.password == nil
    }
}
