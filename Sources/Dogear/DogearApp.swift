import AppKit
import SwiftUI

// Menu bar icons. The idle icon is a template image, so it follows the menu
// bar appearance. The detected icon opts out of template rendering to show
// the brand pink; MenuBarExtra strips color from template images, so a
// palette-configured NSImage is the one way the pink survives.
private let idleIcon: NSImage = {
    let image = NSImage(systemSymbolName: "bookmark", accessibilityDescription: "Dogear")!
    image.isTemplate = true
    return image
}()

private let linkDetectedIcon: NSImage = {
    let base = NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: "Dogear, link detected")!
    let image = base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemPink])) ?? base
    image.isTemplate = false
    return image
}()

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
                .tint(.pink)
                .onAppear {
                    if !hasLaunchedBefore {
                        hasLaunchedBefore = true
                        openWindow(id: "library")
                    }
                }
        } label: {
            Image(nsImage: clipboard.linkDetected ? linkDetectedIcon : idleIcon)
        }
        .menuBarExtraStyle(.window)

        Window("Library", id: "library") {
            LibraryWindow()
                .environmentObject(model)
                .tint(.pink)
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
                .tint(.pink)
        }
    }
}
