import AppKit

enum DockPresence {
    static let defaultsKey = "showDockIcon"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    static func apply() {
        NSApplication.shared.setActivationPolicy(isEnabled ? .regular : .accessory)
    }
}

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
            let visible = NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) }
            if !visible { Task { @MainActor in openLibrary() } }
        }
    }
}
