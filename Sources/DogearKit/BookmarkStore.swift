import Foundation
import Synchronization

enum DuplicatePolicy {
    case resave
    case skip
}

struct Added {
    var new: [Bookmark] = []
    var existing: [Bookmark] = []
}

/// Read and written only on the store's write queue, or in `init` before the first write.
private final class LastWritten: @unchecked Sendable {
    var data: Data?
}

public final class BookmarkStore {
    public private(set) var library: Library {
        didSet { searchTexts = nil }
    }
    public private(set) var didRecoverFromBackup = false
    public var onChange: (() -> Void)?
    public var onWriteFailure: ((Error) -> Void)?

    /// The lowercased NFC bytes of each bookmark, in library order. A keystroke then allocates nothing per bookmark.
    private var searchTexts: [[UInt8]]?
    private let fileURL: URL
    private let backupURL: URL
    /// One write queue per library folder, so a new store waits for the writes of an old store on the same folder, and no other.
    private static let queues = Mutex<[String: DispatchQueue]>([:])
    private let writes: DispatchQueue
    /// The bytes this store wrote or loaded last. The backup is a copy of them, so a file that something else corrupted never becomes the backup.
    private let lastWritten = LastWritten()

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("library.json")
        backupURL = directory.appendingPathComponent("library.json.bak")
        writes = Self.queues.withLock { queues in
            let queue = queues[directory.standardizedFileURL.path] ?? DispatchQueue(label: "Dogear.library-writes", qos: .utility)
            queues[directory.standardizedFileURL.path] = queue
            return queue
        }
        writes.sync {}

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(Library.self, from: data) {
            library = loaded
            lastWritten.data = data
            migrate()
        } else if let data = try? Data(contentsOf: backupURL),
                  let loaded = try? JSONDecoder().decode(Library.self, from: data) {
            library = loaded
            didRecoverFromBackup = true
            if let data = try? JSONEncoder().encode(library) {
                try? data.write(to: fileURL, options: .atomic)
                lastWritten.data = data
            }
            migrate()
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            throw CocoaError(.fileReadCorruptFile)
        } else {
            library = Library(folders: Library.defaultFolders, bookmarks: [], schemaVersion: Library.currentSchemaVersion)
        }
    }

    private func migrate() {
        guard (library.schemaVersion ?? 1) < Library.currentSchemaVersion else { return }

        for folder in Library.defaultFolders where folder != Library.unsorted && !library.folders.contains(folder) {
            let index = library.folders.firstIndex(of: Library.unsorted) ?? library.folders.endIndex
            library.folders.insert(folder, at: index)
        }

        let hadCredentials = library.bookmarks.contains { URLComponents(string: $0.url).map { $0.user != nil || $0.password != nil } ?? false }
        var canonicalized: [Bookmark] = []
        var indexByURL: [String: Int] = [:]
        for var bookmark in library.bookmarks {
            // ponytail: a dropped record leaves its cached thumbnail behind.
            // The store has no reach into the thumbnail directory; sweep the
            // orphans there if that cache ever grows enough to notice.
            guard let url = URL(string: bookmark.url), URLCleaner.isCapturable(url) else { continue }
            bookmark.url = URLCleaner.canonicalString(url)
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
        // The backup still holds the old file, and with it the passwords.
        if hadCredentials {
            try? lastWritten.data?.write(to: backupURL, options: .atomic)
        }
    }

    @discardableResult
    func add(url: URL) -> (bookmark: Bookmark, isNew: Bool)? {
        let added = add(urls: [url], duplicates: .resave)
        if let bookmark = added.new.first { return (bookmark, true) }
        return added.existing.first.map { ($0, false) }
    }

    func add(urls: [URL], duplicates: DuplicatePolicy) -> Added {
        insert(urls.compactMap(webBookmark), duplicates: duplicates)
    }

    /// Saves resolved places as bookmarks in one write.
    /// A place bookmark carries its map link as its URL, so dedupe and export need no second path.
    /// The user chose the folder in the import sheet, so the record counts as filed by hand and the categorizer leaves it alone.
    /// Returns the new bookmarks. A place already saved stays as it is.
    public func add(places: [Place], to folder: String) -> [Bookmark] {
        let target = library.folders.contains(folder) ? folder : Library.unsorted
        return insert(places.compactMap { placeBookmark($0, in: target) }, duplicates: .skip).new
    }

    private func insert(_ candidates: [Bookmark], duplicates: DuplicatePolicy) -> Added {
        let positions = Dictionary(library.bookmarks.enumerated().map { ($1.url, $0) },
                                   uniquingKeysWith: { first, _ in first })
        var added = Added()
        var top: [Bookmark] = []
        var seen = Set<String>()
        var bumped = Set<UUID>()
        for candidate in candidates {
            guard seen.insert(candidate.url).inserted else { continue }
            guard let position = positions[candidate.url] else {
                added.new.append(candidate)
                top.append(candidate)
                continue
            }
            var existing = library.bookmarks[position]
            if duplicates == .resave {
                existing.doneAt = nil
                bumped.insert(existing.id)
                top.append(existing)
            }
            added.existing.append(existing)
        }
        guard !top.isEmpty else { return added }
        library.bookmarks = top + library.bookmarks.filter { !bumped.contains($0.id) }
        mutated()
        return added
    }

    private func webBookmark(for url: URL) -> Bookmark? {
        guard URLCleaner.isCapturable(url) else { return nil }
        return Bookmark(
            id: UUID(), url: URLCleaner.canonicalString(url), title: displayTitle(for: url),
            author: nil, note: nil, folder: Library.unsorted, source: .web,
            createdAt: Date(), doneAt: nil, hasThumbnail: false, manuallyFiled: false
        )
    }

    private func placeBookmark(_ place: Place, in folder: String) -> Bookmark? {
        guard let url = place.mapsURL else { return nil }
        return Bookmark(
            id: UUID(), url: URLCleaner.canonicalString(url), title: place.name,
            author: nil, note: nil, folder: folder, source: .web,
            createdAt: Date(), doneAt: nil, hasThumbnail: false, manuallyFiled: true, place: place
        )
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

    /// Marks a batch as having a thumbnail on disk, with one write. Setting
    /// the flag by id cannot clobber a rename or a refile the user made while
    /// the image was being drawn, and an id that is gone is skipped. Returns
    /// the number applied.
    @discardableResult
    public func markThumbnails(_ ids: [UUID]) -> Int {
        var applied = 0
        for id in ids {
            guard let index = library.bookmarks.firstIndex(where: { $0.id == id }),
                  !library.bookmarks[index].hasThumbnail else { continue }
            library.bookmarks[index].hasThumbnail = true
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

    public func bookmarks(in folder: String) -> [Bookmark] {
        library.bookmarks.filter { $0.folder == folder && !$0.isDone }
    }

    public func archive() -> [Bookmark] {
        library.bookmarks.filter(\.isDone)
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    public func search(_ query: String) -> [Bookmark] {
        let needle = Self.searchBytes(query)
        guard !needle.isEmpty else { return [] }
        // A NUL between fields, so a query cannot match across two of them.
        let texts = searchTexts ?? library.bookmarks.map {
            Array([$0.title, $0.author, $0.note, $0.place?.address, $0.url].compactMap { $0.map(Self.searchBytes) }.joined(separator: [0]))
        }
        searchTexts = texts
        // ponytail: bytes, not Characters. String.contains took 20 to 37 ms a keystroke at 20,000 bookmarks.
        // Both sides are NFC, so the two agree except inside a combining sequence that has no composed form.
        return zip(library.bookmarks, texts).filter { _, text in
            text.withUnsafeBytes { t in needle.withUnsafeBytes { n in memmem(t.baseAddress, t.count, n.baseAddress, n.count) != nil } }
        }.map(\.0)
    }

    /// NFC adds 23 ms at 20,000 bookmarks and changes nothing in ASCII text, so ASCII skips it. Call it once per field: one accent in a joined string sends every field down the slow path.
    private static func searchBytes(_ text: String) -> [UInt8] {
        let lowered = text.lowercased()
        return Array(lowered.utf8.allSatisfy { $0 < 0x80 } ? lowered.utf8 : lowered.precomposedStringWithCanonicalMapping.utf8)
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

    /// The next bookmark to resurface. Filed bookmarks come before Unsorted
    /// ones. Among those, one the row has never shown comes first, then the
    /// one shown longest ago, and the longest-waiting save breaks the tie.
    /// The row therefore works through the whole library before it shows
    /// anything twice. The given id is excluded when another candidate
    /// exists, so "show another" always moves on.
    public func pick(excluding excluded: UUID? = nil) -> Bookmark? {
        let waiting = library.bookmarks.filter { !$0.isDone }
        let pool = waiting.filter { $0.id != excluded }
        let candidates = pool.isEmpty ? waiting : pool
        let filed = candidates.filter { $0.folder != Library.unsorted }
        let preferred = filed.isEmpty ? candidates : filed
        return preferred.min { left, right in
            let leftShown = left.lastShownAt ?? .distantPast
            let rightShown = right.lastShownAt ?? .distantPast
            if leftShown != rightShown { return leftShown < rightShown }
            return left.createdAt < right.createdAt
        }
    }

    /// Records that the pick row showed this bookmark, so the next draw
    /// prefers one the user has not seen. This writes but does not notify:
    /// nothing on screen changes, so a redraw would be wasted work.
    public func markShown(id: UUID) {
        guard let index = library.bookmarks.firstIndex(where: { $0.id == id }) else { return }
        library.bookmarks[index].lastShownAt = Date()
        save()
    }

    private func mutated() {
        save()
        onChange?()
    }

    /// Waits until every queued write is on disk.
    public func flush() {
        writes.sync {}
    }

    /// Writes the library before it returns.
    public func saveNow() {
        save()
        flush()
    }

    /// A change copies the library here and queues the encode and the write, so a click does not wait for the disk.
    /// The queue is serial, so the file always ends at the last change.
    private func save() {
        let snapshot = library
        writes.async { [fileURL, backupURL, lastWritten, weak self] in
            do {
                let data = try JSONEncoder().encode(snapshot)
                if let previous = lastWritten.data {
                    try? previous.write(to: backupURL, options: .atomic)
                }
                try data.write(to: fileURL, options: .atomic)
                lastWritten.data = data
            } catch {
                DispatchQueue.main.async { self?.onWriteFailure?(error) }
            }
        }
    }

    func addForTesting(urlString: String, title: String? = nil, author: String? = nil, note: String? = nil) -> Bookmark {
        let bookmark = Bookmark(
            id: UUID(), url: urlString, title: title ?? urlString, author: author, note: note,
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
