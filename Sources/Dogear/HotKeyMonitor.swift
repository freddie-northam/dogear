import AppKit
import Carbon.HIToolbox
import DogearKit

/// Registers one system-wide shortcut. Carbon is the only way macOS offers to
/// claim a shortcut without asking the user for Accessibility access, and a
/// bookmark app has no business holding that permission.
@MainActor
final class HotKeyMonitor {
    /// Dogear's four-character signature, as Carbon expects one.
    private static let signature = OSType(0x44_47_52_31) // "DGR1"

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    /// Claims the shortcut. Calling it again replaces the previous one, so a
    /// change in Settings takes effect without a relaunch. A nil or
    /// modifier-less combo just clears the shortcut.
    func register(_ combo: HotKeyCombo?, action: @escaping () -> Void) {
        unregister()
        guard let combo, combo.isValid else { return }
        self.action = action
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        // A shortcut another app already holds fails here, and failing is the
        // whole answer: Dogear keeps no shortcut rather than fighting for one.
        if RegisterEventHotKey(combo.keyCode, combo.modifiers, id,
                               GetApplicationEventTarget(), 0, &reference) != noErr {
            reference = nil
            self.action = nil
        }
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        action = nil
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
