import CoreSpotlight
import Foundation

/// The system index, behind one small protocol. `CSSearchableIndex` writes the
/// real Spotlight index of whoever runs the app and takes no stand-in, so the
/// calls it needs are named here and a test substitutes them, the same way
/// `HTTPClient` and `PlaceResolver` are handled.
public protocol SpotlightIndexing: Sendable {
    /// What Dogear last recorded about the state of the index, or nil when the
    /// system has never held one or has purged it.
    func lastStamp() async -> Data?
    func deleteEverything() async
    /// Publishes the items and records the stamp in one batch.
    func publish(_ items: [CSSearchableItem], stamp: Data) async
    /// Records a stamp with nothing published.
    func recordStamp(_ stamp: Data) async
}

/// Serializes every write to the search index.
///
/// CoreSpotlight is explicit that a batch must not be opened again before the
/// previous one has ended, and that concurrent calls to one index instance
/// have undefined results. Dogear writes from three places, and the debounce
/// upstream does not prevent overlap: indexing a large library can outlast it,
/// and the Settings toggle writes directly.
///
/// Turning the setting off must never be the request that gets dropped, so a
/// clear and a publish share one queue rather than one cancelling the other.
public actor SpotlightWriter {
    /// The two things a caller can ask for.
    enum Request: Equatable {
        case publish(bookmarks: [Bookmark], fingerprint: String)
        case clear
    }

    private let index: SpotlightIndexing
    private var isWriting = false
    /// The newest request that arrived while one was running. Holding the
    /// newest, rather than dropping it, is what stops the index settling one
    /// version behind the library while its stamp claims to be current, and it
    /// is what guarantees an opt-out still reaches the system.
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

    /// Runs one request at a time, then drains whatever arrived during it. A
    /// later request replaces an earlier queued one, so the last thing the
    /// user asked for is the thing that lands.
    private func run(_ request: Request) async {
        guard !isWriting else {
            queued = request
            return
        }
        isWriting = true
        defer { isWriting = false }
        var current: Request? = request
        // An await inside perform lets another caller in; it parks its request
        // rather than opening a second batch, so drain before finishing.
        while let next = current {
            await perform(next)
            current = queued
            queued = nil
        }
    }

    private func perform(_ request: Request) async {
        switch request {
        case .publish(let bookmarks, let fingerprint):
            // Rebuild only when the stamp no longer matches the library. That
            // stamp survives a relaunch, which is what stops a login-item app
            // rewriting the whole system index once per session for a library
            // nobody changed. A purged index returns no stamp, which reads as
            // a mismatch and rebuilds, so repair costs nothing extra.
            let published = await index.lastStamp().flatMap { String(data: $0, encoding: .utf8) }
            guard published != fingerprint else { return }
            await index.deleteEverything()
            await index.publish(bookmarks.map(SpotlightIndex.item(for:)),
                                stamp: Data(fingerprint.utf8))
        case .clear:
            await index.deleteEverything()
            // An empty stamp, so turning the setting back on rebuilds rather
            // than trusting a fingerprint whose items are gone.
            await index.recordStamp(Data())
        }
    }
}
