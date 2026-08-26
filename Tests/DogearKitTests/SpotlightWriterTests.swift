import CoreSpotlight
import Foundation
import Testing
@testable import DogearKit

/// Records what reached the system index, and lets a test hold a write open
/// so a second request arrives while the first is still running.
private actor RecordingIndex: SpotlightIndexing {
    enum Call: Equatable {
        case deleteEverything
        case publish(count: Int, stamp: String)
        case recordStamp(String)
    }

    private(set) var calls: [Call] = []
    private var stamp: Data?
    /// When set, the next delete waits for this to be released, which is the
    /// window a second caller arrives in.
    private var gate: CheckedContinuation<Void, Never>?
    private var isGated = false

    init(stamp: Data? = nil, gated: Bool = false) {
        self.stamp = stamp
        self.isGated = gated
    }

    func openGate() {
        isGated = false
        gate?.resume()
        gate = nil
    }

    func lastStamp() async -> Data? { stamp }

    func deleteEverything() async {
        if isGated {
            await withCheckedContinuation { continuation in gate = continuation }
        }
        calls.append(.deleteEverything)
    }

    func publish(_ items: [CSSearchableItem], stamp newStamp: Data) async {
        stamp = newStamp
        calls.append(.publish(count: items.count,
                              stamp: String(decoding: newStamp, as: UTF8.self)))
    }

    func recordStamp(_ newStamp: Data) async {
        stamp = newStamp
        calls.append(.recordStamp(String(decoding: newStamp, as: UTF8.self)))
    }
}

private func bookmark(_ title: String) -> Bookmark {
    Bookmark(id: UUID(), url: "https://a.com/\(title)", title: title, author: nil, note: nil,
             folder: "Recipes", source: .web, createdAt: Date(timeIntervalSince1970: 0),
             doneAt: nil, hasThumbnail: false, manuallyFiled: false)
}

@Test func turningTheSettingOffDuringAWriteStillClearsTheIndex() async {
    // The privacy control: a clear that arrives while a publish is running
    // must never be the request that gets dropped. It was, once.
    let index = RecordingIndex(gated: true)
    let writer = SpotlightWriter(index: index)

    let publishing = Task { await writer.write([bookmark("Pasta")]) }
    // The publish is parked inside deleteEverything; opt out now.
    let clearing = Task { await writer.clear() }
    try? await Task.sleep(for: .milliseconds(50))
    await index.openGate()
    _ = await (publishing.value, clearing.value)

    let calls = await index.calls
    #expect(calls.contains(.recordStamp("")))
    #expect(calls.last == .recordStamp(""))
}

@Test func aWriteAndAClearNeverRunAtTheSameTime() async {
    let index = RecordingIndex(gated: true)
    let writer = SpotlightWriter(index: index)
    let publishing = Task { await writer.write([bookmark("Pasta")]) }
    let clearing = Task { await writer.clear() }
    try? await Task.sleep(for: .milliseconds(50))
    await index.openGate()
    _ = await (publishing.value, clearing.value)

    // Each operation deletes exactly once, and the clear's stamp lands last,
    // so the two never interleaved.
    let calls = await index.calls
    #expect(calls.filter { $0 == .deleteEverything }.count == 2)
    #expect(calls.last == .recordStamp(""))
}

@Test func aPublishThatMatchesTheStampTouchesNothing() async {
    let bookmarks = [bookmark("Pasta")]
    let stamp = Data(SpotlightIndex.fingerprint(bookmarks).utf8)
    let index = RecordingIndex(stamp: stamp)
    await SpotlightWriter(index: index).write(bookmarks)
    // The whole point of the stamp: an unchanged library rebuilds nothing.
    #expect(await index.calls.isEmpty)
}

@Test func aPurgedIndexRebuildsBecauseItReportsNoStamp() async {
    let index = RecordingIndex(stamp: nil)
    let bookmarks = [bookmark("Pasta"), bookmark("Tacos")]
    await SpotlightWriter(index: index).write(bookmarks)
    let calls = await index.calls
    #expect(calls.first == .deleteEverything)
    #expect(calls.last == .publish(count: 2, stamp: SpotlightIndex.fingerprint(bookmarks)))
}

@Test func onlyTheNewestRequestQueuedDuringAWriteRuns() async {
    let index = RecordingIndex(gated: true)
    let writer = SpotlightWriter(index: index)
    // Built once: the helper mints a fresh id per call, so rebuilding the
    // same title would not produce the same fingerprint.
    let newest = [bookmark("Three")]
    let first = Task { await writer.write([bookmark("One")]) }
    try? await Task.sleep(for: .milliseconds(20))
    let second = Task { await writer.write([bookmark("Two")]) }
    let third = Task { await writer.write(newest) }
    try? await Task.sleep(for: .milliseconds(50))
    await index.openGate()
    _ = await (first.value, second.value, third.value)

    // Two publishes, not three: the middle request is superseded rather than
    // replayed, so the index lands on the newest library and not a stale one.
    let published = await index.calls.compactMap { call -> String? in
        if case .publish(_, let stamp) = call { return stamp }
        return nil
    }
    #expect(published.count == 2)
    #expect(published.last == SpotlightIndex.fingerprint(newest))
}
