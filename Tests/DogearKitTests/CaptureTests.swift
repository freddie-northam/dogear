import Foundation
import Testing
@testable import DogearKit

private func urls(_ strings: [String]) -> [URL] { strings.map { URL(string: $0)! } }

private func html(_ strings: [String]) -> String {
    strings.map { "<a href=\"\($0)\">\($0)</a>" }.joined(separator: "\n")
}

@MainActor
private final class EnrichmentGate {
    private(set) var started: [UUID] = []
    private(set) var inFlight = 0
    private(set) var peak = 0
    private var parked: [CheckedContinuation<Void, Never>] = []
    let arrivals: AsyncStream<Void>
    private let arrive: AsyncStream<Void>.Continuation

    init() { (arrivals, arrive) = AsyncStream.makeStream() }

    func enter(_ id: UUID) async {
        started.append(id)
        inFlight += 1
        peak = max(peak, inFlight)
        arrive.yield()
        await withCheckedContinuation { parked.append($0) }
        inFlight -= 1
    }

    func releaseOne() {
        if !parked.isEmpty { parked.removeFirst().resume() }
    }
}

@MainActor
private func settle() async {
    for _ in 0..<200 { await Task.yield() }
}

@MainActor @Test func textBumpsASavedLinkAndEnrichesOnlyTheNewOne() async throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    _ = store.add(urls: urls(["https://a.com/old", "https://a.com/other"]), duplicates: .resave)
    store.markDone(id: store.library.bookmarks[0].id)
    var enriched: [UUID] = []
    let capture = Capture(store: store) { enriched.append($0) }

    let outcome = capture.save(.text("see https://a.com/new and https://a.com/old"))
    await outcome.enrichment?.value

    #expect(outcome.new.map(\.url) == ["https://a.com/new"])
    #expect(outcome.alreadySaved == 1)
    #expect(store.library.bookmarks.map(\.url) == ["https://a.com/new", "https://a.com/old", "https://a.com/other"])
    #expect(store.archive().isEmpty)
    #expect(enriched == outcome.new.map(\.id))
}

@MainActor @Test(arguments: ["drop", "notes", "file"])
func everyImportLeavesSavedLinksAlone(kind: String) async throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    _ = store.add(urls: urls(["https://a.com/1", "https://a.com/2"]), duplicates: .resave)
    store.markDone(id: store.library.bookmarks[1].id)
    let before = store.library.bookmarks
    var changes = 0
    store.onChange = { changes += 1 }
    var enriched = 0
    let capture = Capture(store: store) { _ in enriched += 1 }
    let links = ["https://a.com/2", "https://a.com/1"]
    let source: Capture.Source = switch kind {
    case "drop": .drop(urls(links))
    case "notes": .notes(html: html(links), incremental: false, unreadFolders: 0)
    default: .bookmarksFile(html: html(links))
    }

    let outcome = capture.save(source)

    #expect(outcome.new.isEmpty)
    #expect(outcome.alreadySaved == 2)
    #expect(outcome.enrichment == nil)
    #expect(store.library.bookmarks == before)
    #expect(changes == 0)
    #expect(enriched == 0)
}

@MainActor @Test func enrichmentRunsAtMostFourAtOnce() async throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let gate = EnrichmentGate()
    let capture = Capture(store: store) { await gate.enter($0) }
    let links = (0..<10).map { "https://a.com/\($0)" }

    let outcome = capture.save(.text(links.joined(separator: " ")))
    var arrivals = gate.arrivals.makeAsyncIterator()
    for arrived in 1...10 {
        await arrivals.next()
        await settle()
        #expect(gate.inFlight <= 4)
        if arrived >= 4 { gate.releaseOne() }
    }
    for _ in 0..<4 { gate.releaseOne() }
    await outcome.enrichment?.value

    #expect(gate.peak == 4)
    #expect(gate.started.sorted { $0.uuidString < $1.uuidString }
        == outcome.new.map(\.id).sorted { $0.uuidString < $1.uuidString })
}

