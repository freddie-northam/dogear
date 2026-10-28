import DogearKit
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isSuggestingFolders = false
    @State private var importFileResult: String?
    @State private var isAddingPlaces = false
    @AppStorage("libraryView") private var viewRaw = "grid"
    @AppStorage("librarySort") private var sortRaw = LibrarySort.lastSaved.rawValue
    @AppStorage("notesImportSelection") private var selectionJSON = ""
    @AppStorage("notesImportCursors") private var cursorsJSON = "{}"
    private let archiveID = AppModel.archiveID
    private let favoritesID = "__favorites__"

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
                .dropDestination(for: URL.self) { urls, _ in
                    !model.capture.save(.drop(urls)).new.isEmpty
                }
        }
        .searchable(text: $query, prompt: "Search bookmarks")
        .navigationTitle("Dogear")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingWelcome) {
            WelcomeSheet(pasteFromClipboard: pasteFromClipboard, importFromNotes: startImport)
        }
        .onAppear {
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
        .sheet(isPresented: $isAddingPlaces) {
            PlacesImportSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $isSuggestingFolders) {
            FolderSuggestionSheet()
                .environmentObject(model)
        }
        .onChange(of: selectedFolderIDs) { _, ids in saveSelection(ids) }
        .onChange(of: model.spotlightRequest) { _, _ in
            guard let request = model.spotlightRequest else { return }
            selection = request.folder
            query = request.query
            model.spotlightRequest = nil
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

    private func deleteFolder(_ folder: String) {
        model.deleteFolder(folder, undoManager: undoManager)
        if selection == folder { selection = Library.unsorted }
    }

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
                    .moveDisabled(folder == Library.unsorted)
                }
                .onMove { source, destination in
                    model.store.moveFolders(fromOffsets: source, toOffset: destination)
                }
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
                    Button {
                        isSuggestingFolders = true
                    } label: {
                        Label("Suggest Folders...", systemImage: "folder.badge.plus")
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
                Button {
                    isAddingPlaces = true
                } label: {
                    Label("Add Places...", systemImage: "mappin.and.ellipse")
                }
                Divider()
                Button {
                    exportMarkdownFile()
                } label: {
                    Label("Export as Markdown...", systemImage: "square.and.arrow.up")
                }
                Button {
                    exportBookmarksFile()
                } label: {
                    Label("Export Bookmarks File...", systemImage: "square.and.arrow.up.on.square")
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuIndicator(.hidden)
            .help("Add bookmarks")
            .accessibilityLabel("Add bookmarks")
        }
    }

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

    private func pasteFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        if model.capture.save(.text(text)).found == 0 { pasteFailed = true }
    }

    private func startImport() {
        importState = .confirm
        showingImport = true
    }

    private func continueToFolders() {
        importState = .running("Finding your folders...")
        guard let folders = readNotesFolders() else {
            importState = .finished(
                "Dogear could not read Notes. Open System Settings, Privacy and Security, Automation, and allow Dogear to control Notes.")
            return
        }
        selectedFolderIDs = loadSelection(validFolderIDs: Set(folders.map(\.id)))
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
        let hadIncrementalRead = ticked.contains { cursors.secondsSince(folderID: $0.id, now: now) != nil }
        // NSAppleScript is documented main-thread-only (Apple's Thread
        // Safety Summary, Foundation framework), so each read runs on the
        // main actor and blocks the UI for the duration of its Apple event.
        for folder in ticked {
            importState = .running("Reading \(folder.name)...")
            let secondsSince = cursors.secondsSince(folderID: folder.id, now: now)
            if let body = readNotesBody(folderID: folder.id, secondsSince: secondsSince) {
                combinedBodies += body + "\n"
                cursors.record(folderID: folder.id, at: now)
            } else {
                failedFolders += 1
            }
        }
        saveCursors(cursors)
        let outcome = model.capture.save(
            .notes(html: combinedBodies, incremental: hadIncrementalRead, unreadFolders: failedFolders))
        importState = .finished(outcome.summary ?? "")
    }

    private func importBookmarksFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        importFileResult = model.capture.save(.bookmarksFile(html: html)).summary
    }

    private func exportMarkdownFile() {
        export(named: "Dogear.md",
               type: UTType(filenameExtension: "md") ?? .plainText,
               contents: MarkdownExport.export(model.store.library))
    }

    private func exportBookmarksFile() {
        export(named: "Dogear.html", type: .html,
               contents: BookmarksHTML.export(model.store.library))
    }

    private func export(named name: String, type: UTType, contents: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [type]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try contents.write(to: url, atomically: true, encoding: String.Encoding.utf8)
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

private struct NewFolderRow: View {
    @EnvironmentObject var model: AppModel
    @State private var isAdding = false
    @State private var name = ""
    @State private var isHovering = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        if isAdding {
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
