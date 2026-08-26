// Cards, list rows, and the actions shared by both. Split out of
// LibraryWindow.swift, which was being edited for six unrelated reasons.
import DogearKit
import SwiftUI
import UniformTypeIdentifiers

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
        if !bookmark.isPlace {
            // A place has no page behind it; a fetch would only overwrite the
            // name the user approved.
            Button {
                let id = bookmark.id
                Task { await model.enrichment.enrich(id: id) }
            } label: {
                Label("Refresh Metadata", systemImage: "arrow.clockwise")
            }
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
        if let mapsURL = bookmark.mapsURL {
            Button {
                NSWorkspace.shared.open(mapsURL)
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
                Text(bookmark.subtitle ?? " ")
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.98))
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
                .overlay(Image(systemName: bookmark.isPlace ? "mappin.and.ellipse" : "link")
                    .foregroundStyle(.tertiary))
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
        // One click opens here too; the wide row takes a smaller give than
        // the card so the press reads the same to the eye.
        Button(action: open) {
            HStack(spacing: 10) {
                badge
                Text(bookmark.title).lineLimit(1)
                if let subtitle = bookmark.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
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
