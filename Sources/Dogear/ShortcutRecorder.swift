import AppKit
import DogearKit
import SwiftUI

/// Records a shortcut by listening for the next keystroke. macOS has no
/// stock control for this, and a fixed default would collide with whatever
/// the user already runs, so Dogear asks instead of guessing.
struct ShortcutRecorder: View {
    @Binding var stored: String
    @State private var isRecording = false
    @State private var monitor: Any?

    private var combo: HotKeyCombo? { HotKeyCombo(defaultsValue: stored) }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Text(label)
                    .font(.body.monospaced())
                    .frame(minWidth: 110)
            }
            if combo != nil, !isRecording {
                Button("Clear") { stored = "" }
            }
        }
        .onDisappear(perform: stopListening)
    }

    private var label: String {
        if isRecording { return "Press keys..." }
        return combo?.displayString ?? "Record Shortcut"
    }

    private func toggle() {
        if isRecording { stopListening() } else { startListening() }
    }

    private func startListening() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape leaves the shortcut as it was, the way every other
            // recorder on the Mac behaves.
            if event.keyCode == 53 {
                stopListening()
                return nil
            }
            let candidate = HotKeyCombo(keyCode: UInt32(event.keyCode),
                                        modifiers: carbonModifiers(event.modifierFlags))
            // A bare key would swallow that keystroke in every other app.
            guard candidate.isValid else { return nil }
            stored = candidate.defaultsValue
            stopListening()
            return nil
        }
    }

    private func stopListening() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= HotKeyCombo.command }
        if flags.contains(.shift) { modifiers |= HotKeyCombo.shift }
        if flags.contains(.option) { modifiers |= HotKeyCombo.option }
        if flags.contains(.control) { modifiers |= HotKeyCombo.control }
        return modifiers
    }
}
