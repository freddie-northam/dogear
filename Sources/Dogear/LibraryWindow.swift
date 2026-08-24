import DogearKit
import SwiftUI
import UniformTypeIdentifiers

enum NotesImportState: Equatable {
    case confirm
    case running(String)
    case choosing([NotesFolder])
    case finished(String)
}

/// One Notes folder, as returned by the Notes scripting dictionary: a
/// read-only id (stable across renames) and a display name.
struct NotesFolder: Identifiable, Equatable {
    let id: String
    let name: String
}

/// One alert, one state: the collision message replaces the rename prompt's
/// content in place instead of a second `.alert` firing from the first's
/// own dismissal, which SwiftUI can drop silently.
enum RenameState: Equatable {
    case idle
    case editing(folder: String)
    case collided(folder: String)
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case lastSaved
    case oldestFirst
    case title
    case site

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lastSaved: return "Last Saved"
        case .oldestFirst: return "Oldest First"
        case .title: return "Title"
        case .site: return "By Site"
        }
    }
}

struct LibraryWindow: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var folderPendingDeletion: String?
    // DOGEAR_DEMO_FOLDER picks the folder a demo launch opens on, so README
    // screenshots are reproducible. Real launches open on Unsorted, the inbox.
    @State private var selection: String =
        ProcessInfo.processInfo.environment["DOGEAR_DEMO_FOLDER"] ?? Library.unsorted
    @State private var query = ""
    @State private var pasteFailed = false
    @State private var renameState: RenameState = .idle
    @State private var renameDraft = ""
    @State private var showingImport = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showingWelcome = false
    @State private var importState: NotesImportState = .confirm
    @State private var selectedFolderIDs: Set<String> = []
    @State private var fileForMeResult: String?
    @State private var importFileResult: String?
    @AppStorage("libraryView") private var viewRaw = "grid"
    @AppStorage("librarySort") private var sortRaw = LibrarySort.lastSaved.rawValue
    @AppStorage("notesImportSelection") private var selectionJSON = ""
    @AppStorage("notesImportCursors") private var cursorsJSON = "{}"
    private let archiveID = "__archive__"
    private let favoritesID = "__favorites__"
    private let waitingID = "__waiting__"

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
                .dropDestination(for: URL.self) { urls, _ in
                    // A card dragged and released over the window must not
                    // re-add its own bookmark: that would un-archive and
                    // reorder silently. Only URLs new to the store count.
                    let existing = Set(model.store.library.bookmarks.map(\.url))
                    let fresh = urls.filter { !existing.contains(URLCleaner.canonicalString($0)) }
                    guard !fresh.isEmpty else { return false }
                    return model.capture(urls: fresh).total > 0
                }
        }
        .searchable(text: $query, prompt: "Search bookmarks")
        .navigationTitle("Dogear")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingWelcome) {
            WelcomeSheet(pasteFromClipboard: pasteFromClipboard, importFromNotes: startImport)
        }
        .onAppear {
            // Onboarding shows once, and only to an empty library: a user who
            // already has bookmarks has already learned the model.
            if !hasSeenWelcome {
                hasSeenWelcome = true
                if model.store.library.bookmarks.isEmpty { showingWelcome = true }
            }
        }
        .sheet(isPresented: $showingImport) {
            NotesImportSheet(
                state: $importState,
                selectedFolderIDs: $selectedFolderIDs,
                continueToFolders: continueToFolders,
                run: runNotesImport)
        }
        .onChange(of: selectedFolderIDs) { _, ids in saveSelection(ids) }
        .alert("No Link Found", isPresented: $pasteFailed) {
            Button("OK") {}
        } message: {
            Text("The clipboard holds no web link. Dogear saves http and https links.")
        }
        .alert(renameAlertTitle, isPresented: Binding(
            get: { renameState != .idle },
            set: { if !$0 { renameState = .idle } }
        )) {
            renameAlertActions
        } message: {
            renameAlertMessage
        }
        .alert("Storage Error", isPresented: Binding(
            get: { model.storageError != nil },
            set: { if !$0 { model.storageError = nil } }
        )) {
            Button("OK") { model.storageError = nil }
        } message: {
            Text(model.storageError ?? "")
        }
        .alert("File These for Me", isPresented: Binding(
            get: { fileForMeResult != nil },
            set: { if !$0 { fileForMeResult = nil } }
        )) {
            Button("OK") { fileForMeResult = nil }
        } message: {
            Text(fileForMeResult ?? "")
        }
        .alert("Import Bookmarks File", isPresented: Binding(
            get: { importFileResult != nil },
            set: { if !$0 { importFileResult = nil } }
        )) {
            Button("OK") { importFileResult = nil }
        } message: {
            Text(importFileResult ?? "")
        }
    }

    // MARK: Rename alert

    private var renameAlertTitle: String {
        if case .collided = renameState { return "Folder Name in Use" }
        return "Rename Folder"
    }

    @ViewBuilder private var renameAlertActions: some View {
        switch renameState {
        case .idle:
            EmptyView()
        case .editing:
            TextField("Name", text: $renameDraft)
            Button("Save") { saveRename() }
            Button("Cancel", role: .cancel) {}
        case .collided:
            Button("OK") { renameState = .idle }
        }
    }

    @ViewBuilder private var renameAlertMessage: some View {
        if case .collided = renameState {
            Text("A folder with this name exists.")
        } else {
            EmptyView()
        }
    }

    // MARK: Sidebar

    private func deleteFolder(_ folder: String) {
        model.deleteFolder(folder, undoManager: undoManager)
        if selection == folder { selection = Library.unsorted }
    }

    /// A populated folder asks before it goes. The dialog names the count and
    /// promises undo, so the choice is informed rather than alarming.
    private var folderDeletionDialog: some View {
        EmptyView().confirmationDialog(
            "Delete \"\(folderPendingDeletion ?? "")\"?",
            isPresented: Binding(
                get: { folderPendingDeletion != nil },
                set: { if !$0 { folderPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Folder", role: .destructive) {
                if let folder = folderPendingDeletion { deleteFolder(folder) }
                folderPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { folderPendingDeletion = nil }
        } message: {
            let count = folderPendingDeletion.map { model.store.counts().byFolder[$0, default: 0] } ?? 0
            Text("Its \(count) bookmark\(count == 1 ? "" : "s") move to Unsorted. You can undo this.")
        }
    }

    private var sidebar: some View {
        let counts = model.store.counts()
        return List(selection: $selection) {
            Section {
                Label {
                    Text("Waiting")
                } icon: {
                    Image(systemName: "clock")
                        .foregroundStyle(.orange)
                }
                .badge(model.store.library.bookmarks.count - counts.archived)
                .tag(waitingID)
                Label {
                    Text("Favourites")
                } icon: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.pink)
                }
                .badge(counts.favorites)
                .tag(favoritesID)
            }
            Section("Folders") {
                ForEach(model.store.library.folders, id: \.self) { folder in
                    Label {
                        Text(folder)
                    } icon: {
                        Image(systemName: folderSymbol(for: folder))
                            .foregroundStyle(folderColor(for: folder))
                    }
                    .badge(counts.byFolder[folder, default: 0])
                    .tag(folder)
                    // Unsorted is an inbox; it stays pinned last and does not drag.
                    .moveDisabled(folder == Library.unsorted)
                }
                .onMove { source, destination in
                    model.store.moveFolders(fromOffsets: source, toOffset: destination)
                }
                // The affordance to add a folder is the last row of the list it
                // adds to, like Finder and Reminders, not a control floating in
                // the window corner.
                NewFolderRow()
                    .selectionDisabled()
            }
            .background(folderDeletionDialog)
            Section {
                Label {
                    Text("Archive")
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                }
                .badge(counts.archived)
                .tag(archiveID)
            }
        }
        .contextMenu(forSelectionType: String.self) { folders in
            if let folder = folders.first,
               folder != archiveID, folder != favoritesID, folder != waitingID {
                Button {
                    copyToPasteboard(Bookmark.markdownList(model.store.bookmarks(in: folder)))
                } label: {
                    Label("Copy as Markdown List", systemImage: "doc.on.doc")
                }
                if folder == Library.unsorted {
                    Button {
                        Task {
                            let filed = await model.fileUnsorted()
                            fileForMeResult = filed > 0
                                ? "Dogear filed \(filed) bookmark\(filed == 1 ? "" : "s")."
                                : "No matches. Add folders that fit your links, then try again."
                        }
                    } label: {
                        Label("File These for Me", systemImage: "sparkles")
                    }
                }
                if folder != Library.unsorted {
                    Button {
                        renameDraft = folder
                        renameState = .editing(folder: folder)
                    } label: {
                        Label("Rename Folder", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        // A populated folder asks first; an empty one just goes,
                        // and Undo brings either back.
                        if counts.byFolder[folder, default: 0] > 0 {
                            folderPendingDeletion = folder
                        } else {
                            deleteFolder(folder)
                        }
                    } label: {
                        Label("Delete Folder", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Picker("View", selection: $viewRaw) {
                Label("Grid", systemImage: "square.grid.2x2").tag("grid")
                Label("List", systemImage: "list.bullet").tag("list")
            }
            .pickerStyle(.segmented)
            .help("View as grid or list")
            Menu {
                Picker("Sort", selection: $sortRaw) {
                    ForEach(LibrarySort.allCases) { sort in
                        Text(sort.label).tag(sort.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .help("Sort")
            .accessibilityLabel("Sort")
            .disabled(!supportsGrouping)
            Menu {
                Button {
                    pasteFromClipboard()
                } label: {
                    Label("Save from Clipboard", systemImage: "doc.on.clipboard")
                }
                Button {
                    startImport()
                } label: {
                    Label("Import from Notes...", systemImage: "square.and.arrow.down")
                }
                Button {
                    importBookmarksFile()
                } label: {
                    Label("Import Bookmarks File...", systemImage: "doc.badge.plus")
                }
                Divider()
                Button {
                    exportLibrary()
                } label: {
                    Label("Export Library...", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuIndicator(.hidden)
            .help("Add bookmarks")
            .accessibilityLabel("Add bookmarks")
        }
    }

    // MARK: Content

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sort: LibrarySort {
        LibrarySort(rawValue: sortRaw) ?? .lastSaved
    }

    private var visibleBookmarks: [Bookmark] {
        if !trimmedQuery.isEmpty { return model.store.search(trimmedQuery) }
        if selection == archiveID { return model.store.archive() }
        if selection == favoritesID { return model.store.favorites() }
        if selection == waitingID { return sorted(model.store.waiting()) }
        return sorted(model.store.bookmarks(in: selection))
    }

    /// Favourites and Archive keep their own recency orders: they are time
    /// lenses already. Waiting and folders use the selected sort.
    private func sorted(_ items: [Bookmark]) -> [Bookmark] {
        switch sort {
        case .lastSaved:
            return items
        case .oldestFirst:
            return items.sorted { $0.createdAt < $1.createdAt }
        case .title:
            return items.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .site:
            return items.sorted { siteName($0) < siteName($1) }
        }
    }

    private var supportsGrouping: Bool {
        selection != archiveID && selection != favoritesID && trimmedQuery.isEmpty
    }

    @ViewBuilder private var detailContent: some View {
        let bookmarks = visibleBookmarks
        if bookmarks.isEmpty, !trimmedQuery.isEmpty {
            ContentUnavailableView.search(text: trimmedQuery)
        } else if bookmarks.isEmpty, selection == favoritesID {
            ContentUnavailableView(
                "No favourites yet",
                systemImage: "star",
                description: Text("Point at a bookmark and click its star.")
            )
        } else if bookmarks.isEmpty, selection == archiveID {
            ContentUnavailableView(
                "Nothing archived yet",
                systemImage: "checkmark.circle",
                description: Text("Mark a bookmark done and it moves here.")
            )
        } else if bookmarks.isEmpty, selection == waitingID {
            ContentUnavailableView(
                "Nothing waiting",
                systemImage: "checkmark.circle",
                description: Text("New bookmarks appear here until you mark them done.")
            )
        } else if bookmarks.isEmpty, model.store.library.bookmarks.isEmpty {
            firstRunEmptyState
        } else if bookmarks.isEmpty {
            // The folder is empty but the library is not: no capture pitch,
            // just the folder speaking in its own color.
            ContentUnavailableView {
                Label {
                    Text("No \(selection.lowercased()) yet")
                } icon: {
                    Image(systemName: folderSymbol(for: selection))
                        .foregroundStyle(folderColor(for: selection))
                }
            } description: {
                Text("Move a bookmark here, or let Dogear file one for you.")
            }
        } else if viewRaw == "list" {
            BookmarkList(bookmarks: bookmarks, grouping: listGrouping)
        } else {
            BookmarkGrid(bookmarks: bookmarks)
        }
    }

    private var listGrouping: BookmarkList.Grouping {
        guard supportsGrouping else { return .none }
        switch sort {
        case .lastSaved: return .date
        case .site: return .site
        case .oldestFirst, .title: return .none
        }
    }

    private var firstRunEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bookmark")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("Nothing here yet")
                .font(.title3.weight(.semibold))
            Text("Copy a link, then click the bookmark icon in the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Paste from Clipboard", action: pasteFromClipboard)
                    .buttonStyle(.borderedProminent)
                Button("Import from Notes...") { startImport() }
                    .buttonStyle(.bordered)
            }
            Text("Paste many links at once. Dogear saves each one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Actions

    /// The one capture path: same as the popover, fed from the clipboard.
    private func pasteFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        if model.capture(text: text).total == 0 { pasteFailed = true }
    }

    private func startImport() {
        importState = .confirm
        showingImport = true
    }

    /// Consent step: list folders before any note body is read. A nil result
    /// means Notes denied the Apple event outright.
    private func continueToFolders() {
        importState = .running("Finding your folders...")
        guard let folders = readNotesFolders() else {
            importState = .finished(
                "Dogear could not read Notes. Open System Settings, Privacy and Security, Automation, and allow Dogear to control Notes.")
            return
        }
        selectedFolderIDs = loadSelection(validFolderIDs: Set(folders.map(\.id)))
        // Cursors for folders that no longer exist (deleted or renamed away)
        // are dead weight; drop them against the folder list we just read.
        var cursors = loadCursors()
        cursors.prune(keeping: Set(folders.map(\.id)))
        saveCursors(cursors)
        importState = .choosing(folders)
    }

    private func loadSelection(validFolderIDs: Set<String>) -> Set<String> {
        guard !selectionJSON.isEmpty,
              let data = selectionJSON.data(using: .utf8),
              let saved = try? JSONDecoder().decode([String].self, from: data)
        else { return validFolderIDs }
        return Set(saved).intersection(validFolderIDs)
    }

    private func saveSelection(_ ids: Set<String>) {
        guard let data = try? JSONEncoder().encode(Array(ids)),
              let json = String(data: data, encoding: .utf8) else { return }
        selectionJSON = json
    }

    private func loadCursors() -> NotesImportCursors {
        guard let data = cursorsJSON.data(using: .utf8),
              let cursors = try? JSONDecoder().decode(NotesImportCursors.self, from: data)
        else { return NotesImportCursors() }
        return cursors
    }

    private func saveCursors(_ cursors: NotesImportCursors) {
        guard let data = try? JSONEncoder().encode(cursors),
              let json = String(data: data, encoding: .utf8) else { return }
        cursorsJSON = json
    }

    private func runNotesImport() {
        guard case .choosing(let folders) = importState else { return }
        let ticked = folders.filter { selectedFolderIDs.contains($0.id) }
        var cursors = loadCursors()
        var combinedBodies = ""
        var failedFolders = 0
        let now = Date()
        // Checked before the loop records any new cursor, so this reflects
        // whether the read was incremental (a cursor already existed), not
        // whether this run happened to succeed.
        let hadIncrementalRead = ticked.contains { cursors.secondsSince(folderID: $0.id, now: now) != nil }
        // NSAppleScript is documented main-thread-only (Apple's Thread
        // Safety Summary, Foundation framework), so each read runs on the
        // main actor and blocks the UI for the duration of its Apple event.
        for folder in ticked {
            importState = .running("Reading \(folder.name)...")
            let secondsSince = cursors.secondsSince(folderID: folder.id, now: now)
            if let body = readNotesBody(folderID: folder.id, secondsSince: secondsSince) {
                combinedBodies += body + "\n"
                // Recorded only on success: a failed folder keeps its old
                // cursor and is re-read in full (or from its old cursor) next time.
                cursors.record(folderID: folder.id, at: now)
            } else {
                failedFolders += 1
            }
        }
        saveCursors(cursors)
        finishImport(with: combinedBodies, failedFolders: failedFolders, hadIncrementalRead: hadIncrementalRead)
    }

    private func finishImport(with bodies: String, failedFolders: Int, hadIncrementalRead: Bool) {
        let existing = Set(model.store.library.bookmarks.map(\.url))
        let found = URLCleaner.allHTTPURLs(inHTML: bodies)
        let fresh = NotesImportPlanning.freshURLs(found, existing: existing)
        var message: String
        if found.isEmpty {
            message = hadIncrementalRead
                ? "No new links since your last import."
                : "No links found in your notes."
        } else if fresh.isEmpty {
            message = found.count == 1
                ? "All 1 link was already saved."
                : "All \(found.count) links were already saved."
        } else {
            let result = model.capture(urls: fresh)
            let alreadySaved = found.count - result.new
            message = result.new == 1 ? "Imported 1 link." : "Imported \(result.new) links."
            if alreadySaved > 0 {
                message += alreadySaved == 1
                    ? " 1 was already saved."
                    : " \(alreadySaved) were already saved."
            }
        }
        if failedFolders > 0 {
            message += failedFolders == 1
                ? " Dogear could not read 1 folder."
                : " Dogear could not read \(failedFolders) folders."
        }
        importState = .finished(message)
    }

    private func importBookmarksFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html: String
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            html = text
        } else if let data = try? Data(contentsOf: url) {
            html = String(decoding: data, as: UTF8.self)
        } else {
            importFileResult = "No links found in that file."
            return
        }
        let result = model.capture(urls: URLCleaner.allHTTPURLs(inHTML: html))
        if result.total == 0 {
            importFileResult = "No links found in that file."
        } else if result.new == 0 {
            importFileResult = result.total == 1
                ? "This link was already saved."
                : "All \(result.total) were already saved."
        } else {
            importFileResult = result.new == 1
                ? "Imported 1 link."
                : "Imported \(result.new) links."
        }
    }

    private func exportLibrary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Dogear.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let markdown = exportMarkdown(model.store.library)
        do {
            try markdown.write(to: url, atomically: true, encoding: String.Encoding.utf8)
        } catch {
            model.storageError = "Dogear could not export your bookmarks: \(error.localizedDescription)"
        }
    }

    private func saveRename() {
        guard case .editing(let folder) = renameState else { return }
        let before = model.store.library.folders
        model.store.renameFolder(folder, to: renameDraft)
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.store.library.folders != before {
            // The rename went through; keep the renamed folder selected.
            if selection == folder { selection = trimmed }
            renameState = .idle
        } else if !trimmed.isEmpty, trimmed != folder {
            // Refused because another folder holds this name. The Save
            // action runs before SwiftUI writes isPresented back to false
            // (that write reaches our setter after this closure returns and
            // would immediately idle a `.collided` set here), so defer the
            // transition to the next run loop turn. That reads as a clean
            // dismiss-then-represent of this same alert, not a second one.
            DispatchQueue.main.async { renameState = .collided(folder: folder) }
        } else {
            // Empty or unchanged name: that reads as a cancel.
            renameState = .idle
        }
    }
}

func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

/// The one place a stored URL becomes a system open. Refuses anything that
/// is not http(s): NSWorkspace dispatches any scheme to whichever app
/// claims it, and stored data must not carry that authority.
func openBookmarkURL(_ string: String) {
    guard let url = URL(string: string), URLCleaner.isCapturable(url) else { return }
    NSWorkspace.shared.open(url)
}

func displayHost(_ bookmark: Bookmark) -> String {
    URL(string: bookmark.url).map(URLCleaner.displayHost) ?? "Other"
}

func siteName(_ bookmark: Bookmark) -> String {
    URL(string: bookmark.url).map(URLCleaner.siteName) ?? "Other"
}

/// A markdown export of the whole library: one `## <Folder>` section per
/// non-empty folder, in `library.folders` order, then an `## Archive`
/// section for done bookmarks if any exist.
private func exportMarkdown(_ library: Library) -> String {
    var sections: [String] = []
    for folder in library.folders {
        let items = library.bookmarks.filter { $0.folder == folder && !$0.isDone }
        guard !items.isEmpty else { continue }
        sections.append("## \(folder)\n\n\(Bookmark.markdownList(items))")
    }
    let archived = library.bookmarks.filter(\.isDone)
    if !archived.isEmpty {
        sections.append("## Archive\n\n\(Bookmark.markdownList(archived))")
    }
    return sections.joined(separator: "\n\n")
}

/// Lists every Notes folder across every account, on the main thread:
/// NSAppleScript is documented main-thread-only. This is the first Apple
/// event of an import, so it is also the consent trigger. Returns nil when
/// Notes cannot be read: permission denied or Notes unavailable.
private func readNotesFolders() -> [NotesFolder]? {
    let source = "tell application \"Notes\" to get {id of every folder, name of every folder}"
    var errorInfo: NSDictionary?
    guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo),
          errorInfo == nil,
          descriptor.numberOfItems == 2,
          let ids = descriptor.atIndex(1),
          let names = descriptor.atIndex(2),
          ids.numberOfItems == names.numberOfItems else { return nil }
    let count = ids.numberOfItems
    guard count > 0 else { return [] }
    return (1...count).compactMap { index -> NotesFolder? in
        guard let id = ids.atIndex(index)?.stringValue,
              let name = names.atIndex(index)?.stringValue else { return nil }
        return NotesFolder(id: id, name: name)
    }
}

/// Reads every non-password-protected note body in one folder, over Apple
/// events, on the main thread. When `secondsSince` is given, only notes
/// modified within that many seconds of now are read (an incremental read);
/// nil means a full read. Returns nil when the folder cannot be read.
private func readNotesBody(folderID: String, secondsSince: Int?) -> String? {
    let escapedID = folderID
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    var whose = "password protected is false"
    var cutoffLine = ""
    if let secondsSince {
        cutoffLine = "set cutoff to (current date) - \(secondsSince)\n"
        whose += " and modification date > cutoff"
    }
    let source = "tell application \"Notes\"\n" +
        "set f to first folder whose id is \"\(escapedID)\"\n" +
        cutoffLine +
        "get body of every note of f whose \(whose)\n" +
        "end tell"
    var errorInfo: NSDictionary?
    guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo),
          errorInfo == nil else { return nil }
    // A list descriptor is 1-indexed. Zero items covers both an empty folder
    // and a scalar result, whose text still comes back as stringValue.
    guard descriptor.numberOfItems > 0 else { return descriptor.stringValue ?? "" }
    return (1...descriptor.numberOfItems)
        .compactMap { descriptor.atIndex($0)?.stringValue }
        .joined(separator: "\n")
}

private struct NotesImportSheet: View {
    @Binding var state: NotesImportState
    @Binding var selectedFolderIDs: Set<String>
    let continueToFolders: () -> Void
    let run: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var title: String {
        if case .choosing = state { return "Which folders?" }
        return "Import from Notes"
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.headline)
            switch state {
            case .confirm:
                Text("Dogear reads your notes on this Mac to find links. macOS asks you for permission one time. Nothing leaves your Mac.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button("Continue", action: continueToFolders)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            case .running(let label):
                ProgressView(label)
                // Cancel cannot interrupt the in-flight Apple event (the
                // call is synchronous on the main actor); it only lets the
                // user dismiss once the event has returned.
                Button("Cancel") { state = .confirm }
            case .choosing(let folders):
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(folders) { folder in
                            Toggle(folder.name, isOn: Binding(
                                get: { selectedFolderIDs.contains(folder.id) },
                                set: { isOn in
                                    if isOn { selectedFolderIDs.insert(folder.id) }
                                    else { selectedFolderIDs.remove(folder.id) }
                                }
                            ))
                        }
                    }
                }
                .frame(maxHeight: 220)
                HStack {
                    Button("Select all") { selectedFolderIDs = Set(folders.map(\.id)) }
                    Button("Select none") { selectedFolderIDs = [] }
                    Spacer()
                }
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button("Import", action: run)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedFolderIDs.isEmpty)
                }
            case .finished(let message):
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

private struct NewFolderRow: View {
    @EnvironmentObject var model: AppModel
    @State private var isAdding = false
    @State private var name = ""
    @State private var isHovering = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        if isAdding {
            // Same icon column and text inset as a folder row, so the field
            // reads as "this row is becoming a folder", not as a form.
            Label {
                TextField("Folder name", text: $name)
                    .textFieldStyle(.plain)
                    .focused($isFieldFocused)
                    .onSubmit {
                        model.store.addFolder(name)
                        cancel()
                    }
                    .onExitCommand { cancel() }
                    .onChange(of: isFieldFocused) { _, focused in
                        if !focused { cancel() }
                    }
                    .onAppear { isFieldFocused = true }
            } icon: {
                Image(systemName: "folder.badge.plus")
                    .foregroundStyle(.secondary)
            }
        } else {
            Button {
                isAdding = true
            } label: {
                Label {
                    Text("New Folder")
                } icon: {
                    Image(systemName: "plus.circle")
                }
                .foregroundStyle(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { isHovering = $0 }
            .accessibilityLabel("New Folder")
        }
    }

    private func cancel() {
        name = ""
        isAdding = false
    }
}

// MARK: - Shared bookmark actions

/// The context menu, edit alerts, and QR popover that every bookmark
/// presentation shares, so the grid card and the list row behave the same.
struct BookmarkActions: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Environment(\.undoManager) private var undoManager
    let bookmark: Bookmark
    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @State private var isEditingNote = false
    @State private var draftNote = ""
    @State private var showingQRCode = false

    func body(content: Content) -> some View {
        content
            .contextMenu { menu }
            .popover(isPresented: $showingQRCode) { QRPopover(bookmark: bookmark) }
            .alert("Edit Title", isPresented: $isEditingTitle) {
                TextField("Title", text: $draftTitle)
                Button("Save") {
                    if var current = model.store.library.bookmarks.first(where: { $0.id == bookmark.id }) {
                        current.title = draftTitle
                        model.store.update(current)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Edit Note", isPresented: $isEditingNote) {
                TextField("Note", text: $draftNote)
                Button("Save") {
                    if var current = model.store.library.bookmarks.first(where: { $0.id == bookmark.id }) {
                        current.note = draftNote.isEmpty ? nil : draftNote
                        model.store.update(current)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
    }

    @ViewBuilder private var menu: some View {
        if bookmark.isDone {
            Button {
                model.store.markUndone(id: bookmark.id)
            } label: {
                Label("Move Back", systemImage: "arrow.uturn.backward")
            }
        } else {
            Button {
                model.markDone(bookmark.id, undoManager: undoManager)
            } label: {
                Label("Mark Done", systemImage: "checkmark.circle")
            }
        }
        Button {
            model.store.toggleFavorite(id: bookmark.id)
        } label: {
            Label(
                bookmark.isFavorite ? "Remove from Favourites" : "Add to Favourites",
                systemImage: bookmark.isFavorite ? "star.slash" : "star"
            )
        }
        Menu {
            ForEach(model.store.library.folders, id: \.self) { folder in
                Button(folder) { model.store.refile(id: bookmark.id, to: folder) }
            }
        } label: {
            Label("Move To", systemImage: "folder")
        }
        Divider()
        Button {
            draftTitle = bookmark.title
            isEditingTitle = true
        } label: {
            Label("Edit Title", systemImage: "pencil")
        }
        Button {
            draftNote = bookmark.note ?? ""
            isEditingNote = true
        } label: {
            Label("Edit Note", systemImage: "note.text")
        }
        Button {
            let id = bookmark.id
            Task { await model.enrichment.enrich(id: id) }
        } label: {
            Label("Refresh Metadata", systemImage: "arrow.clockwise")
        }
        Divider()
        Button {
            copyToPasteboard(bookmark.url)
        } label: {
            Label("Copy Link", systemImage: "link")
        }
        Button {
            copyToPasteboard(bookmark.markdownLink)
        } label: {
            Label("Copy as Markdown", systemImage: "doc.on.doc")
        }
        Button {
            showingQRCode = true
        } label: {
            Label("Show QR Code", systemImage: "qrcode")
        }
        if bookmark.folder == "Restaurants" {
            Button {
                openInMaps()
            } label: {
                Label("Open in Maps", systemImage: "map")
            }
        }
        Divider()
        Button(role: .destructive) {
            model.deleteBookmark(bookmark, undoManager: undoManager)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func openInMaps() {
        var parts = URLComponents(string: "https://maps.apple.com/")!
        parts.queryItems = [URLQueryItem(name: "q", value: bookmark.title)]
        if let url = parts.url { NSWorkspace.shared.open(url) }
    }
}

extension View {
    func bookmarkActions(_ bookmark: Bookmark) -> some View {
        modifier(BookmarkActions(bookmark: bookmark))
    }
}

private struct QRPopover: View {
    let bookmark: Bookmark

    var body: some View {
        VStack(spacing: 8) {
            Text(bookmark.title).font(.headline).lineLimit(1)
            if let qr = QRCode.image(for: bookmark.url) {
                Image(qr, scale: 1, label: Text("QR code for \(bookmark.title)"))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 180, height: 180)
                    .padding(8)
                    // A QR code needs a light background to scan, in dark
                    // mode too, so this white is deliberate.
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Dogear could not make a QR code for this link.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Scan with your iPhone camera.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 220)
    }
}

// MARK: - Grid

struct BookmarkGrid: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Read here so a sort change animates the reorder. Folder clicks and
    // search keystrokes replace the whole list and must stay hard cuts, so
    // the grid does not key its animation on the bookmark ids.
    @AppStorage("librarySort") private var sortRaw = LibrarySort.lastSaved.rawValue
    let bookmarks: [Bookmark]

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(bookmarks) { bookmark in
                    BookmarkCard(bookmark: bookmark)
                        // A card that is marked done or deleted leaves toward the
                        // sidebar, where Archive lives, so the motion says where
                        // it went. A card that arrives grows into place; it did
                        // not come from the sidebar. Reduced motion keeps the
                        // fade only.
                        .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity.combined(with: .move(edge: .leading))))
                }
            }
            .padding(16)
            .animation(Motion.shuffle, value: sortRaw)
        }
    }
}

struct BookmarkCard: View {
    @EnvironmentObject var model: AppModel
    let bookmark: Bookmark
    @State private var isHovering = false

    var body: some View {
        if let url = URL(string: bookmark.url) {
            card.draggable(url)
        } else {
            card
        }
    }

    private var card: some View {
        // One click opens, the same as the popover rows: a card is a button.
        // The shared style gives the press its feel on pointer-down, and the
        // star is a button of its own inside the label, so it wins its own
        // clicks.
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                thumbnail
                    .overlay(alignment: .topTrailing) {
                        FavoriteStar(bookmark: bookmark)
                            .opacity(isHovering || bookmark.isFavorite ? 1 : 0)
                    }
                Text(bookmark.title)
                    .font(.headline)
                    .lineLimit(2, reservesSpace: true)
                // The note line always reserves its height, so every card in a
                // row is the same size whether or not a note exists.
                Text(bookmark.note ?? " ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1, reservesSpace: true)
                HStack(spacing: 6) {
                    // Keep the folder compact, but show the destination host:
                    // fetched titles, authors, and images are not identity.
                    Image(systemName: folderSymbol(for: bookmark.folder))
                        .font(.caption2)
                        .foregroundStyle(folderColor(for: bookmark.folder))
                        .help(bookmark.folder)
                        .accessibilityLabel(bookmark.folder)
                    Text(displayHost(bookmark))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let author = bookmark.author {
                        Text(author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(bookmark.createdAt, format: .dateTime.day().month())
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .background(isHovering ? .quaternary : .quinary, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.98))
        .accessibilityLabel("\(bookmark.title), \(displayHost(bookmark))")
        .animation(Motion.hover, value: isHovering)
        .onHover { isHovering = $0 }
        .pointerStyle(.link)
        .bookmarkActions(bookmark)
    }

    @ViewBuilder private var thumbnail: some View {
        if bookmark.hasThumbnail,
           let image = model.thumbnails.image(for: bookmark.id) {
            Image(nsImage: image)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(height: 110)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if bookmark.source == .x {
            // A text post reads as a quote, not as a missing image.
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(height: 110)
                .overlay(
                    Image(systemName: "quote.opening")
                        .font(.title3)
                        .foregroundStyle(folderColor(for: bookmark.folder))
                )
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(height: 110)
                .overlay(Image(systemName: "link").foregroundStyle(.tertiary))
        }
    }

    private func open() {
        openBookmarkURL(bookmark.url)
    }
}

struct FavoriteStar: View {
    @EnvironmentObject var model: AppModel
    let bookmark: Bookmark

    var body: some View {
        Button {
            model.store.toggleFavorite(id: bookmark.id)
        } label: {
            Image(systemName: bookmark.isFavorite ? "star.fill" : "star")
                .font(.caption)
                .foregroundStyle(.pink)
                .padding(4)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.borderless)
        .pointerStyle(.link)
        .help(bookmark.isFavorite ? "Remove from Favourites" : "Add to Favourites")
        .accessibilityLabel(bookmark.isFavorite ? "Remove from Favourites" : "Add to Favourites")
        .padding(6)
    }
}

// MARK: - List

struct BookmarkList: View {
    enum Grouping {
        case none
        case date
        case site
    }

    let bookmarks: [Bookmark]
    let grouping: Grouping

    var body: some View {
        List {
            ForEach(groups, id: \.title) { group in
                if let title = group.title {
                    Section(title) {
                        rows(group.items)
                    }
                } else {
                    rows(group.items)
                }
            }
        }
        .listStyle(.inset)
    }

    private func rows(_ items: [Bookmark]) -> some View {
        ForEach(items) { bookmark in
            BookmarkListRow(bookmark: bookmark)
        }
    }

    private var groups: [(title: String?, items: [Bookmark])] {
        switch grouping {
        case .none:
            return [(nil, bookmarks)]
        case .site:
            let grouped = Dictionary(grouping: bookmarks, by: siteName)
            return grouped.keys.sorted().map { ($0.isEmpty ? "Other" : $0, grouped[$0] ?? []) }
        case .date:
            return dateGroups
        }
    }

    /// Finder-style recency sections.
    private var dateGroups: [(title: String?, items: [Bookmark])] {
        let calendar = Calendar.current
        let now = Date()
        var buckets: [(String, [Bookmark])] = [
            ("Today", []), ("Yesterday", []), ("Previous 7 Days", []),
            ("Previous 30 Days", []), ("Older", []),
        ]
        for bookmark in bookmarks {
            let date = bookmark.createdAt
            let index: Int
            if calendar.isDateInToday(date) {
                index = 0
            } else if calendar.isDateInYesterday(date) {
                index = 1
            } else if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
                index = 2
            } else if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 30 {
                index = 3
            } else {
                index = 4
            }
            buckets[index].1.append(bookmark)
        }
        return buckets.filter { !$0.1.isEmpty }.map { ($0.0, $0.1) }
    }
}

struct BookmarkListRow: View {
    @EnvironmentObject var model: AppModel
    let bookmark: Bookmark
    @State private var isHovering = false

    var body: some View {
        // One click opens here too; the wide row takes a smaller give than
        // the card so the press reads the same to the eye.
        Button(action: open) {
            HStack(spacing: 10) {
                badge
                Text(bookmark.title).lineLimit(1)
                Text(displayHost(bookmark))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let note = bookmark.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 8)
                if bookmark.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                }
                Text(bookmark.createdAt, format: .dateTime.day().month())
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(isHovering ? 0.6 : 0), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.99))
        .accessibilityLabel("\(bookmark.title), \(displayHost(bookmark))")
        .pointerStyle(.link)
        .onHover { isHovering = $0 }
        .bookmarkActions(bookmark)
        .draggable(URL(string: bookmark.url) ?? URL(fileURLWithPath: "/"))
    }

    @ViewBuilder private var badge: some View {
        if bookmark.hasThumbnail,
           let image = model.thumbnails.image(for: bookmark.id) {
            Image(nsImage: image)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Circle()
                .fill(folderColor(for: bookmark.folder).opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: bookmark.source == .x ? "quote.opening" : folderSymbol(for: bookmark.folder))
                        .font(.system(size: 10))
                        .foregroundStyle(folderColor(for: bookmark.folder))
                )
        }
    }

    private func open() {
        openBookmarkURL(bookmark.url)
    }
}