struct SummaryCase: Sendable, CustomTestStringConvertible {
    let kind: String
    var incremental = false
    var unread = 0
    let saved: Int
    let new: Int
    let expected: String?
    var testDescription: String { "\(kind) saved \(saved) new \(new) -> \(expected ?? "nil")" }
}

@MainActor @Test(arguments: [
    SummaryCase(kind: "text", saved: 0, new: 0, expected: "That is not a web link. Dogear saves http and https links."),
    SummaryCase(kind: "text", saved: 0, new: 1, expected: nil),
    SummaryCase(kind: "text", saved: 1, new: 0, expected: "Already saved. It moved to the top of the library."),
    SummaryCase(kind: "text", saved: 2, new: 0, expected: "All 2 were already saved."),
    SummaryCase(kind: "text", saved: 1, new: 2, expected: "Saved 3 links."),
    SummaryCase(kind: "drop", saved: 1, new: 1, expected: nil),
    SummaryCase(kind: "notes", saved: 0, new: 0, expected: "No links found in your notes."),
    SummaryCase(kind: "notes", incremental: true, unread: 2, saved: 0, new: 0,
                expected: "No new links since your last import. Dogear could not read 2 folders."),
    SummaryCase(kind: "notes", saved: 1, new: 0, expected: "This link was already saved."),
    SummaryCase(kind: "notes", unread: 1, saved: 2, new: 0,
                expected: "All 2 links were already saved. Dogear could not read 1 folder."),
    SummaryCase(kind: "notes", saved: 0, new: 1, expected: "Imported 1 link."),
    SummaryCase(kind: "notes", saved: 1, new: 2, expected: "Imported 2 links. 1 was already saved."),
    SummaryCase(kind: "file", saved: 0, new: 0, expected: "No links found in that file."),
    SummaryCase(kind: "file", saved: 2, new: 3, expected: "Imported 3 links. 2 were already saved."),
    SummaryCase(kind: "file", saved: 3, new: 0, expected: "All 3 links were already saved."),
])
func summaryTellsTheUserWhatHappened(_ c: SummaryCase) async throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    let saved = (0..<c.saved).map { "https://saved.com/\($0)" }
    _ = store.add(urls: urls(saved), duplicates: .resave)
    let links = saved + (0..<c.new).map { "https://new.com/\($0)" }
    let source: Capture.Source = switch c.kind {
    case "text": .text(links.isEmpty ? "no link here" : links.joined(separator: " "))
    case "drop": .drop(urls(links))
    case "notes": .notes(html: html(links), incremental: c.incremental, unreadFolders: c.unread)
    default: .bookmarksFile(html: html(links))
    }
    let outcome = Capture(store: store) { _ in }.save(source)
    #expect(outcome.found == c.saved + c.new)
    #expect(outcome.summary == c.expected)
}

@MainActor @Test func reimportingAnExportChangesNothingOnDisk() async throws {
    let temp = TempDirectory()
    let store = try BookmarkStore(directory: temp.url)
    _ = store.add(urls: urls((0..<12).map { "https://example.com/item/\($0)" }), duplicates: .resave)
    for (index, bookmark) in store.library.bookmarks.enumerated() {
        if index % 3 == 0 { store.markDone(id: bookmark.id) }
        if index % 4 == 0 { store.toggleFavorite(id: bookmark.id) }
        if index % 5 == 0 { store.refile(id: bookmark.id, to: "Articles") }
    }
    let exported = temp.url.appendingPathComponent("Dogear.html")
    try BookmarksHTML.export(store.library).write(to: exported, atomically: true, encoding: .utf8)
    let libraryFile = temp.url.appendingPathComponent("library.json")
    let bytesBefore = try Data(contentsOf: libraryFile)
    let before = store.library

    let outcome = Capture(store: store) { _ in }
        .save(.bookmarksFile(html: try String(contentsOf: exported, encoding: .utf8)))

    #expect(outcome.new.isEmpty)
    #expect(outcome.alreadySaved == 12)
    #expect(store.library == before)
    #expect(store.archive().count == 4)
    #expect(try Data(contentsOf: libraryFile) == bytesBefore)
    #expect(try BookmarkStore(directory: temp.url).library == before)
}
