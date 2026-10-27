import CoreSpotlight
import Foundation

/// The system index, behind one small protocol.
public protocol SpotlightIndexing: Sendable {
    /// What Dogear last recorded about the index, or nil when it has recorded nothing.
    func lastStamp() async -> Data?
    func deleteEverything() async
    /// Publishes the items and records the stamp.
    func publish(_ items: [CSSearchableItem], stamp: Data) async
    /// Records a stamp with nothing published.
    func recordStamp(_ stamp: Data) async
}

/// Serializes every write to the search index.
///
/// CoreSpotlight gives undefined results for concurrent calls to one index instance.
/// Dogear writes from three places, and the upstream debounce does not prevent overlap.
/// A large library can take longer to index than the debounce, and the Settings toggle writes directly.
///
/// Turning the setting off must never be the request that gets dropped, so a
/// clear and a publish share one queue rather than one cancelling the other.
public actor SpotlightWriter {
    enum Request: Equatable {
        case publish(bookmarks: [Bookmark], fingerprint: String)
        case clear
    }

    private let index: SpotlightIndexing
    private var isWriting = false
    private var queued: Request?

    public init(index: SpotlightIndexing) {
        self.index = index
    }

    public func write(_ bookmarks: [Bookmark]) async {
        await run(.publish(bookmarks: bookmarks,
                           fingerprint: SpotlightIndex.fingerprint(bookmarks)))
    }

    public func clear() async {
        await run(.clear)
    }

    private func run(_ request: Request) async {
        guard !isWriting else {
            queued = request
            return
        }
        isWriting = true
        defer { isWriting = false }
        var current: Request? = request
        while let next = current {
            await perform(next)
            current = queued
            queued = nil
        }
    }

    private func perform(_ request: Request) async {
        switch request {
        case .publish(let bookmarks, let fingerprint):
            let published = await index.lastStamp().flatMap { String(data: $0, encoding: .utf8) }
            guard published != fingerprint else { return }
            await index.deleteEverything()
            await index.publish(bookmarks.map(SpotlightIndex.item(for:)),
                                stamp: Data(fingerprint.utf8))
        case .clear:
            await index.deleteEverything()
            await index.recordStamp(Data())
        }
    }
}
