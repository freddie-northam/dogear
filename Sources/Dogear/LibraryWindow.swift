import DogearKit
import SwiftUI

struct LibraryWindow: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: String = Library.unsorted
    @State private var query = ""
    @State private var pasteFailed = false
    @State private var renamingFolder: String?
    @State private var renameDraft = ""
    private let archiveID = "__archive__"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
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
                if let folder = folders.first, folder != archiveID {
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
            BookmarkGrid(
                bookmarks: visibleBookmarks,
                isArchive: selection == archiveID,
                onPaste: pasteFromClipboard
            )
            .dropDestination(for: URL.self) { urls, _ in
                let text = urls.map(\.absoluteString).joined(separator: "\n")
                return model.capture(text: text).total > 0
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
            Button("Save") {
                guard let folder = renamingFolder else { return }
                model.store.renameFolder(folder, to: renameDraft)
                if model.store.library.folders.contains(renameDraft), selection == folder {
                    selection = renameDraft
                }
            }
            Button("Cancel", role: .cancel) {}
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

    private var visibleBookmarks: [Bookmark] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty { return model.store.search(trimmedQuery) }
        if selection == archiveID { return model.store.archive() }
        return model.store.bookmarks(in: selection)
    }

    /// The one capture path: same as the popover, fed from the clipboard.
    private func pasteFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        if model.capture(text: text).total == 0 { pasteFailed = true }
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
    @EnvironmentObject var model: AppModel
    let bookmarks: [Bookmark]
    let isArchive: Bool
    let onPaste: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16)]

    var body: some View {
        if bookmarks.isEmpty, isArchive {
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
                    Button("Paste from Clipboard", action: onPaste)
                        .buttonStyle(.borderedProminent)
                    Text("You can paste many links at once. Copy them from Apple Notes and Dogear saves each one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(bookmarks) { bookmark in
                        BookmarkCard(bookmark: bookmark, isArchive: isArchive)
                    }
                }
                .padding(16)
            }
        }
    }
}

struct BookmarkCard: View {
    @EnvironmentObject var model: AppModel
    let bookmark: Bookmark
    let isArchive: Bool
    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @State private var isEditingNote = false
    @State private var draftNote = ""
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
