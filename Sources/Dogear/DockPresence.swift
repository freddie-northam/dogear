import AppKit

/// Dogear can run as a plain menu bar app or also show a Dock icon. The Dock
/// icon is on by default so the app is never invisible when a crowded menu
/// bar hides its item; a click on the Dock icon opens the library.
///
/// Measured cost, so nobody chases it as a leak: the accessory policy idles
/// at about 13 MB; the regular policy at about 48 MB. The difference is
/// AppKit and SwiftUI window-server code that macOS pages in for every
/// Foreground app. It is the price of a Dock icon, not something in Dogear.
enum DockPresence {
    static let defaultsKey = "showDockIcon"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    static func apply() {
        NSApplication.shared.setActivationPolicy(isEnabled ? .regular : .accessory)
    }
}

/// Opens the library when the Dock icon is clicked with no window showing.
/// This is an observer, not an NSApplicationDelegate: adopting a delegate
/// adaptor makes SwiftUI materialize every scene at launch, which measured
/// as 35 MB of live layers for a handler that fires a few times a day.
@MainActor
final class DockReopenObserver {
    private var token: NSObjectProtocol?

    func start(openLibrary: @escaping @MainActor () -> Void) {
        guard token == nil else { return }
        token = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            // A click on the Dock icon activates the app. When no window is
            // visible at that moment the click meant "show me the library".
            let visible = NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) }
            if !visible { Task { @MainActor in openLibrary() } }
        }
    }
}
