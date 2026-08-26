import AppKit
import Carbon.HIToolbox
import DogearKit

/// Registers one system-wide shortcut. Carbon is the only way macOS offers to
/// claim a shortcut without asking the user for Accessibility access, and a
/// bookmark app has no business holding that permission.
@MainActor
final class HotKeyMonitor: ObservableObject {
    /// One monitor for the process. Settings needs to read the result of a
    /// registration the app scene performed, and a shortcut is a single
    /// system-wide claim, so there is nothing to gain from a second instance.
    static let shared = HotKeyMonitor()

    /// True when a shortcut is recorded but macOS refused to give it to
    /// Dogear, which nearly always means another app already holds it.
    /// Settings reads this to say so, because a shortcut that looks recorded
    /// and does nothing is indistinguishable from a broken app.
    @Published private(set) var isUnavailable = false

    /// Dogear's four-character signature, as Carbon expects one.
    private static let signature = OSType(0x44_47_52_31) // "DGR1"

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    /// Claims the shortcut. Calling it again replaces the previous one, so a
    /// change in Settings takes effect without a relaunch. A nil or
    /// modifier-less combo just clears the shortcut.
    @discardableResult
    func register(_ combo: HotKeyCombo?, action: @escaping () -> Void) -> Bool {
        unregister()
        guard let combo, combo.isValid else { return true }
        self.action = action
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        // A shortcut another app already holds fails here. Dogear keeps no
        // shortcut rather than fighting for one, and says so instead of
        // leaving a dead shortcut on screen in Settings.
        guard RegisterEventHotKey(combo.keyCode, combo.modifiers, id,
                                  GetApplicationEventTarget(), 0, &reference) == noErr else {
            reference = nil
            self.action = nil
            isUnavailable = true
            return false
        }
        return true
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        action = nil
        isUnavailable = false
    }

    fileprivate func fire() { action?() }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        // The handler outlives every registration, so it is installed once and
        // reads back the monitor through the user-data pointer Carbon keeps.
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}

/// Carbon calls a plain C function, which cannot capture anything, so the
/// monitor arrives through the user-data pointer.
private let hotKeyHandler: EventHandlerUPP = { _, _, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
    DispatchQueue.main.async { MainActor.assumeIsolated { monitor.fire() } }
    return noErr
}
