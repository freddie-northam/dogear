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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Paste a link", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.isEmpty)
            }
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Open Library") {
                    openWindow(id: "library")
                    dismiss()
                }
                Spacer()
                SettingsLink { Text("Settings") }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .font(.caption)
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { Task { await prefill() } }
        .alert("Storage Error", isPresented: Binding(
            get: { model.storageError != nil },
            set: { if !$0 { model.storageError = nil } }
        )) {
            Button("OK") { model.storageError = nil }
        } message: {
            Text(model.storageError ?? "")
        }
    }

    private func prefill() async {
        hint = nil
        // Check the clipboard shape first; read the content only on a positive match.
        let detected = try? await NSPasteboard.general.detectedPatterns(for: [\.links])
        guard detected?.contains(\.links) == true,
              let clip = clipboard.readClipboard(),
              URLCleaner.firstHTTPURL(in: clip) != nil else { return }
        text = clip
    }

    private func save() {
        switch model.capture(text: text) {
        case .saved:
            clipboard.consume()
            text = ""
            dismiss()
        case .alreadySaved:
            hint = "Already saved. It moved to the top of the library."
            clipboard.consume()
            text = ""
        case .invalid:
            hint = "That is not a web link. Dogear saves http and https links."
        }
    }
}
