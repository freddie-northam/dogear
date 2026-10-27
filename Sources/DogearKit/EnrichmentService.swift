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
        guard let started = current(id), !started.isPlace,
              let url = URL(string: started.url) else { return }

        let result = await metadata.fetch(for: url)
        let resolved = URLCleaner.canonicalString(result.resolvedURL)
        let fetched = result.metadata

        var guess: String?
        if let fetched, current(id)?.manuallyFiled == false {
            guess = await categorizer.categorize(fetched, url: result.resolvedURL, folders: store.library.folders)
        }
        var storedThumbnail = false
        if let thumbnailURL = fetched?.thumbnailURL,
           let data = try? await client.data(from: thumbnailURL, limit: FetchLimit.thumbnail) {
            storedThumbnail = thumbnails.store(data, for: id)
        }

        // Every await above lets the user edit this bookmark, so apply onto the record as it is now.
        guard var latest = current(id) else { return }
        latest.url = resolved
        if storedThumbnail { latest.hasThumbnail = true }
        if let fetched {
            if let title = fetched.title, !title.isEmpty { latest.title = title }
            latest.author = fetched.author ?? latest.author
            latest.source = fetched.source
            if !latest.manuallyFiled {
                latest.folder = guess.flatMap { store.library.folders.contains($0) ? $0 : nil } ?? Library.unsorted
            }
        }
        save(latest)
    }

    private func current(_ id: UUID) -> Bookmark? {
        store.library.bookmarks.first { $0.id == id }
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
            survivor.createdAt = min(survivor.createdAt, latest.createdAt)
            store.remove(id: latest.id)
            thumbnails.remove(for: latest.id)
            store.update(survivor)
            store.add(url: URL(string: survivor.url)!)
            return
        }
        store.update(latest)
    }
}
