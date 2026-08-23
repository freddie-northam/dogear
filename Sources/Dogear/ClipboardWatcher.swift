import AppKit
import DogearKit
import SwiftUI

@MainActor
final class ClipboardWatcher: ObservableObject {
    @Published var linkDetected = false
    @AppStorage("detectCopiedLinks") var enabled = true

    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
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
        linkDetected = detected?.contains(\.links) ?? false
    }

    /// The one intentional content read, at save time.
    func readClipboard() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func consume() {
        linkDetected = false
    }
}
