import DogearKit
import Foundation
import SwiftUI

struct CaptureResult {
    /// Distinct bookmarks created by this capture.
    let new: Int
    /// Distinct bookmarks touched: created plus re-saved duplicates.
    let total: Int
}

@MainActor
final class AppModel: ObservableObject {
    /// The one live model, for scenes that must not eagerly build their view
    /// tree (Settings). Set once by DogearApp; nil only before the app exists.
    static weak var shared: AppModel?

    let store: BookmarkStore
    let enrichment: EnrichmentService
    let thumbnails: ThumbnailCache
    @Published var revision = 0
    @Published var storageError: String?
    /// Set when a Spotlight result asks the library to show a bookmark.
    struct SpotlightReveal: Equatable {
        let folder: String
        let query: String
    }
    @Published var spotlightRequest: SpotlightReveal?
    /// True for a moment after a save that had no window on screen. The menu
    /// bar shows a tick, because the app sends no notifications.
    @Published private(set) var showsSavedTick = false

    private var spotlightTask: Task<Void, Never>?

    init() {
        // DOGEAR_DATA_DIR points the app at another library: screenshots and
        // demos run against a throwaway directory, never a real one.
        let supportDir: URL
        if let override = ProcessInfo.processInfo.environment["DOGEAR_DATA_DIR"], !override.isEmpty {
            supportDir = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Dogear")
        }
        // A store that cannot initialize means unreadable data with no backup.
        // Crashing here is correct: never run against a store we cannot trust.
        store = try! BookmarkStore(directory: supportDir)
        thumbnails = try! ThumbnailCache(directory: supportDir.appendingPathComponent("thumbnails"))
        if store.didRecoverFromBackup {
            storageError = "Dogear restored your bookmarks from a backup. Recent changes may be missing."
        }
        let client = URLSessionHTTPClient()
        enrichment = EnrichmentService(
            store: store,
            metadata: MetadataService(client: client),
            categorizer: CategorizerFactory.make(),
            thumbnails: thumbnails,
            client: client
        )
        store.onChange = { [weak self] in
            self?.revision += 1
            self?.scheduleSpotlightSync()
        }
        // A library saved before this version was never published, so index
        // once at launch. The delay keeps it clear of the first frame.
        scheduleSpotlightSync()
        AppModel.shared = self
        store.onWriteFailure = { [weak self] error in
            self?.storageError = "Dogear could not save your bookmarks: \(error.localizedDescription)"
        }
    }

    /// Saves every http(s) link in the text. Deduplication applies per URL,
    /// so a link that appears twice in one paste counts once.
    // MARK: Spotlight

