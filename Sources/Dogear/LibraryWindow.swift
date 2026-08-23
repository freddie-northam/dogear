import DogearKit
import SwiftUI

struct LibraryWindow: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: String = Library.unsorted
    @State private var query = ""
    @State private var pasteFailed = false
    @State private var renamingFolder: String?
    @State private var renameDraft = ""
    @State private var renameCollided = false
    private let archiveID = "__archive__"
    private let favoritesID = "__favorites__"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label {
                        Text("Favourites")
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.pink)
                    }
                    .badge(model.store.favorites().count)
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
                        .badge(model.store.bookmarks(in: folder).count)
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
                    .badge(model.store.archive().count)
                    .tag(archiveID)
                }
            }
            .contextMenu(forSelectionType: String.self) { folders in
                if let folder = folders.first, folder != archiveID, folder != favoritesID {
                    Button("Copy as Markdown List") {
                        copyToPasteboard(Bookmark.markdownList(model.store.bookmarks(in: folder)))
                    }
                    if folder != Library.unsorted {
                        Button("Rename Folder") {
                            renameDraft = folder
                            renamingFolder = folder
                        }
                        Button("Delete Folder") {
                            model.store.removeFolder(folder)
                            selection = Library.unsorted
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                NewFolderButton()
            }
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
        .toolbar {
            Button {
                pasteFromClipboard()
            } label: {
                Image(systemName: "plus")
            }
            .help("Save from clipboard")
            .accessibilityLabel("Save from clipboard")
        }
        .alert("No Link Found", isPresented: $pasteFailed) {
            Button("OK") {}
        } message: {
            Text("The clipboard holds no web link. Dogear saves http and https links.")
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("Name", text: $renameDraft)
            Button("Save") { saveRename() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Folder Name in Use", isPresented: $renameCollided) {
            Button("OK") {}
        } message: {
            Text("A folder with this name exists.")
        }
        .alert("Storage Error", isPresented: Binding(
            get: { model.storageError != nil },
            set: { if !$0 { model.storageError = nil } }
        )) {
            Button("OK") { model.storageError = nil }
        } message: {
            Text(model.storageError ?? "")
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleBookmarks: [Bookmark] {
        if !trimmedQuery.isEmpty { return model.store.search(trimmedQuery) }
        if selection == archiveID { return model.store.archive() }
        if selection == favoritesID { return model.store.favorites() }
        return model.store.bookmarks(in: selection)
    }

    @ViewBuilder private var detailContent: some View {
        let bookmarks = visibleBookmarks
        if bookmarks.isEmpty, !trimmedQuery.isEmpty {
            ContentUnavailableView.search(text: trimmedQuery)
        } else if bookmarks.isEmpty, selection == favoritesID {
            ContentUnavailableView(
                "No favourites yet",
                systemImage: "star",
                description: Text("Hover a card and click the star.")
            )
        } else if bookmarks.isEmpty, selection == archiveID {
            ContentUnavailableView(
                "Nothing archived yet",
                systemImage: "bookmark",
                description: Text("Mark a bookmark done and it moves here.")
            )
        } else if bookmarks.isEmpty {
            ContentUnavailableView {
                Label("Nothing here yet", systemImage: "bookmark")
            } description: {
                Text("Copy a link, then click the bookmark icon in the menu bar.")
            } actions: {
                VStack(spacing: 8) {
                    Button("Paste from Clipboard", action: pasteFromClipboard)
                        .buttonStyle(.borderedProminent)
                    Text("You can paste many links at once. Copy them from Apple Notes and Dogear saves each one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            BookmarkGrid(bookmarks: bookmarks)
        }
    }

    /// The one capture path: same as the popover, fed from the clipboard.
    private func pasteFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        if model.capture(text: text).total == 0 { pasteFailed = true }
    }

    private func saveRename() {
        guard let folder = renamingFolder else { return }
        let before = model.store.library.folders
        model.store.renameFolder(folder, to: renameDraft)
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.store.library.folders != before {
            // The rename went through; keep the renamed folder selected.
            if selection == folder { selection = trimmed }
        } else if !trimmed.isEmpty, trimmed != folder {
            // Refused because another folder holds this name. An empty or
            // unchanged name closes silently: that reads as a cancel.
            renameCollided = true
        }
    }
}

func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

private struct NewFolderButton: View {
    @EnvironmentObject var model: AppModel
    @State private var isAdding = false
    @State private var name = ""
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
                .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(8)
    }

    private func cancel() {
        name = ""
        isAdding = false
    }
}

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
    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @State private var isEditingNote = false
    @State private var draftNote = ""
    @State private var isHovering = false
    @State private var showingQRCode = false

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
                        favoriteStar
                    }
                }
            Text(bookmark.title).font(.headline).lineLimit(2)
            if let note = bookmark.note, !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Text(bookmark.folder)
                    .font(.caption2)
                    .foregroundStyle(folderColor(for: bookmark.folder))
                if let author = bookmark.author {
                    Text(author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(bookmark.createdAt, format: .dateTime.day().month())
                    .font(.caption2).foregroundStyle(.tertiary)
                Text(host).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(isHovering ? .quaternary : .quinary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.5))
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { open() }
        .contextMenu { menu }
        .popover(isPresented: $showingQRCode) { qrPopover }
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

    private var qrPopover: some View {
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

    private var favoriteStar: some View {
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
        .help(bookmark.isFavorite ? "Remove from Favourites" : "Add to Favourites")
        .accessibilityLabel(bookmark.isFavorite ? "Remove from Favourites" : "Add to Favourites")
        .padding(6)
    }

    @ViewBuilder private var thumbnail: some View {
        if bookmark.hasThumbnail,
           let image = NSImage(contentsOf: model.thumbnails.fileURL(for: bookmark.id)) {
            Image(nsImage: image)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(height: 110).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(height: 110)
                .overlay(Image(systemName: "link").foregroundStyle(.tertiary))
        }
    }

    @ViewBuilder private var menu: some View {
        if bookmark.isDone {
            Button("Move Back") { model.store.markUndone(id: bookmark.id) }
        } else {
            Button("Mark Done") { model.store.markDone(id: bookmark.id) }
        }
        Button(bookmark.isFavorite ? "Remove from Favourites" : "Add to Favourites") {
            model.store.toggleFavorite(id: bookmark.id)
        }
        Menu("Move To") {
            ForEach(model.store.library.folders, id: \.self) { folder in
                Button(folder) { model.store.refile(id: bookmark.id, to: folder) }
            }
        }
        Button("Edit Title") {
            draftTitle = bookmark.title
            isEditingTitle = true
        }
        Button("Edit Note") {
            draftNote = bookmark.note ?? ""
            isEditingNote = true
        }
        Button("Copy Link") {
            copyToPasteboard(bookmark.url)
        }
        Button("Copy as Markdown") {
            copyToPasteboard(bookmark.markdownLink)
        }
        Button("Show QR Code") { showingQRCode = true }
        if bookmark.folder == "Restaurants" {
            Button("Open in Maps") { openInMaps() }
        }
        Divider()
        Button("Delete", role: .destructive) {
            model.thumbnails.remove(for: bookmark.id)
            model.store.remove(id: bookmark.id)
        }
    }

    private var host: String { URL(string: bookmark.url)?.host ?? "" }
    private func open() {
        if let url = URL(string: bookmark.url) { NSWorkspace.shared.open(url) }
    }

    private func openInMaps() {
        var parts = URLComponents(string: "https://maps.apple.com/")!
        parts.queryItems = [URLQueryItem(name: "q", value: bookmark.title)]
        if let url = parts.url { NSWorkspace.shared.open(url) }
    }
}
