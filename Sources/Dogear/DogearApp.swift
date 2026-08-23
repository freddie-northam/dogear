import AppKit
import SwiftUI

@main
struct DogearApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var clipboard = ClipboardWatcher()
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false
    @Environment(\.openWindow) private var openWindow

    init() {
        // No dock icon: menu bar app. Replaces LSUIElement when run outside a bundle.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            CapturePopover()
                .environmentObject(model)
                .environmentObject(clipboard)
                .onAppear {
                    if !hasLaunchedBefore {
                        hasLaunchedBefore = true
                        openWindow(id: "library")
                    }
                }
        } label: {
            Image(systemName: clipboard.linkDetected ? "bookmark.fill" : "bookmark")
        }
        .menuBarExtraStyle(.window)

        Window("Library", id: "library") {
            LibraryWindow()
                .environmentObject(model)
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
        }
    }
}
