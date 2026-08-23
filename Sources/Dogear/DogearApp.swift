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
    // A non-template image keeps its intrinsic size instead of following the
    // menu bar, so pin the symbol to the menu bar's standard point size.
    let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.systemPink]))
    let image = base.withSymbolConfiguration(configuration) ?? base
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
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
        }
    }
}
