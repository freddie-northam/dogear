import DogearKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static weak var shared: AppModel?

    let directory: URL
    let store: BookmarkStore
    let enrichment: EnrichmentService
    let capture: Capture
    let thumbnails: ThumbnailCache
    @Published var revision = 0
    @Published var storageError: String?
    struct SpotlightReveal: Equatable {
        let folder: String
        let query: String
    }
    @Published var spotlightRequest: SpotlightReveal?
    @Published private(set) var showsSavedTick = false

    private var spotlightTask: Task<Void, Never>?

    init() {
        if let override = ProcessInfo.processInfo.environment["DOGEAR_DATA_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Dogear")
        }
        do {
            store = try BookmarkStore(directory: directory)
            thumbnails = try ThumbnailCache(directory: directory.appendingPathComponent("thumbnails"))
        } catch {
            fatalError("Dogear cannot read its library and has no backup: \(error)")
        }
        if store.didRecoverFromBackup {
            storageError = "Dogear restored your bookmarks from a backup. Recent changes may be missing."
        }
        let client = URLSessionHTTPClient()
        let enrichment = EnrichmentService(
            store: store,
            metadata: MetadataService(client: client),
            categorizer: CategorizerFactory.make(),
            thumbnails: thumbnails,
            client: client
        )
        self.enrichment = enrichment
        capture = Capture(store: store) { await enrichment.enrich(id: $0) }
        store.onChange = { [weak self] in
            self?.revision += 1
            self?.scheduleSpotlightSync()
        }
        scheduleSpotlightSync()
        AppModel.shared = self
        store.onWriteFailure = { [weak self] error in
            self?.storageError = "Dogear could not save your bookmarks: \(error.localizedDescription)"
        }
        // The store writes on a queue, so a change from just before quit can still be waiting.
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [store] _ in store.flush() }
    }

    // MARK: Spotlight

    /// Republishes the library after the changes stop.
    /// A paste of fifty links fires `onChange` once, but fifty enrichments fire it fifty times.
    /// Without the delay, each one rebuilds the whole index.
    private func scheduleSpotlightSync() {
        guard SpotlightSync.isEnabled else { return }
        spotlightTask?.cancel()
        spotlightTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.syncSpotlight()
        }
    }

    func syncSpotlight() {
        guard SpotlightSync.isEnabled else {
            SpotlightSync.removeAll()
            return
        }
        SpotlightSync.replaceAll(with: store.library.bookmarks)
    }

    func showFromSpotlight(id: String) {
        guard let uuid = UUID(uuidString: id),
              let bookmark = store.library.bookmarks.first(where: { $0.id == uuid }) else { return }
        spotlightRequest = SpotlightReveal(
            folder: bookmark.isDone ? AppModel.archiveID : bookmark.folder,
            query: bookmark.title)
    }

    static let archiveID = "__archive__"

    func deleteBookmark(_ bookmark: Bookmark, undoManager: UndoManager?) {
        guard let removed = withAnimation(Motion.shuffle, { store.remove(id: bookmark.id) }) else { return }
        if undoManager == nil { thumbnails.remove(for: bookmark.id) }
        register(undoManager, name: "Delete Bookmark") { model in
            if let dropped = model.store.restore(removed.bookmark, at: removed.index) {
                model.thumbnails.remove(for: dropped.id)
            }
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

    /// Runs the categorizer again on each Unsorted bookmark that is not done, with the current folders.
    /// Returns how many it filed.
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

    func importPlaces(_ places: [Place], to folder: String) -> Int {
        let saved = store.add(places: places, to: folder)
        guard !saved.isEmpty else { return 0 }
        let thumbnails = thumbnails
        let store = store
        Task { @MainActor in
            let drawn = await boundedMap(saved, limit: Capture.maxInFlight) {
                await AppModel.drawMap(for: $0, into: thumbnails)
            }
            store.markThumbnails(drawn.compactMap { $0 })
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

    @discardableResult
    func captureWithoutWindow(text: String) -> Capture.Outcome {
        let outcome = capture.save(.text(text))
        guard outcome.found > 0 else { return outcome }
        showsSavedTick = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            self?.showsSavedTick = false
        }
        return outcome
    }
}
