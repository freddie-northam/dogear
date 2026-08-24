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
            migrate()
        } else if let data = try? Data(contentsOf: backupURL),
                  let loaded = try? JSONDecoder().decode(Library.self, from: data) {
            // The main file is missing or unreadable: restore from backup, never start empty.
            // Write directly (no rotation): the main file is not a known-good state,
            // so it must never be copied over the good .bak.
            library = loaded
            didRecoverFromBackup = true
            if let data = try? JSONEncoder().encode(library) {
                try? data.write(to: fileURL, options: .atomic)
            }
            migrate()
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            throw CocoaError(.fileReadCorruptFile)
        } else {
            library = Library(folders: Library.defaultFolders, bookmarks: [], schemaVersion: Library.currentSchemaVersion)
        }
    }

    /// One-shot forward migration for a library saved by an older app version.
    /// The schema-version gate makes every step below run at most once per
    /// library: a user who later removes an adopted default folder is not
    /// fighting the app every launch.
    private func migrate() {
        guard (library.schemaVersion ?? 1) < Library.currentSchemaVersion else { return }

        for folder in Library.defaultFolders where folder != Library.unsorted && !library.folders.contains(folder) {
            let index = library.folders.firstIndex(of: Library.unsorted) ?? library.folders.endIndex
            library.folders.insert(folder, at: index)
        }

        // Re-canonicalize every stored URL, merging any collision this creates
        // (e.g. an old twitter.com save now matching a newer x.com save of the
        // same link). The earlier bookmark in storage order survives; note and
        // favoritedAt are copied onto it only when it lacks them.
        var canonicalized: [Bookmark] = []
        var indexByURL: [String: Int] = [:]
        for var bookmark in library.bookmarks {
            if let url = URL(string: bookmark.url) {
                bookmark.url = URLCleaner.canonicalString(url)
            }
            if let existingIndex = indexByURL[bookmark.url] {
                if canonicalized[existingIndex].note == nil {
                    canonicalized[existingIndex].note = bookmark.note
                }
                if canonicalized[existingIndex].favoritedAt == nil {
                    canonicalized[existingIndex].favoritedAt = bookmark.favoritedAt
                }
            } else {
                indexByURL[bookmark.url] = canonicalized.count
                canonicalized.append(bookmark)
            }
        }
        library.bookmarks = canonicalized

        library.schemaVersion = Library.currentSchemaVersion
        saveNow()
    }

    // MARK: Mutations

    @discardableResult
    public func add(url: URL) -> (bookmark: Bookmark, isNew: Bool)? {
        guard let result = insert(url: url) else { return nil }
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
            guard let (bookmark, isNew) = insert(url: url) else { continue }
            touched.insert(bookmark.id)
            if isNew { new.append(bookmark) }
        }
        new.reverse()
        mutated()
        return (new, touched.count)
    }

    /// Shared insert path: dedupe on the canonical URL, bump a duplicate to
    /// the top and clear its done state. Does not save; callers call mutated().
    private func insert(url: URL) -> (bookmark: Bookmark, isNew: Bool)? {
        guard URLCleaner.isCapturable(url) else { return nil }
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
        guard URL(string: bookmark.url).map(URLCleaner.isCapturable) == true else { return }
        library.bookmarks[index] = bookmark
        mutated()
    }

    /// Removes a bookmark and returns what undo needs: the record and the
    /// index it held, so `restore` can put it back exactly where it was.
    @discardableResult
    public func remove(id: UUID) -> (bookmark: Bookmark, index: Int)? {
        guard let index = library.bookmarks.firstIndex(where: { $0.id == id }) else { return nil }
        let bookmark = library.bookmarks.remove(at: index)
        mutated()
        return (bookmark, index)
    }

    /// Reinserts a removed bookmark at its original position (clamped to the
    /// current count). A record already present is left alone.
    public func restore(_ bookmark: Bookmark, at index: Int) {
        guard !library.bookmarks.contains(where: { $0.id == bookmark.id }) else { return }
        library.bookmarks.insert(bookmark, at: min(index, library.bookmarks.endIndex))
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

    /// Files bookmarks without claiming the user chose the folder, so a
    /// later categorizer run may still move them. For the categorizer's own
    /// use. Skips an assignment whose id is unknown, whose bookmark is
    /// manuallyFiled, whose bookmark has already left Unsorted (a mid-run
    /// user move), or whose target folder does not exist. Saves and notifies
    /// at most once, only when at least one assignment applied. Returns the
    /// number applied.
    @discardableResult
    public func autoFile(_ assignments: [(id: UUID, folder: String)]) -> Int {
        var applied = 0
        for assignment in assignments {
            guard let index = library.bookmarks.firstIndex(where: { $0.id == assignment.id }),
                  !library.bookmarks[index].manuallyFiled,
                  library.bookmarks[index].folder == Library.unsorted,
                  library.folders.contains(assignment.folder) else { continue }
            library.bookmarks[index].folder = assignment.folder
            applied += 1
        }
        if applied > 0 { mutated() }
        return applied
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

    /// Reorders the user-facing folders. Unsorted is pinned last: it is an
    /// inbox, not a folder the user arranges, so moves that would displace it
    /// are clamped to the slot above it.
    public func moveFolders(fromOffsets source: IndexSet, toOffset destination: Int) {
        var movable = library.folders.filter { $0 != Library.unsorted }
        let hasUnsorted = movable.count != library.folders.count
        let clampedDestination = min(destination, movable.count)
        movable.move(fromOffsets: source, toOffset: clampedDestination)
        library.folders = hasUnsorted ? movable + [Library.unsorted] : movable
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

    /// Removes a folder, moving its bookmarks to Unsorted. Returns what undo
    /// needs: the folder's index and the ids it held, so `restoreFolder` can
    /// put the folder back and re-home exactly those bookmarks.
    @discardableResult
    public func removeFolder(_ name: String) -> (index: Int, bookmarkIDs: [UUID])? {
        guard name != Library.unsorted, let index = library.folders.firstIndex(of: name) else { return nil }
        library.folders.remove(at: index)
        var moved: [UUID] = []
        for i in library.bookmarks.indices where library.bookmarks[i].folder == name {
            library.bookmarks[i].folder = Library.unsorted
            moved.append(library.bookmarks[i].id)
        }
        mutated()
        return (index, moved)
    }

    /// Reverses `removeFolder`: the folder returns to its index and the listed
    /// bookmarks return to it. A name already in use is left alone.
    public func restoreFolder(_ name: String, at index: Int, bookmarkIDs: [UUID]) {
        guard name != Library.unsorted, !library.folders.contains(name) else { return }
        library.folders.insert(name, at: min(index, library.folders.endIndex))
        let ids = Set(bookmarkIDs)
        for i in library.bookmarks.indices where ids.contains(library.bookmarks[i].id) {
            library.bookmarks[i].folder = name
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
        let needle = TextSearch.Query(query)
        guard !needle.isEmpty else { return [] }
        return library.bookmarks.filter {
            TextSearch.matches($0.title, needle)
                || TextSearch.matches($0.author, needle)
                || TextSearch.matches($0.note, needle)
                || TextSearch.matches($0.url, needle)
        }
    }

    /// Favourites are a lens, not a queue: done bookmarks stay in the list.
    public func favorites() -> [Bookmark] {
        library.bookmarks.filter(\.isFavorite)
            .sorted { ($0.favoritedAt ?? .distantPast) > ($1.favoritedAt ?? .distantPast) }
    }

    public struct Counts {
        public var byFolder: [String: Int]
        public var favorites: Int
        public var archived: Int
    }

    /// One pass over the library instead of a filter-and-sort per sidebar
    /// badge and per popover count line.
    public func counts() -> Counts {
        var byFolder: [String: Int] = [:]
        var favorites = 0
        var archived = 0
        for bookmark in library.bookmarks {
            if !bookmark.isDone { byFolder[bookmark.folder, default: 0] += 1 }
            if bookmark.isFavorite { favorites += 1 }
            if bookmark.isDone { archived += 1 }
        }
        return Counts(byFolder: byFolder, favorites: favorites, archived: archived)
    }

    /// A not-done bookmark to resurface. Filed bookmarks come before Unsorted
    /// ones, and the draw is random among the ten oldest candidates, so the
    /// longest-waiting saves come back first. The given id is excluded when
    /// another candidate exists, so "show another" never repeats itself.
    public func pick(excluding excluded: UUID? = nil) -> Bookmark? {
        let waiting = library.bookmarks.filter { !$0.isDone }
        let pool = waiting.filter { $0.id != excluded }
        let candidates = pool.isEmpty ? waiting : pool
        let filed = candidates.filter { $0.folder != Library.unsorted }
        let preferred = filed.isEmpty ? candidates : filed
        let oldest = preferred.sorted { $0.createdAt < $1.createdAt }.prefix(10)
        return oldest.randomElement()
    }

    // MARK: Persistence

    /// Encoding the whole library and rotating the backup costs about 70 ms
    /// on a 20,000 bookmark library. Done on the caller's thread that is four
    /// dropped frames for every star click, so a mutation now hands the write
    /// to `writeQueue` and returns. `onChange` still fires first and in place:
    /// the UI redraws from memory and never waits on the disk.
    private func mutated() {
        onChange?()
        scheduleWrite()
    }

    /// The newest library still to reach the disk. A burst of mutations
    /// replaces this snapshot instead of queueing one write each, so a
    /// hundred-link paste writes once, not a hundred times.
    private var pendingWrite: Library?
    private let pendingLock = NSLock()
    private let writeQueue = DispatchQueue(label: "app.dogear.library-write", qos: .utility)

    private func scheduleWrite() {
        pendingLock.lock()
        let alreadyQueued = pendingWrite != nil
        pendingWrite = library
        pendingLock.unlock()
        // A queued write has not read its snapshot yet, so it will pick up the
        // one just stored. Only an empty queue needs a new job.
        guard !alreadyQueued else { return }
        writeQueue.async { [weak self] in self?.drainPendingWrite() }
    }

    private func drainPendingWrite() {
        pendingLock.lock()
        let snapshot = pendingWrite
        pendingWrite = nil
        pendingLock.unlock()
        guard let snapshot else { return }
        write(snapshot)
    }

    /// Blocks until every scheduled write has reached the disk. Call it before
    /// the app quits, and from a test that reopens the store.
    ///
    /// ponytail: a crash or a force quit can still lose the changes made in
    /// the last few milliseconds. A write-ahead log would close that window;
    /// a menu bar app that saves links does not need one.
    public func flush() {
        writeQueue.sync { self.drainPendingWrite() }
    }

    /// Writes the library now and waits for it. Every write goes through
    /// `writeQueue`, including this one: two threads writing `library.json` at
    /// once could land the older snapshot last.
    public func saveNow() {
        scheduleWrite()
        flush()
    }

    private func write(_ snapshot: Library) {
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            report(error)
            return
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            report(error)
        }
    }

    /// A failed write reports on the main thread whoever noticed it, so the
    /// handler can touch the UI without a hop of its own.
    private func report(_ error: Error) {
        guard let onWriteFailure else { return }
        if Thread.isMainThread {
            onWriteFailure(error)
        } else {
            DispatchQueue.main.async { onWriteFailure(error) }
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
