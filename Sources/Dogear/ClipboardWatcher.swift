import AppKit
import DogearKit
import SwiftUI

@MainActor
final class ClipboardWatcher: ObservableObject {
    @Published var linkDetected = false
    @AppStorage("detectCopiedLinks") var enabled = true

    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    private func tick() async {
        guard enabled else {
            linkDetected = false
            return
        }
        let count = NSPasteboard.general.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        // Pattern detection: asks about shape without a content read.
        let detected = try? await NSPasteboard.general.detectedPatterns(for: [\.links])
        // The clipboard may have changed again while we awaited; a stale result
        // must not overwrite a detection for the newer content.
        guard count == lastChangeCount else { return }
        linkDetected = detected?.contains(\.links) ?? false
    }

    /// The one intentional content read, and the only place that decides when
    /// one is allowed. Asks the clipboard for its shape first and reads the
    /// text only on a positive match, which is the privacy promise the README
    /// makes. Every capture path that starts from the clipboard calls this,
    /// so no caller has to remember the rule.
    func readLink() async -> String? {
        let detected = try? await NSPasteboard.general.detectedPatterns(for: [\.links])
        guard detected?.contains(\.links) == true else { return nil }
        return NSPasteboard.general.string(forType: .string)
    }

    func consume() {
        linkDetected = false
    }
}
