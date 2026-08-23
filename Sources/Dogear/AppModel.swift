import DogearKit
import Foundation
import SwiftUI

enum CaptureResult { case saved, alreadySaved, invalid }

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

    func capture(text: String) -> CaptureResult {
        guard let url = URLCleaner.firstHTTPURL(in: text) else { return .invalid }
        let (bookmark, isNew) = store.add(url: url)
        if isNew {
            let id = bookmark.id
            Task { await enrichment.enrich(id: id) }
        }
        return isNew ? .saved : .alreadySaved
    }
}
