import SwiftUI

/// First-run onboarding: three ideas and one action, then out of the way.
/// The same content lives in Settings under Help for anyone who wants it
/// again, so this sheet never needs to be exhaustive.
struct WelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pasteFromClipboard: () -> Void
    let importFromNotes: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text("Welcome to Dogear")
                    .font(.title2.weight(.semibold))
                Text("Save links now. Come back to them when you have time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                HelpRow(symbol: "play.rectangle", color: .pink,
                        title: "Save TikToks, tweets, and links from anywhere",
                        detail: "Copy the link in TikTok or X on your iPhone. It arrives on your Mac by itself. Click the bookmark in the menu bar and press Return.")
                HelpRow(symbol: "sparkles", color: .orange,
                        title: "Dogear files it for you",
                        detail: "Recipes, restaurants, shows, music, articles. Move anything yourself and it stays put.")
                HelpRow(symbol: "checkmark.circle", color: .green,
                        title: "Mark it done when you are",
                        detail: "Done bookmarks move to the Archive. The popover shows you one that is waiting.")
            }
            .frame(maxWidth: 360)
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button("Import from Notes...") {
                        dismiss()
                        importFromNotes()
                    }
                    .buttonStyle(.bordered)
                    Button("Paste from Clipboard") {
                        dismiss()
                        pasteFromClipboard()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                Button("Start empty") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
            }
            Text("Everything stays on this Mac. No account, no server.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 440)
    }
}
