import AppKit
import SwiftUI

@main
struct DogearApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var clipboard = ClipboardWatcher()

    init() {
        // No dock icon: menu bar app. Replaces LSUIElement when run outside a bundle.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            CapturePopover()
                .environmentObject(model)
                .environmentObject(clipboard)
        } label: {
            Image(systemName: clipboard.linkDetected ? "bookmark.fill" : "bookmark")
        }
        .menuBarExtraStyle(.window)
    }
}
