import DogearKit
import SwiftUI

private let folderSymbols: [String: String] = [
    "Recipes": "fork.knife", "Restaurants": "mappin.and.ellipse",
    "Shows": "tv", "Articles": "doc.text", "Unsorted": "tray",
]

struct LibraryWindow: View {
    @EnvironmentObject var model: AppModel
    @State private var selection: String = Library.unsorted
    @State private var query = ""
    private let archiveID = "__archive__"

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Folders") {
                    ForEach(model.store.library.folders, id: \.self) { folder in
                        Label(folder, systemImage: folderSymbols[folder] ?? "folder")
                            .badge(model.store.bookmarks(in: folder).count)
                            .tag(folder)
                    }
                }
                Section {
                    Label("Archive", systemImage: "checkmark.circle")
                        .badge(model.store.archive().count)
                        .tag(archiveID)
                }
            }
            .contextMenu(forSelectionType: String.self) { folders in
                if let folder = folders.first, folder != archiveID, folder != Library.unsorted {
                    Button("Delete Folder") { model.store.removeFolder(folder) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                NewFolderButton()
            }
        } detail: {
            BookmarkGrid(bookmarks: visibleBookmarks, isArchive: selection == archiveID)
        }
        .searchable(text: $query, prompt: "Search bookmarks")
        .navigationTitle("Dogear")
        .id(model.revision) // re-render on every store change
    }

    private var visibleBookmarks: [Bookmark] {
        if !query.isEmpty { return model.store.search(query) }
        if selection == archiveID { return model.store.archive() }
        return model.store.bookmarks(in: selection)
    }
}

private struct NewFolderButton: View {
    @EnvironmentObject var model: AppModel
    @State private var isAdding = false
    @State private var name = ""

    var body: some View {
        HStack {
            if isAdding {
                TextField("Folder name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        model.store.addFolder(name)
                        name = ""
                        isAdding = false
                    }
            } else {
                Button {
                    isAdding = true
                } label: {
                    Label("New Folder", systemImage: "plus")
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(8)
    }
}

struct BookmarkGrid: View {
    @EnvironmentObject var model: AppModel
    let bookmarks: [Bookmark]
    let isArchive: Bool

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12)]

    var body: some View {
        if bookmarks.isEmpty {
            ContentUnavailableView(
                isArchive ? "Nothing archived yet" : "Nothing here yet",
                systemImage: "bookmark",
                description: Text("Copy a link, then click the bookmark icon in the menu bar.")
            )
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(bookmarks) { bookmark in
                        BookmarkCard(bookmark: bookmark, isArchive: isArchive)
                    }
                }
                .padding(12)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail
            Text(bookmark.title).font(.headline).lineLimit(2)
            HStack {
                if let author = bookmark.author {
                    Text(author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(host).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .onTapGesture(count: 2) { open() }
        .contextMenu { menu }
        .alert("Edit Title", isPresented: $isEditingTitle) {
            TextField("Title", text: $draftTitle)
            Button("Save") {
                var updated = bookmark
                updated.title = draftTitle
                model.store.update(updated)
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
                .overlay(Image(systemName: "link").foregroundStyle(.secondary))
        }
    }

    @ViewBuilder private var menu: some View {
        if isArchive {
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
        Button("Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(bookmark.url, forType: .string)
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
}
