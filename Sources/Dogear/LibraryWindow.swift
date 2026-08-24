import DogearKit
import SwiftUI
import UniformTypeIdentifiers

enum NotesImportState: Equatable {
    case confirm
    case running
    case finished(String)
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
    @State private var selection: String = Library.unsorted
    @State private var query = ""
    @State private var pasteFailed = false
    @State private var renameState: RenameState = .idle
    @State private var renameDraft = ""
    @State private var showingImport = false
    @State private var importState: NotesImportState = .confirm
    @State private var fileForMeResult: String?
    @State private var importFileResult: String?
    @AppStorage("libraryView") private var viewRaw = "grid"
    @AppStorage("librarySort") private var sortRaw = LibrarySort.lastSaved.rawValue
    private let archiveID = "__archive__"
    private let favoritesID = "__favorites__"

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
        .sheet(isPresented: $showingImport) {
            NotesImportSheet(state: $importState, run: runNotesImport)
        }
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

    private var sidebar: some View {
        let counts = model.store.counts()
        return List(selection: $selection) {
            Section {
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
                }
            }
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
            if let folder = folders.first, folder != archiveID, folder != favoritesID {
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
                        model.store.removeFolder(folder)
                        selection = Library.unsorted
                    } label: {
                        Label("Delete Folder", systemImage: "trash")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            NewFolderButton()
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
        return sorted(model.store.bookmarks(in: selection))
    }

    /// The sort menu applies to folder views. Favourites and Archive keep
    /// their own recency orders: they are time lenses already.
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
            return items.sorted { hostName($0) < hostName($1) }
        }
    }

    private var isFolderSelection: Bool {
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
        guard isFolderSelection else { return .none }
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

    private func runNotesImport() {
        importState = .running
        // NSAppleScript is documented main-thread-only (Apple's Thread
        // Safety Summary, Foundation framework), so this runs on the main
        // actor and blocks the UI for the duration of the Apple event.
        // ponytail: reads every note serially in one AppleScript call;
        // per-folder selection and incremental import can come later.
        let bodies = readNotesBodies()
        finishImport(with: bodies)
    }

    private func finishImport(with bodies: String?) {
        guard let bodies else {
            importState = .finished(
                "Dogear could not read Notes. Open System Settings, Privacy and Security, Automation, and allow Dogear to control Notes.")
            return
        }
        let result = model.capture(urls: URLCleaner.allHTTPURLs(inHTML: bodies))
        if result.total == 0 {
            importState = .finished("No links found in your notes.")
        } else if result.new == 0 {
            importState = .finished(result.total == 1
                ? "This link was already saved."
                : "All \(result.total) were already saved.")
        } else {
            importState = .finished(result.total == 1
                ? "Imported 1 link."
                : "Imported \(result.total) links.")
        }
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
            importFileResult = "All \(result.total) were already saved."
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

func hostName(_ bookmark: Bookmark) -> String {
    URL(string: bookmark.url)?.host ?? ""
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

/// Reads every note body over Apple events, on the main thread: NSAppleScript
/// is documented main-thread-only. Returns nil when Notes cannot be read:
/// permission denied or Notes unavailable.
private func readNotesBodies() -> String? {
    let source = "tell application \"Notes\" to get body of every note"
    var errorInfo: NSDictionary?
    guard let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo),
          errorInfo == nil else { return nil }
    // A list descriptor is 1-indexed. Zero items covers both an empty Notes
    // account and a scalar result, whose text still comes back as stringValue.
    guard descriptor.numberOfItems > 0 else { return descriptor.stringValue ?? "" }
    return (1...descriptor.numberOfItems)
        .compactMap { descriptor.atIndex($0)?.stringValue }
        .joined(separator: "\n")
}

private struct NotesImportSheet: View {
    @Binding var state: NotesImportState
    let run: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text("Import from Notes").font(.headline)
            switch state {
            case .confirm:
                Text("Dogear reads your notes on this Mac to find links. macOS asks you for permission one time. Nothing leaves your Mac.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button("Import", action: run)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            case .running:
                ProgressView("Reading your notes...")
                // Cancel cannot interrupt the in-flight Apple event (the
                // call is synchronous on the main actor); it only lets the
                // user dismiss once the event has returned.
                Button("Cancel") { state = .confirm }
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

private struct NewFolderButton: View {
    @EnvironmentObject var model: AppModel
    @State private var isAdding = false
    @State private var name = ""
    @State private var isHoveringNewFolder = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack {
            if isAdding {
                TextField("Folder name", text: $name)
                    .textFieldStyle(.roundedBorder)
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
            } else {
                Button {
                    isAdding = true
                } label: {
                    Label("New Folder", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .foregroundStyle(isHoveringNewFolder ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .onHover { isHoveringNewFolder = $0 }
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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
                model.store.markDone(id: bookmark.id)
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
            model.thumbnails.remove(for: bookmark.id)
            model.store.remove(id: bookmark.id)
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
    let bookmarks: [Bookmark]

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(bookmarks) { bookmark in
                    BookmarkCard(bookmark: bookmark)
                }
            }
            .padding(16)
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
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
                .overlay(alignment: .topTrailing) {
                    if isHovering || bookmark.isFavorite {
                        FavoriteStar(bookmark: bookmark)
                    }
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
                // The folder speaks through its symbol and color; the word,
                // the domain, and the raw link are noise at card size.
                Image(systemName: folderSymbol(for: bookmark.folder))
                    .font(.caption2)
                    .foregroundStyle(folderColor(for: bookmark.folder))
                    .help(bookmark.folder)
                    .accessibilityLabel(bookmark.folder)
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
        .onHover { isHovering = $0 }
        .pointerStyle(.link)
        .onTapGesture(count: 2) { open() }
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
            let grouped = Dictionary(grouping: bookmarks, by: hostName)
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
        HStack(spacing: 10) {
            badge
            Text(bookmark.title).lineLimit(1)
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
        .pointerStyle(.link)
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { open() }
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
