import Foundation

public final class BookmarkStore {
    public private(set) var library: Library
    public private(set) var didRecoverFromBackup = false
    public var onChange: (() -> Void)?
    public var onWriteFailure: ((Error) -> Void)?

    private let fileURL: URL
    private let backupURL: URL

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("library.json")
        backupURL = directory.appendingPathComponent("library.json.bak")

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(Library.self, from: data) {
            library = loaded
        } else if FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: backupURL),
                  let loaded = try? JSONDecoder().decode(Library.self, from: data) {
            // The main file exists but is unreadable: restore from backup, never start empty.
            // Write directly (no rotation): library.json is corrupt, not a known-good state,
            // so it must never be copied over the good .bak.
            library = loaded
            didRecoverFromBackup = true
            if let data = try? JSONEncoder().encode(library) {
                try? data.write(to: fileURL, options: .atomic)
            }
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            throw CocoaError(.fileReadCorruptFile)
        } else {
            library = Library(folders: Library.defaultFolders, bookmarks: [])
        }
    }

    // MARK: Mutations

    @discardableResult
    public func add(url: URL) -> (bookmark: Bookmark, isNew: Bool) {
        let result = insert(url: url)
        mutated()
        return result
    }

    /// Batch add with one disk write and one change notification, so a paste
    /// of many links does not encode the whole library once per link.
    /// Returns the new bookmarks in paste order and the count of distinct
    /// bookmarks touched (new plus re-saved duplicates).
    public func add(urls: [URL]) -> (new: [Bookmark], touched: Int) {
        guard !urls.isEmpty else { return ([], 0) }
        var new: [Bookmark] = []
        var touched = Set<UUID>()
        // Insert back to front: each insert lands at index 0, so the batch ends
        // up at the top of the list in paste order, first pasted link first.
        for url in urls.reversed() {
            let (bookmark, isNew) = insert(url: url)
            touched.insert(bookmark.id)
            if isNew { new.append(bookmark) }
        }
        new.reverse()
        mutated()
        return (new, touched.count)
    }

    /// Shared insert path: dedupe on the canonical URL, bump a duplicate to
    /// the top and clear its done state. Does not save; callers call mutated().
    private func insert(url: URL) -> (bookmark: Bookmark, isNew: Bool) {
        let canonical = URLCleaner.canonicalString(url)
        if let index = library.bookmarks.firstIndex(where: { $0.url == canonical }) {
            var existing = library.bookmarks.remove(at: index)
            existing.doneAt = nil
            library.bookmarks.insert(existing, at: 0)
            return (existing, false)
        }
        let bookmark = Bookmark(
            id: UUID(), url: canonical, title: displayTitle(for: url),
            author: nil, note: nil, folder: Library.unsorted, source: .web,
            createdAt: Date(), doneAt: nil, hasThumbnail: false, manuallyFiled: false
        )
        library.bookmarks.insert(bookmark, at: 0)
        return (bookmark, true)
    }

    public func update(_ bookmark: Bookmark) {
        guard let index = library.bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        var bookmark = bookmark
        if let url = URL(string: bookmark.url) {
            bookmark.url = URLCleaner.canonicalString(url)
        }
        library.bookmarks[index] = bookmark
        mutated()
    }

    public func remove(id: UUID) {
        library.bookmarks.removeAll { $0.id == id }
        mutated()
    }

    public func markDone(id: UUID) { setDone(id: id, date: Date()) }
    public func markUndone(id: UUID) { setDone(id: id, date: nil) }

    private func setDone(id: UUID, date: Date?) {
        guard let index = library.bookmarks.firstIndex(where: { $0.id == id }) else { return }
        library.bookmarks[index].doneAt = date
        mutated()
    }

    public func toggleFavorite(id: UUID) {
        guard let index = library.bookmarks.firstIndex(where: { $0.id == id }) else { return }
        library.bookmarks[index].favoritedAt = library.bookmarks[index].isFavorite ? nil : Date()
        mutated()
    }

    public func refile(id: UUID, to folder: String) {
        guard let index = library.bookmarks.firstIndex(where: { $0.id == id }) else { return }
        library.bookmarks[index].folder = folder
        library.bookmarks[index].manuallyFiled = true
        mutated()
    }

    public func addFolder(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !library.folders.contains(name) else { return }
        // Insert before Unsorted wherever it sits: a loaded library may not have it last,
        // and an empty folder list would make a count-based index negative.
        let index = library.folders.firstIndex(of: Library.unsorted) ?? library.folders.endIndex
        library.folders.insert(name, at: index)
        mutated()
    }

    public func renameFolder(_ name: String, to newName: String) {
        let newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name != Library.unsorted, !newName.isEmpty,
              let index = library.folders.firstIndex(of: name),
              !library.folders.contains(newName) else { return }
        library.folders[index] = newName
        for i in library.bookmarks.indices where library.bookmarks[i].folder == name {
            library.bookmarks[i].folder = newName
        }
        mutated()
    }

    public func removeFolder(_ name: String) {
        guard name != Library.unsorted, library.folders.contains(name) else { return }
        library.folders.removeAll { $0 == name }
        for i in library.bookmarks.indices where library.bookmarks[i].folder == name {
            library.bookmarks[i].folder = Library.unsorted
        }
        mutated()
    }

    // MARK: Queries

    // Newest-first by insertion order: adds and re-adds land at the top of the
    // array (a batch in paste order), so no sort is needed.
    public func bookmarks(in folder: String) -> [Bookmark] {
        library.bookmarks.filter { $0.folder == folder && !$0.isDone }
    }

    public func archive() -> [Bookmark] {
        library.bookmarks.filter(\.isDone)
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    public func search(_ query: String) -> [Bookmark] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }
        return library.bookmarks.filter {
            $0.title.lowercased().contains(needle)
                || ($0.author?.lowercased().contains(needle) ?? false)
                || ($0.note?.lowercased().contains(needle) ?? false)
                || $0.url.lowercased().contains(needle)
        }
    }

    /// Favourites are a lens, not a queue: done bookmarks stay in the list.
    public func favorites() -> [Bookmark] {
        library.bookmarks.filter(\.isFavorite)
            .sorted { ($0.favoritedAt ?? .distantPast) > ($1.favoritedAt ?? .distantPast) }
    }

    /// A random not-done bookmark to resurface. The given id is excluded when
    /// another candidate exists, so "show another" never repeats itself.
    public func pick(excluding excluded: UUID? = nil) -> Bookmark? {
        let waiting = library.bookmarks.filter { !$0.isDone }
        let fresh = waiting.filter { $0.id != excluded }
        return (fresh.isEmpty ? waiting : fresh).randomElement()
    }

    // MARK: Persistence

    private func mutated() {
        saveNow()
        onChange?()
    }

    public func saveNow() {
        let data: Data
        do {
            data = try JSONEncoder().encode(library)
        } catch {
            onWriteFailure?(error)
            return
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            onWriteFailure?(error)
        }
    }

    // Test-only fast path: skips per-add disk writes so the 5,000-item benchmark
    // measures load time, not 5,000 saves.
    func addForTesting(urlString: String) -> Bookmark {
        let bookmark = Bookmark(
            id: UUID(), url: urlString, title: urlString, author: nil, note: nil,
            folder: Library.unsorted, source: .web, createdAt: Date(), doneAt: nil,
            hasThumbnail: false, manuallyFiled: false
        )
        library.bookmarks.append(bookmark)
        return bookmark
    }

    private func displayTitle(for url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let path = url.path == "/" ? "" : url.path
        return host + path
    }
}
