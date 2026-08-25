import AppKit
import DogearKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            LibrarySettings()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            HelpSettings()
                .tabItem { Label("Help", systemImage: "questionmark.circle") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage("detectCopiedLinks") private var detectCopiedLinks = true
    @AppStorage(DockPresence.defaultsKey) private var showDockIcon = true
    @AppStorage(AppModel.spotlightKey) private var spotlightIndexing = true
    @AppStorage(DogearApp.hotKeyDefaultsKey) private var captureHotKey = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle(isOn: $showDockIcon) {
                    Text("Show icon in Dock")
                    Text("With the Dock icon off, Dogear lives only in the menu bar.")
                }
                .onChange(of: showDockIcon) { _, _ in DockPresence.apply() }
            }
            Section("Capture") {
                Toggle(isOn: $detectCopiedLinks) {
                    Text("Detect copied links")
                    Text("Dogear checks if the clipboard holds a link. It reads the clipboard only when you save.")
                }
                LabeledContent {
                    ShortcutRecorder(stored: $captureHotKey)
                } label: {
                    Text("Save the copied link")
                    Text("Press this shortcut in any app. Dogear saves the link and shows a tick in the menu bar.")
                }
            }
            Section("Search") {
                Toggle(isOn: $spotlightIndexing) {
                    Text("Find bookmarks in Spotlight")
                    Text("Your saved links answer a Spotlight search. The list stays on this Mac.")
                }
                .onChange(of: spotlightIndexing) { AppModel.shared?.syncSpotlight() }
            }
            Section("Startup") {
                Toggle(isOn: $launchAtLogin) {
                    Text("Launch at login")
                    Text("Dogear starts with your Mac and waits in the menu bar.")
                }
                .onChange(of: launchAtLogin) { _, enable in
                    try? enable ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Library

private struct LibrarySettings: View {
    // Resolved when the tab is shown, never at launch; see the Settings scene.
    private var model: AppModel? { AppModel.shared }
    @State private var thumbnailBytes: Int64 = 0
    @State private var clearedThumbnails = false

    private var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dogear")
    }

    var body: some View {
        let counts = model?.store.counts()
        let total = model?.store.library.bookmarks.count ?? 0
        Form {
            Section("Your library") {
                LabeledContent("Bookmarks", value: "\(total)")
                LabeledContent("Waiting", value: "\(total - (counts?.archived ?? 0))")
                LabeledContent("Archived", value: "\(counts?.archived ?? 0)")
                LabeledContent("Favourites", value: "\(counts?.favorites ?? 0)")
                LabeledContent("Folders", value: "\(model?.store.library.folders.count ?? 0)")
            }
            Section("Storage") {
                LabeledContent("Location") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([supportDirectory])
                    }
                }
                LabeledContent("Thumbnail cache") {
                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: thumbnailBytes, countStyle: .file))
                            .foregroundStyle(.secondary)
                        Button("Clear") { clearThumbnails() }
                            .disabled(thumbnailBytes == 0)
                    }
                }
                Text(clearedThumbnails
                    ? "Cleared. Dogear fetches thumbnails again when you refresh a bookmark."
                    : "Your library is one JSON file on this Mac, with a backup beside it. Nothing leaves your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { thumbnailBytes = measureThumbnails() }
    }

    private func measureThumbnails() -> Int64 {
        let directory = supportDirectory.appendingPathComponent("thumbnails")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private func clearThumbnails() {
        guard let model else { return }
        for bookmark in model.store.library.bookmarks where bookmark.hasThumbnail {
            model.thumbnails.remove(for: bookmark.id)
            var cleared = bookmark
            cleared.hasThumbnail = false
            model.store.update(cleared)
        }
        thumbnailBytes = measureThumbnails()
        clearedThumbnails = true
    }
}

// MARK: - Help

/// Always-available onboarding: the same four ideas the welcome sheet shows on
/// first run, here for anyone who skipped it or forgot.
struct HelpSettings: View {
    var body: some View {
        Form {
            Section("Save a link") {
                HelpRow(symbol: "play.rectangle", color: .pink,
                        title: "TikToks, tweets, and any web link",
                        detail: "Use Share, then Copy Link in TikTok or X on your iPhone. Universal Clipboard carries it to your Mac. Dogear fetches the caption, the author, and a thumbnail.")
                HelpRow(symbol: "doc.on.clipboard", color: .blue,
                        title: "Copy, then click the bookmark icon",
                        detail: "The menu bar icon fills when a link is ready. Click it and press Return.")
                HelpRow(symbol: "text.cursor", color: .indigo,
                        title: "Paste many at once",
                        detail: "Paste a block of text with many links. Dogear saves each one.")
                HelpRow(symbol: "contextualmenu.and.cursorarrow", color: .teal,
                        title: "From any app",
                        detail: "Select a link, right-click, and choose Services, then Save to Dogear.")
            }
            Section("Let Dogear file it") {
                HelpRow(symbol: "sparkles", color: .orange,
                        title: "Auto-filing",
                        detail: "New links go to Recipes, Restaurants, Shows, Music, or Articles. Move any bookmark yourself; Dogear never moves it again.")
                HelpRow(symbol: "tray", color: .gray,
                        title: "Unsorted is your inbox",
                        detail: "Links Dogear cannot place wait in Unsorted. Right-click the folder and choose File These for Me to try again.")
            }
            Section("Come back to it") {
                HelpRow(symbol: "checkmark.circle", color: .green,
                        title: "Mark it done",
                        detail: "Cooked the recipe? Watched the show? Mark it done. It moves to the Archive, which stays searchable. Undo with Command Z.")
                HelpRow(symbol: "qrcode", color: .purple,
                        title: "Open on your phone",
                        detail: "Right-click a bookmark and choose Show QR Code. Scan it with your iPhone camera.")
            }
        }
        .formStyle(.grouped)
    }
}

struct HelpRow: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - About

private struct AboutSettings: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Dogear").font(.title2.weight(.semibold))
            Text("Version \(version)")
                .font(.caption).foregroundStyle(.secondary)
            Text("Save links to make, visit, watch, hear, and read.")
                .font(.callout)
                .multilineTextAlignment(.center)
            Divider().frame(width: 200).padding(.vertical, 4)
            Text("Free and open source under the MIT license.\nNo account, no server, no telemetry.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link("Dogear on GitHub", destination: URL(string: "https://github.com/freddie-northam/dogear")!)
                .font(.caption)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
