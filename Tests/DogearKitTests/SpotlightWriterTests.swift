import CoreSpotlight
import Foundation
import Testing
@testable import DogearKit

private actor RecordingIndex: SpotlightIndexing {
    enum Call: Equatable {
        case deleteEverything
        case publish(count: Int, stamp: String)
        case recordStamp(String)
    }

    private(set) var calls: [Call] = []
    private var stamp: Data?
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
    let index = RecordingIndex(gated: true)
    let writer = SpotlightWriter(index: index)

    let publishing = Task { await writer.write([bookmark("Pasta")]) }
    try? await Task.sleep(for: .milliseconds(20))
    await writer.clear()
    await index.openGate()
    await publishing.value

    let calls = await index.calls
    #expect(calls.contains(.recordStamp("")))
    #expect(calls.last == .recordStamp(""))
}

@Test func aWriteAndAClearNeverRunAtTheSameTime() async {
    let index = RecordingIndex(gated: true)
    let writer = SpotlightWriter(index: index)
    let publishing = Task { await writer.write([bookmark("Pasta")]) }
    try? await Task.sleep(for: .milliseconds(20))
    await writer.clear()
    await index.openGate()
    await publishing.value

    let calls = await index.calls
    #expect(calls.filter { $0 == .deleteEverything }.count == 2)
    #expect(calls.last == .recordStamp(""))
}

@Test func aPublishThatMatchesTheStampTouchesNothing() async {
    let bookmarks = [bookmark("Pasta")]
    let stamp = Data(SpotlightIndex.fingerprint(bookmarks).utf8)
    let index = RecordingIndex(stamp: stamp)
    await SpotlightWriter(index: index).write(bookmarks)
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
    let newest = [bookmark("Three")]
    let first = Task { await writer.write([bookmark("One")]) }
    try? await Task.sleep(for: .milliseconds(20))
    await writer.write([bookmark("Two")])
    await writer.write(newest)
    await index.openGate()
    await first.value

    let published = await index.calls.compactMap { call -> String? in
        if case .publish(_, let stamp) = call { return stamp }
        return nil
    }
    #expect(published.count == 2)
    #expect(published.last == SpotlightIndex.fingerprint(newest))
}
