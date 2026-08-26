import AppKit
import CoreSpotlight
import DogearKit
import SwiftUI

// The idle icon is a template image, so it follows the menu bar appearance.
private let idleIcon: NSImage = {
    let image = NSImage(systemSymbolName: "bookmark", accessibilityDescription: "Dogear")!
    image.isTemplate = true
    return image
}()

/// MenuBarExtra strips color from a template image, so a palette-configured
/// non-template one is the only way the brand pink survives. Such an image
/// also keeps its intrinsic size instead of following the menu bar, so the
/// symbol is pinned to the menu bar's standard point size.
private func pinkMenuBarIcon(_ symbol: String, weight: NSFont.Weight,
                             description: String) -> NSImage {
    let base = NSImage(systemSymbolName: symbol, accessibilityDescription: description)!
    let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.systemPink]))
    let image = base.withSymbolConfiguration(configuration) ?? base
    image.isTemplate = false
    return image
}

private let linkDetectedIcon = pinkMenuBarIcon(
    "bookmark.fill", weight: .regular, description: "Dogear, link detected")

// Shown for a moment after the shortcut saves a link. The app has no
// notifications, so the menu bar itself is where the confirmation goes.
private let savedIcon = pinkMenuBarIcon(
    "checkmark", weight: .semibold, description: "Dogear, link saved")

@main
struct DogearApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var clipboard = ClipboardWatcher()
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false
    @Environment(\.openWindow) private var openWindow
    @State private var serviceProvider: ServiceProvider?
    @State private var dockObserver = DockReopenObserver()
    @AppStorage(DogearApp.hotKeyDefaultsKey) private var captureHotKey = ""

    static let hotKeyDefaultsKey = "captureHotKey" 

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
            Image(nsImage: menuBarIcon)
                // The label renders at launch, unlike the popover content, so
                // registration here also covers the launched-by-service path.
                .task {
                    registerServiceProviderIfNeeded()
                    dockObserver.start {
                        openWindow(id: "library")
                    }
                    applyHotKey()
                }
                .onChange(of: captureHotKey) { applyHotKey() }
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

    private var menuBarIcon: NSImage {
        if model.showsSavedTick { return savedIcon }
        return clipboard.linkDetected ? linkDetectedIcon : idleIcon
    }

    // MARK: Shortcut

    private func applyHotKey() {
        HotKeyMonitor.shared.register(HotKeyCombo(defaultsValue: captureHotKey),
                                      action: captureFromClipboard)
    }

    /// The shortcut path skips the popover: there is nothing to confirm, and
    /// a save that needs no window is the whole point of a shortcut.
    private func captureFromClipboard() {
        Task { @MainActor in
            guard let text = await clipboard.readLink(),
                  model.captureWithoutWindow(text: text).total > 0 else { return }
            clipboard.consume()
        }
    }

    /// Registers the Save to Dogear service handler. NSApp.servicesProvider
    /// does not retain its provider, so the strong reference lives here.
    private func registerServiceProviderIfNeeded() {
        guard serviceProvider == nil else { return }
        let model = model
        let provider = ServiceProvider { text in
            model.captureWithoutWindow(text: text)
        }
        serviceProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
    }
}
