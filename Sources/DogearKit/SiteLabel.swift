import Foundation

/// The name of the site a link is on, for By Site groups and for rows: `gist.github.com` and `github.com` are both `github.com`.
public enum SiteLabel {
    static let aliases = ["twitter.com": "x.com", "youtu.be": "youtube.com"]
    // ponytail: a short list, not the Public Suffix List. A domain like `city.kawasaki.jp` keeps one label too few.
    /// Second-level labels under a country code, as in `bbc.co.uk`.
    static let countrySecondLevels: Set = ["co", "com", "org", "net", "ac", "gov", "edu"]

    public static func of(_ urlString: String) -> String {
        guard let host = URL(string: urlString)?.host?.lowercased(), !host.isEmpty else { return "" }
        let labels = host.split(separator: ".")
        if labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) { return host }
        let underCountry = labels.count >= 3 && labels[labels.count - 1].count == 2
            && countrySecondLevels.contains(String(labels[labels.count - 2]))
        let site = labels.suffix(underCountry ? 3 : 2).joined(separator: ".")
        return aliases[site] ?? site
    }
}
