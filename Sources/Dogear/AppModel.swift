import AppKit
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
        store.onChange = { [weak self] in self?.revision += 1 }
        AppModel.shared = self
        store.onWriteFailure = { [weak self] error in
            self?.storageError = "Dogear could not save your bookmarks: \(error.localizedDescription)"
        }
        // The store writes on a background queue so a click never waits on the
        // disk. Quit is the one moment that must wait: without this, the last
        // few changes would still be in the queue when the process ends.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.flush() }
        }
    }

    /// Saves every http(s) link in the text. Deduplication applies per URL,
    /// so a link that appears twice in one paste counts once.
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
