import AppKit
import DogearKit
import SwiftUI

struct CapturePopover: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var clipboard: ClipboardWatcher
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var text = ""
    @State private var hint: String?
    @State private var pick: Bookmark?
    @State private var pickFolder: String?
    @State private var isPickHovering = false
    @State private var detectedURLCount = 0
    @AppStorage("popoverListTab") private var listTab = "recents"
    @State private var isHoveringMore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            captureRow
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            if let pick {
                Divider()
                pickSection(pick)
            }
            if model.store.library.bookmarks.isEmpty {
                Text("Copy a link to get started.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                listSection
            }
        }
        .padding(14)
        .frame(width: 350)
        .animation(Motion.reveal, value: hint)
        .onAppear {
            pickFolder = nil
            rollPick()
            Task { await prefill() }
        }
        .onChange(of: text) {
            detectedURLCount = Set(URLCleaner.allHTTPURLs(in: text).map(URLCleaner.canonicalString)).count
        }
        .onChange(of: model.revision) {
            guard let id = pick?.id else { return }
            let fresh = model.store.library.bookmarks.first { $0.id == id }
            if let fresh, !fresh.isDone {
                pick = fresh
            } else {
                rollPick(excluding: id)
            }
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

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.pink)
                Text("Dogear")
                    .font(.headline)
            }
            .accessibilityLabel("Dogear")
            Spacer()
            // One menu, three line items, each with a real icon. SwiftUI drops
            // SF Symbols from menu rows on macOS unless the image is built as
            // an NSImage first; the Label helper below does that.
            Menu {
                Button {
                    openWindow(id: "library")
                    dismiss()
                } label: {
                    menuLabel("Open Library", symbol: "square.grid.2x2")
                }
                .keyboardShortcut("l")
                SettingsLink {
                    menuLabel("Settings...", symbol: "gearshape")
                }
                .keyboardShortcut(",")
                Divider()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    menuLabel("Quit Dogear", symbol: "power")
                }
                .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isHoveringMore ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .frame(width: 22, height: 22)
                    .background(.quaternary.opacity(isHoveringMore ? 1 : 0), in: Circle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .onHover { isHoveringMore = $0 }
            .animation(Motion.hover, value: isHoveringMore)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More actions")
        }
    }

    private func menuLabel(_ title: String, symbol: String) -> some View {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        return Label {
            Text(title)
        } icon: {
            if let image {
                Image(nsImage: image)
            } else {
                Image(systemName: symbol)
            }
        }
    }

    private var captureRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            TextField("Paste a link", text: $text)
                .textFieldStyle(.plain)
                .onSubmit(save)
            if detectedURLCount > 0 {
                HStack(spacing: 4) {
                    if detectedURLCount > 1 {
                        Text("\(detectedURLCount)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    Image(systemName: "return")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.9)))
                .accessibilityLabel(detectedURLCount > 1
                    ? "Press Return to save \(detectedURLCount) links"
                    : "Press Return to save")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .animation(Motion.hover, value: detectedURLCount > 0)
    }

    private func prefill() async {
        hint = nil
        guard text.isEmpty, let clip = await clipboard.readLink(),
              URLCleaner.firstHTTPURL(in: clip) != nil else { return }
        text = clip
    }

    private func save() {
        let outcome = model.capture.save(.text(text))
        hint = outcome.summary
        guard outcome.found > 0 else { return }
        clipboard.consume()
        text = ""
        if pick == nil { rollPick() }
        if outcome.savedOneNewLink { dismiss() }
    }

    private func rollPick(excluding excluded: UUID? = nil) {
        var next = model.store.pick(excluding: excluded, in: pickFolder)
        // The chosen folder ran out, so fall back to every folder rather than show an empty row.
        if next == nil, pickFolder != nil {
            pickFolder = nil
            next = model.store.pick(excluding: excluded)
        }
        if let next { model.store.markShown(id: next.id) }
        pick = next
    }

    private func pickSection(_ pick: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("WAITING FOR YOU")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.pink)
                Spacer()
                countsRow
            }
            pickRow(pick)
                .id(pick.id)
                .transition(.opacity)
        }
    }

    private func pickRow(_ pick: Bookmark) -> some View {
        HStack(spacing: 8) {
            Button {
                openBookmarkURL(pick.url)
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    pickBadge(pick)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pick.title).font(.callout).lineLimit(2)
                        HStack(spacing: 4) {
                            Image(systemName: folderSymbol(for: pick.folder))
                                .font(.system(size: 9))
                            Text(pick.folder)
                        }
                        .font(.caption2)
                        .foregroundStyle(folderColor(for: pick.folder))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.98))
            .pointerStyle(.link)
            Spacer(minLength: 8)
            if isPickHovering {
                HoverIconButton(symbol: "checkmark", label: "Mark done", hoverColor: .green) {
                    withAnimation(Motion.reveal) {
                        model.markDone(pick.id, undoManager: undoManager)
                        rollPick(excluding: pick.id)
                    }
                }
                HoverIconButton(symbol: "arrow.clockwise", label: "Show another", hoverColor: .primary) {
                    withAnimation(Motion.reveal) {
                        rollPick(excluding: pick.id)
                    }
                }
            }
        }
        .padding(6)
        .background(
            .quaternary.opacity(isPickHovering ? 1 : 0),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .animation(Motion.hover, value: isPickHovering)
        .onHover { isPickHovering = $0 }
    }

    @ViewBuilder private func pickBadge(_ pick: Bookmark) -> some View {
        if pick.hasThumbnail,
           let image = model.thumbnails.image(for: pick.id) {
            Image(nsImage: image)
                .resizable().aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(folderColor(for: pick.folder).opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: folderSymbol(for: pick.folder))
                        .foregroundStyle(folderColor(for: pick.folder))
                )
        }
    }

    @ViewBuilder private var countsRow: some View {
        let counts = model.store.counts()
        let entries = countEntries(counts)
        if entries.isEmpty {
            let unsorted = counts.byFolder[Library.unsorted, default: 0]
            if unsorted > 0 {
                Text("\(unsorted) to sort.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            HStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.name) { index, entry in
                    if index > 0 { Text(", ") }
                    Button(entry.label) {
                        pickFolder = entry.name
                        withAnimation(Motion.reveal) { rollPick() }
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .foregroundStyle(entry.name == pickFolder ? AnyShapeStyle(folderColor(for: entry.name)) : AnyShapeStyle(.secondary))
                    .help("Show a waiting link from \(entry.name)")
                    .accessibilityLabel("Show a waiting link from \(entry.name)")
                }
                Text(" waiting.")
                if pickFolder != nil {
                    Button {
                        pickFolder = nil
                        withAnimation(Motion.reveal) { rollPick() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
                    .help("Show links from every folder")
                    .accessibilityLabel("Show links from every folder")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private func countEntries(_ counts: BookmarkStore.Counts) -> [(name: String, label: String)] {
        model.store.library.folders
            .filter { $0 != Library.unsorted }
            .compactMap { folder -> (name: String, count: Int)? in
                let count = counts.byFolder[folder, default: 0]
                return count > 0 ? (folder, count) : nil
            }
            .sorted { $0.count > $1.count }
            .prefix(3)
            .map { entry in
                var name = entry.name.lowercased()
                // ponytail: naive singularization; a folder like "Dishes" yields "1 dishe".
                if entry.count == 1, name.hasSuffix("s") { name.removeLast() }
                return (entry.name, "\(entry.count) \(name)")
            }
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                listTabButton("Recents", tag: "recents")
                listTabButton("Favourites", tag: "favourites")
            }
            let items = listItems
            if items.isEmpty {
                Text(listTab == "favourites"
                    ? "No favourites yet. Star a bookmark in the library."
                    : "Nothing saved yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { PopoverListRow(bookmark: $0) }
            }
        }
    }

    private func listTabButton(_ title: String, tag: String) -> some View {
        Button(title) { listTab = tag }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .font(.caption.weight(listTab == tag ? .semibold : .regular))
            .foregroundStyle(listTab == tag ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .accessibilityAddTraits(listTab == tag ? .isSelected : [])
    }

    private var listItems: [Bookmark] {
        let items = listTab == "favourites"
            ? model.store.favorites()
            : model.store.library.bookmarks.filter { !$0.isDone }
        return Array(items.prefix(3))
    }
}

private struct PopoverListRow: View {
    let bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss
    @State private var isHovering = false

    var body: some View {
        Button {
            openBookmarkURL(bookmark.url)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(folderColor(for: bookmark.folder).opacity(0.2))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: folderSymbol(for: bookmark.folder))
                            .font(.system(size: 11))
                            .foregroundStyle(folderColor(for: bookmark.folder))
                    )
                Text(bookmark.title).font(.callout).lineLimit(1)
                Spacer(minLength: 8)
                if isHovering {
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.98))
        .pointerStyle(.link)
        .onHover { isHovering = $0 }
    }
}

struct HoverIconButton: View {
    let symbol: String
    let label: String
    let hoverColor: Color
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovering ? AnyShapeStyle(hoverColor) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 24)
                .background(.quaternary.opacity(isHovering ? 1 : 0), in: Circle())
        }
        .buttonStyle(.pressable)
        .pointerStyle(.link)
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}
