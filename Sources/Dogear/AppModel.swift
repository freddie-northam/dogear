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
        var touched = Set<UUID>()
        var newCount = 0
        for url in URLCleaner.allHTTPURLs(in: text) {
            let (bookmark, isNew) = store.add(url: url)
            touched.insert(bookmark.id)
            if isNew {
                newCount += 1
                let id = bookmark.id
                Task { await enrichment.enrich(id: id) }
            }
        }
        return CaptureResult(new: newCount, total: touched.count)
    }
}
