import AppKit
import DogearKit
import SwiftUI

struct CapturePopover: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var clipboard: ClipboardWatcher
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var hint: String?
    @State private var pick: Bookmark?
    @State private var isPickHovering = false
    // Distinct links in the field, so the button count matches what a save
    // reports. Held as state and updated per edit, not recomputed per render.
    @State private var detectedURLCount = 0
    @AppStorage("popoverListTab") private var listTab = "recents"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            captureRow
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            if let pick {
                Divider()
                pickSection(pick)
            }
            Divider()
            listSection
        }
        .padding(14)
        .frame(width: 350)
        .onAppear {
            pick = model.store.pick()
            Task { await prefill() }
        }
        .onChange(of: text) {
            detectedURLCount = Set(URLCleaner.allHTTPURLs(in: text).map(URLCleaner.canonicalString)).count
        }
        .onChange(of: model.revision) {
            // Enrichment lands title and thumbnail after the pick was rolled;
            // re-read it by id so the row updates live. A pick that was deleted
            // or marked done elsewhere rolls over to a fresh one.
            guard let id = pick?.id else { return }
            let fresh = model.store.library.bookmarks.first { $0.id == id }
            if let fresh, !fresh.isDone {
                pick = fresh
            } else {
                pick = model.store.pick(excluding: id)
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

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 18))
                .foregroundStyle(.pink)
                .accessibilityLabel("Dogear")
            Spacer()
            Button {
                openWindow(id: "library")
                dismiss()
            } label: {
                Image(systemName: "books.vertical")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Open Library")
            .accessibilityLabel("Open Library")
            Menu {
                SettingsLink {
                    Label("Settings...", systemImage: "gearshape")
                }
                .keyboardShortcut(",")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit Dogear", systemImage: "power")
                }
                .keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("More")
            .accessibilityLabel("More actions")
        }
    }

    // MARK: Capture

    private var captureRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField("Paste a link", text: $text)
                    .textFieldStyle(.plain)
                    .onSubmit(save)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            Button(detectedURLCount > 1 ? "Save \(detectedURLCount)" : "Save", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(detectedURLCount == 0)
        }
    }

    private func prefill() async {
        hint = nil
        // Check the clipboard shape first; read the content only on a positive match.
        let detected = try? await NSPasteboard.general.detectedPatterns(for: [\.links])
        guard detected?.contains(\.links) == true,
              text.isEmpty,
              let clip = clipboard.readClipboard(),
              URLCleaner.firstHTTPURL(in: clip) != nil else { return }
        text = clip
    }

    private func save() {
        let result = model.capture(text: text)
        if result.total == 0 {
            hint = "That is not a web link. Dogear saves http and https links."
            return
        }
        clipboard.consume()
        text = ""
        if pick == nil { pick = model.store.pick() }
        if result.total > 1 {
            hint = result.new == 0
                ? "All \(result.total) were already saved."
                : "Saved \(result.total) links."
        } else if result.new == 1 {
            dismiss()
        } else {
            hint = "Already saved. It moved to the top of the library."
        }
    }

    // MARK: Waiting for you

    private func pickSection(_ pick: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("WAITING FOR YOU")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.pink)
                Spacer()
                if let counts = countsLine {
                    Text(counts)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            pickRow(pick)
        }
    }

    private func pickRow(_ pick: Bookmark) -> some View {
        HStack(spacing: 8) {
            Button {
                if let url = URL(string: pick.url) { NSWorkspace.shared.open(url) }
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    pickBadge(pick)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pick.title).font(.callout).lineLimit(2)
                        Text(pick.folder)
                            .font(.caption2)
                            .foregroundStyle(folderColor(for: pick.folder))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Button {
                model.store.markDone(id: pick.id)
                self.pick = model.store.pick(excluding: pick.id)
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Mark done")
            .accessibilityLabel("Mark done")
            Button {
                self.pick = model.store.pick(excluding: pick.id)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Show another")
            .accessibilityLabel("Show another")
        }
        .padding(6)
        .background(
            .quaternary.opacity(isPickHovering ? 1 : 0),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .onHover { isPickHovering = $0 }
    }

    /// Control Center style badge: the thumbnail in a circle, or the folder
    /// symbol on a soft circle of the folder color.
    @ViewBuilder private func pickBadge(_ pick: Bookmark) -> some View {
        if pick.hasThumbnail,
           let image = NSImage(contentsOf: model.thumbnails.fileURL(for: pick.id)) {
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

    // MARK: Counts

    private var countsLine: String? {
        let parts = model.store.library.folders.compactMap { folder -> String? in
            let count = model.store.bookmarks(in: folder).count
            guard count > 0 else { return nil }
            var name = folder.lowercased()
            // ponytail: naive singularization; a folder like "Dishes" yields "1 dishe".
            if count == 1, name.hasSuffix("s") { name.removeLast() }
            return "\(count) \(name)"
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: ", ") + " waiting."
    }

    // MARK: Recents and Favourites

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("List", selection: $listTab) {
                Text("Recents").tag("recents")
                Text("Favourites").tag("favourites")
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .labelsHidden()
            .fixedSize()
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

    private var listItems: [Bookmark] {
        let items = listTab == "favourites"
            ? model.store.favorites()
            : model.store.library.bookmarks
                .filter { !$0.isDone }
                .sorted { $0.createdAt > $1.createdAt }
        return Array(items.prefix(3))
    }
}

private struct PopoverListRow: View {
    let bookmark: Bookmark
    @Environment(\.dismiss) private var dismiss
    @State private var isHovering = false

    var body: some View {
        Button {
            if let url = URL(string: bookmark.url) { NSWorkspace.shared.open(url) }
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
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
