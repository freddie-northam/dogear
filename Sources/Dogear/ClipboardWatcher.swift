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
        let detected = try? await NSPasteboard.general.detectedPatterns(for: [\.links])
        guard count == lastChangeCount else { return }
        linkDetected = detected?.contains(\.links) ?? false
    }

    func readLink() async -> String? {
        let detected = try? await NSPasteboard.general.detectedPatterns(for: [\.links])
        guard detected?.contains(\.links) == true else { return nil }
        return NSPasteboard.general.string(forType: .string)
    }

    func consume() {
        linkDetected = false
    }
}
