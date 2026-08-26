import Foundation

/// A place on the map that a bookmark stands for. A restaurant or a hotel
/// from a note has no link, so Dogear resolves it once and keeps the result.
public struct Place: Codable, Equatable, Sendable {
    public var name: String
    public var address: String?
    public var latitude: Double
    public var longitude: Double

    public init(name: String, address: String?, latitude: Double, longitude: Double) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }

    /// An Apple Maps link for the resolved coordinates. The bookmark stores
    /// this as its URL, so dedupe, export, and the http(s) capture gate all
    /// keep working without a second code path for places.
    public var mapsURL: URL? {
        var parts = URLComponents(string: "https://maps.apple.com/")
        parts?.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: name),
        ]
        return parts?.url
    }
}

extension Place {
    /// Hosts whose pages are a map. A bookmark pointing at one of these opens
    /// in Maps even without a resolved place behind it, which is what a link
    /// copied out of Maps looks like.
    static let mapHosts: Set<String> = [
        "maps.apple.com", "maps.google.com", "maps.app.goo.gl", "goo.gl",
    ]

    static func isMapHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return mapHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

/// One line of pasted text, ready to look up.
public struct PlaceQuery: Equatable, Sendable {
    /// The place itself, as the user wrote it.
    public var name: String
    /// The city or area that narrows the search. Nil when the line had none.
    public var near: String?

    public init(name: String, near: String?) {
        self.name = name
        self.near = near
    }

    /// What goes to the map search: the name, then the area that narrows it.
    public var searchText: String {
        guard let near, !near.isEmpty else { return name }
        return "\(name), \(near)"
    }
}

public enum PlaceParser {
    /// Reads pasted note lines into place queries. A line is
    /// "City, Country ~ Name", the shape these notes already use. A line with
    /// no tilde is the name on its own. List markers and blank lines are
    /// dropped, so a block copied straight out of Notes needs no cleanup.
    public static func parse(_ text: String) -> [PlaceQuery] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let cleaned = stripListMarker(String(line))
            guard !cleaned.isEmpty else { return nil }
            // Split on the first tilde only: a name may contain another one.
            guard let separator = cleaned.firstIndex(of: "~") else {
                return PlaceQuery(name: cleaned, near: nil)
            }
            let near = cleaned[..<separator].trimmingCharacters(in: .whitespaces)
            let name = cleaned[cleaned.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return PlaceQuery(name: name, near: near.isEmpty ? nil : near)
        }
    }

    static func stripListMarker(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        // Bullets survive a copy out of Notes and would otherwise become part
        // of the search text.
        for marker in ["- ", "* ", "• ", "– "] where text.hasPrefix(marker) {
            text.removeFirst(marker.count)
            break
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

/// Turns a query into a place. One method, so a test can stand in for the map.
public protocol PlaceResolver: Sendable {
    func resolve(_ query: PlaceQuery) async -> Place?
}
