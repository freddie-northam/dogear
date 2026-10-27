import Foundation

@MainActor
public final class EnrichmentService {
    private let store: BookmarkStore
    private let metadata: MetadataService
    private let categorizer: Categorizer
    let thumbnails: ThumbnailCache
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
        guard !started.isPlace else { return }

        let result = await metadata.fetch(for: url)
        let resolved = URLCleaner.canonicalString(result.resolvedURL)

        guard var bookmark = store.library.bookmarks.first(where: { $0.id == id }) else { return }

        bookmark.url = resolved

        guard let fetched = result.metadata else {
            save(bookmark)
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

        guard var latest = store.library.bookmarks.first(where: { $0.id == id }) else { return }
        latest.url = bookmark.url
        latest.title = bookmark.title
        latest.author = bookmark.author
        latest.source = bookmark.source
        latest.hasThumbnail = bookmark.hasThumbnail
        if !latest.manuallyFiled {
            latest.folder = store.library.folders.contains(bookmark.folder) ? bookmark.folder : Library.unsorted
        }
        save(latest)
    }

    private func save(_ latest: Bookmark) {
        // A redirect can resolve to the URL of a bookmark that already exists.
        // No await sits between this check and the write, so no concurrent enrichment can add the URL first.
        // Merge, not only delete `latest`: it may carry a note, a star, a chosen folder or an earlier save date.
        if var survivor = store.library.bookmarks.first(where: { $0.url == latest.url && $0.id != latest.id }) {
            survivor.note = survivor.note ?? latest.note
            survivor.favoritedAt = survivor.favoritedAt ?? latest.favoritedAt
            if latest.manuallyFiled && !survivor.manuallyFiled {
                survivor.folder = latest.folder
                survivor.manuallyFiled = true
            }
            var merged = survivor
            merged.createdAt = min(survivor.createdAt, latest.createdAt)
            merged.doneAt = nil
            store.remove(id: latest.id)
            thumbnails.remove(for: latest.id)
            store.update(merged)
            store.add(url: URL(string: merged.url)!)
            return
        }
        store.update(latest)
    }
}
