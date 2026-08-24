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
    @State private var isPickHovering = false
    // Distinct links in the field, so the button count matches what a save
    // reports. Held as state and updated per edit, not recomputed per render.
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
            // An empty store gets one friendly line, not tabs over nothing.
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

    /// A menu row with an icon that macOS actually renders: an NSImage-backed
    /// symbol, sized as a menu item glyph.
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

    // MARK: Capture

    private var captureRow: some View {
        // Return saves; there is no button to duplicate it. When the field
        // holds a link (typed or prefilled from the clipboard) a quiet return
        // glyph on the trailing edge says so, with a count when it holds many.
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
        // Check the clipboard shape first; read the content only on a positive match.
        let detected = try? await NSPasteboard.general.detectedPatterns(for: [\.links])
        guard detected?.contains(\.links) == true,
              text.isEmpty,
              let clip = clipboard.readClipboard(),
              URLCleaner.firstHTTPURL(in: clip) != nil else { return }
        text = clip
    }

    private func save() {
        let urls = URLCleaner.allHTTPURLs(in: text)
        let result = model.capture(urls: urls)
        if result.total == 0 {
            hint = result.rejectedCredentials > 0
                ? "Remove the username or password from this link before saving it."
                : "That is not a web link. Dogear saves http and https links."
            return
        }
        clipboard.consume()
        text = ""
        if pick == nil { pick = model.store.pick() }
        if result.rejectedCredentials > 0 {
            let saved = result.new == 0
                ? "Valid links were already saved."
                : "Saved \(result.new) valid link\(result.new == 1 ? "" : "s")."
            hint = "\(saved) Skipped links that include usernames or passwords."
            return
        }
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
            // Identity follows the bookmark so a new pick is a new view: the
            // old row fades out and the new one fades in, instead of the text
            // and badge snapping in place.
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
                            HStack(spacing: 4) {
                                Image(systemName: folderSymbol(for: pick.folder))
                                    .font(.system(size: 9))
                                Text(pick.folder)
                            }
                            .foregroundStyle(folderColor(for: pick.folder))
                            Text(displayHost(pick))
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable(scale: 0.98))
            .pointerStyle(.link)
            Spacer(minLength: 8)
            // The actions appear with the row hover, Control Center style,
            // and each names itself through its own hover color.
            if isPickHovering {
                HoverIconButton(symbol: "checkmark", label: "Mark done", hoverColor: .green) {
                    withAnimation(Motion.reveal) {
                        model.markDone(pick.id, undoManager: undoManager)
                        self.pick = model.store.pick(excluding: pick.id)
                    }
                }
                HoverIconButton(symbol: "arrow.clockwise", label: "Show another", hoverColor: .primary) {
                    withAnimation(Motion.reveal) {
                        self.pick = model.store.pick(excluding: pick.id)
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

    /// Control Center style badge: the thumbnail in a circle, or the folder
    /// symbol on a soft circle of the folder color.
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

    // MARK: Counts

    private var countsLine: String? {
        // Unsorted is an inbox, not a promise, so it stays out of the summary.
        // The top three filed folders keep the line short enough to never
        // truncate; an all-unsorted library gets a call to sort instead.
        let counts = model.store.counts()
        let filed = model.store.library.folders
            .filter { $0 != Library.unsorted }
            .compactMap { folder -> (name: String, count: Int)? in
                let count = counts.byFolder[folder, default: 0]
                return count > 0 ? (folder, count) : nil
            }
            .sorted { $0.count > $1.count }
            .prefix(3)
        if filed.isEmpty {
            let unsorted = counts.byFolder[Library.unsorted, default: 0]
            return unsorted > 0 ? "\(unsorted) to sort." : nil
        }
        let parts = filed.map { entry -> String in
            var name = entry.name.lowercased()
            // ponytail: naive singularization; a folder like "Dishes" yields "1 dishe".
            if entry.count == 1, name.hasSuffix("s") { name.removeLast() }
            return "\(entry.count) \(name)"
        }
        return parts.joined(separator: ", ") + " waiting."
    }

    // MARK: Recents and Favourites

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Quiet text tabs, not segmented chrome: the selected tab reads as
            // a section title, the other as an available lens.
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
        // Recents follow the store's array order, the same order the library
        // shows: a re-saved duplicate sits on top, matching its hint.
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(bookmark.title).font(.callout).lineLimit(1)
                    Text(displayHost(bookmark))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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

/// A quiet icon button that reveals its purpose on hover: a circular
/// highlight plus a meaningful color, with the tooltip as backup.
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
