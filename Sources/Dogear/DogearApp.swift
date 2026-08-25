import AppKit
import CoreSpotlight
import DogearKit
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
    @State private var serviceProvider: ServiceProvider?
    @State private var dockObserver = DockReopenObserver()

    init() {
        // The Dock icon is a setting; LSUIElement only sets the initial state.
        DockPresence.apply()
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
                // The label renders at launch, unlike the popover content, so
                // registration here also covers the launched-by-service path.
                .task {
                    registerServiceProviderIfNeeded()
                    dockObserver.start {
                        openWindow(id: "library")
                    }
                }
                // The label is the one view that exists from launch, so it is
                // where a Spotlight result lands even when Spotlight started
                // the app.
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
                    else { return }
                    model.showFromSpotlight(id: id)
                    openWindow(id: "library")
                }
        }
        .menuBarExtraStyle(.window)

        Window("Library", id: "library") {
            LibraryWindow()
                .environmentObject(model)
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }

    /// Registers the Save to Dogear service handler. NSApp.servicesProvider
    /// does not retain its provider, so the strong reference lives here.
    private func registerServiceProviderIfNeeded() {
        guard serviceProvider == nil else { return }
        let model = model
        let provider = ServiceProvider { text in
            _ = model.capture(text: text)
        }
        serviceProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
    }
}
