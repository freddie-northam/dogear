import AppKit

/// Dogear can run as a plain menu bar app or also show a Dock icon. The Dock
/// icon is on by default so the app is never invisible when a crowded menu
/// bar hides its item; a click on the Dock icon opens the library.
enum DockPresence {
    static let defaultsKey = "showDockIcon"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    static func apply() {
        NSApplication.shared.setActivationPolicy(isEnabled ? .regular : .accessory)
    }
}

/// Receives the Dock icon click (the reopen event) and hands it to the app.
/// NSApplicationDelegateAdaptor is the one supported hook for that event in
/// a SwiftUI app; it stays this small on purpose.
final class DockDelegate: NSObject, NSApplicationDelegate {
    var openLibrary: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openLibrary?() }
        return true
    }
}
