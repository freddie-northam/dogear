import Foundation

@MainActor
public final class EnrichmentService {
    private let store: BookmarkStore
    private let metadata: MetadataService
    private let categorizer: Categorizer
    private let thumbnails: ThumbnailCache
    private let client: HTTPClient

    public init(store: BookmarkStore, metadata: MetadataService, categorizer: Categorizer,
                thumbnails: ThumbnailCache, client: HTTPClient) {
        self.store = store
        self.metadata = metadata
        self.categorizer = categorizer
        self.thumbnails = thumbnails
        self.client = client
    }

    public func enrich(id: UUID) async {
        guard let started = store.library.bookmarks.first(where: { $0.id == id }),
              let url = URL(string: started.url) else { return }

        let result = await metadata.fetch(for: url)
        let resolved = URLCleaner.canonicalString(result.resolvedURL)

        // Re-read: the user may have refiled/edited/completed this bookmark while the
        // network fetch was in flight. Apply enrichment onto the fresh state, never the
        // pre-fetch snapshot, so a concurrent edit is never reverted.
        guard var bookmark = store.library.bookmarks.first(where: { $0.id == id }) else { return }

        // Post-redirect dedupe: the resolved URL may match an existing bookmark.
        if let existing = store.library.bookmarks.first(where: { $0.url == resolved && $0.id != id }) {
            store.remove(id: id)
            var bumped = existing
            bumped.doneAt = nil
            store.update(bumped)
            return
        }
        bookmark.url = resolved

        guard let fetched = result.metadata else {
            store.update(bookmark) // keep resolved URL even when enrichment failed
            return
        }

        if let title = fetched.title, !title.isEmpty { bookmark.title = title }
        bookmark.author = fetched.author ?? bookmark.author
        bookmark.source = fetched.source

        if !bookmark.manuallyFiled {
            let folders = store.library.folders
            let guess = await categorizer.categorize(fetched, url: result.resolvedURL, folders: folders)
            bookmark.folder = (guess.flatMap { folders.contains($0) ? $0 : nil }) ?? Library.unsorted
        }

        if let thumbnailURL = fetched.thumbnailURL,
           let data = try? await client.data(from: thumbnailURL, limit: FetchLimit.thumbnail),
           thumbnails.store(data, for: bookmark.id) {
            bookmark.hasThumbnail = true
        }

        store.update(bookmark)
    }
}
