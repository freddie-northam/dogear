import Foundation

/// Per-folder cursors: a folder with no entry gets a full read; an entry means
/// read only notes modified after it. Keyed by the Notes folder id.
public struct NotesImportCursors: Codable, Equatable {
    public var lastImport: [String: Date]

    public init(lastImport: [String: Date] = [:]) {
        self.lastImport = lastImport
    }

    /// Seconds to subtract from "now" in the AppleScript, or nil for a full read.
    /// Includes a 60 second skew margin.
    public func secondsSince(folderID: String, now: Date) -> Int? {
        guard let last = lastImport[folderID] else { return nil }
        return Int(now.timeIntervalSince(last)) + 60
    }

    public mutating func record(folderID: String, at date: Date) {
        lastImport[folderID] = date
    }

    public mutating func prune(keeping folderIDs: Set<String>) {
        lastImport = lastImport.filter { folderIDs.contains($0.key) }
    }
}
