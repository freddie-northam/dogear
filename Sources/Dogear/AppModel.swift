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
    let store: BookmarkStore
    let enrichment: EnrichmentService
    let thumbnails: ThumbnailCache
    @Published var revision = 0
    @Published var storageError: String?

    init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dogear")
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
        store.onWriteFailure = { [weak self] error in
            self?.storageError = "Dogear could not save your bookmarks: \(error.localizedDescription)"
        }
    }

    /// Saves every http(s) link in the text. Deduplication applies per URL,
    /// so a link that appears twice in one paste counts once.
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