    /// Republishes the library after the changes stop. A paste of fifty links
    /// fires onChange once, but a burst of enrichments fires it fifty times,
    /// and each one would otherwise rebuild the whole index.
    private func scheduleSpotlightSync() {
        // Nothing to publish and nothing to clear: the toggle already cleared
        // the index once when the user turned it off. Without this, every
        // capture and every enrichment would ask Spotlight to delete an empty
        // domain, for as long as the app runs.
        guard SpotlightSync.isEnabled else { return }
        spotlightTask?.cancel()
        spotlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.syncSpotlight()
        }
    }

    /// Publishes the library, or clears it when the user turns the setting off.
    func syncSpotlight() {
        guard SpotlightSync.isEnabled else {
            SpotlightSync.removeAll()
            return
        }
        SpotlightSync.replaceAll(with: store.library.bookmarks)
    }

    /// Answers a Spotlight result by asking the library to search for it. The
    /// library, not the browser, is the honest destination: it shows the note
    /// and the folder the user filed it under.
    func showFromSpotlight(id: String) {
        guard let uuid = UUID(uuidString: id),
              let bookmark = store.library.bookmarks.first(where: { $0.id == uuid }) else { return }
        // Open the folder the bookmark actually lives in. Searching the title
        // alone dropped the user into an all-folders result list, so a done
        // bookmark and a filed one looked the same and two similar titles
        // gave no way to tell which one Spotlight had matched.
        spotlightRequest = SpotlightReveal(
            folder: bookmark.isDone ? AppModel.archiveID : bookmark.folder,
            query: bookmark.title)
    }

    /// The sidebar's identifier for the archive, shared with the library window.
    static let archiveID = "__archive__"

    // MARK: Forgiveness

    /// Every destructive action registers its inverse here, so Undo works the
    /// same from a card, a list row, the sidebar, and the popover. Undo
    /// closures are @Sendable and run on the main thread; the explicit hop
    /// is what lets them touch main-actor state honestly. A nil manager (no
    /// window) still performs the action, just without undo.

    // Deletion, done, and their undo are the only library changes that
    // animate. Capture, filing, and enrichment stay hard cuts: they arrive
    // in batches and the user did not point at a card.

    func deleteBookmark(_ bookmark: Bookmark, undoManager: UndoManager?) {
        guard let removed = withAnimation(Motion.shuffle, { store.remove(id: bookmark.id) }) else { return }
        // The cached thumbnail stays while undo is possible so a restored
        // bookmark keeps its image; the cache tolerates an orphan if the
        // delete is never undone.
        if undoManager == nil { thumbnails.remove(for: bookmark.id) }
        register(undoManager, name: "Delete Bookmark") { model in
            model.store.restore(removed.bookmark, at: removed.index)
            model.register(undoManager, name: "Delete Bookmark") { model in
                model.deleteBookmark(bookmark, undoManager: undoManager)
            }
        }
    }

    func markDone(_ id: UUID, undoManager: UndoManager?) {
        withAnimation(Motion.shuffle) { store.markDone(id: id) }
        register(undoManager, name: "Mark Done") { model in
            model.store.markUndone(id: id)
            model.register(undoManager, name: "Mark Done") { model in
                model.markDone(id, undoManager: undoManager)
            }
        }
    }

    func deleteFolder(_ name: String, undoManager: UndoManager?) {
        guard let removed = withAnimation(Motion.shuffle, { store.removeFolder(name) }) else { return }
        register(undoManager, name: "Delete Folder") { model in
            model.store.restoreFolder(name, at: removed.index, bookmarkIDs: removed.bookmarkIDs)
            model.register(undoManager, name: "Delete Folder") { model in
                model.deleteFolder(name, undoManager: undoManager)
            }
        }
    }

    private func register(_ undoManager: UndoManager?, name: String,
                          _ action: @escaping @MainActor (AppModel) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { withAnimation(Motion.shuffle) { action(model) } }
        }
        undoManager.setActionName(name)
    }

    func capture(text: String) -> CaptureResult {
        capture(urls: URLCleaner.allHTTPURLs(in: text))
    }

    /// Re-runs the categorizer over every not-done Unsorted bookmark against
    /// the current folder list. Returns how many were filed.
    func fileUnsorted() async -> Int {
        let categorizer = CategorizerFactory.make()
        let unsorted = store.bookmarks(in: Library.unsorted)
        var assignments: [(id: UUID, folder: String)] = []
        for bookmark in unsorted {
            let metadata = FetchedMetadata(
                title: bookmark.title, author: bookmark.author,
                description: bookmark.note, source: bookmark.source)
            guard let url = URL(string: bookmark.url) else { continue }
            let folders = store.library.folders
            if let folder = await categorizer.categorize(metadata, url: url, folders: folders),
               folder != Library.unsorted {
                assignments.append((id: bookmark.id, folder: folder))
            }
        }
        return store.autoFile(assignments)
    }

    /// Saves resolved places and draws a map for each one. Places never go
    /// through enrichment: there is no page to read, and a fetch of the map
    /// link would only overwrite the name the user just approved. Returns how
    /// many were saved.
    func importPlaces(_ places: [Place], to folder: String) -> Int {
        let saved = store.add(places: places, to: folder)
        guard !saved.isEmpty else { return 0 }
        let thumbnails = thumbnails
        let store = store
        Task { @MainActor in
            // At most four maps drawing at once, the same cap capture uses:
            // twenty places must not draw one map after another.
            var drawn: [UUID] = []
            await withTaskGroup(of: UUID?.self) { group in
                var iterator = saved.makeIterator()
                for _ in 0..<4 {
                    guard let bookmark = iterator.next() else { break }
                    group.addTask { await AppModel.drawMap(for: bookmark, into: thumbnails) }
                }
                for await id in group {
                    if let id { drawn.append(id) }
                    guard let bookmark = iterator.next() else { continue }
                    group.addTask { await AppModel.drawMap(for: bookmark, into: thumbnails) }
                }
            }
            // One write for the batch. A write per map would undo the batching
            // add(places:) just did.
            store.markThumbnails(drawn)
        }
        return saved.count
    }

    /// Draws one map off the main actor and returns the id when an image
    /// landed on disk. Nonisolated on purpose: inheriting the main actor here
    /// would make the task group draw the maps one at a time.
    private nonisolated static func drawMap(for bookmark: Bookmark,
                                            into thumbnails: ThumbnailCache) async -> UUID? {
        guard let place = bookmark.place,
              let data = await PlaceSnapshot.pngData(for: place),
              thumbnails.store(data, for: bookmark.id) else { return nil }
        return bookmark.id
    }

    /// A save with nothing on screen: the shortcut, the Services item, and
    /// the Shortcuts action. All three go through here so the confirmation
    /// belongs to the save rather than to one of the three callers.
    @discardableResult
    func captureWithoutWindow(text: String) -> CaptureResult {
        let result = capture(text: text)
        guard result.total > 0 else { return result }
        showsSavedTick = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.showsSavedTick = false
        }
        return result
    }

    func capture(urls: [URL]) -> CaptureResult {
        // The one capture gate: every caller (text, drop, import) inherits it.
        // A dropped file:// URL must never become a bookmark or reach enrichment.
        let urls = urls.filter {
            let scheme = $0.scheme?.lowercased()
            return scheme == "http" || scheme == "https"
        }
        let (new, touched) = store.add(urls: urls)
        let ids = new.map(\.id)
        if !ids.isEmpty {
            let enrichment = enrichment
            Task {
                // At most four enrichments in flight: a big Notes paste must not
                // open one network fetch per link at once.
                await withTaskGroup(of: Void.self) { group in
                    var iterator = ids.makeIterator()
                    for _ in 0..<4 {
                        guard let id = iterator.next() else { break }
                        group.addTask { await enrichment.enrich(id: id) }
                    }
                    for await _ in group {
                        guard let id = iterator.next() else { continue }
                        group.addTask { await enrichment.enrich(id: id) }
                    }
                }
            }
        }
        return CaptureResult(new: ids.count, total: touched)
    }
}
