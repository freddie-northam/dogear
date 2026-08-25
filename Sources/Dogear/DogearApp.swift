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

// Shown for a moment after the shortcut saves a link. The app has no
// notifications, so the menu bar itself is where the confirmation goes.
private let savedIcon: NSImage = {
    let base = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Dogear, link saved")!
    let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
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
    @State private var hotKey = HotKeyMonitor()
    @State private var didSaveFromHotKey = false
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
        if didSaveFromHotKey { return savedIcon }
        return clipboard.linkDetected ? linkDetectedIcon : idleIcon
    }

    // MARK: Shortcut

    private func applyHotKey() {
        hotKey.register(HotKeyCombo(defaultsValue: captureHotKey), action: captureFromClipboard)
    }

    /// The shortcut path skips the popover: there is nothing to confirm, and
    /// a save that needs no window is the whole point of a shortcut.
    private func captureFromClipboard() {
        Task { @MainActor in
            // The same rule as the popover: ask the clipboard for its shape,
            // and read the content only when it holds a link.
            let detected = try? await NSPasteboard.general.detectedPatterns(for: [\.links])
            guard detected?.contains(\.links) == true,
                  let text = clipboard.readClipboard(),
                  model.capture(text: text).total > 0 else { return }
            clipboard.consume()
            didSaveFromHotKey = true
            try? await Task.sleep(for: .seconds(1.2))
            didSaveFromHotKey = false
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
