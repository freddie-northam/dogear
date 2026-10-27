import AppKit
import Carbon.HIToolbox
import DogearKit
import SwiftUI

struct ShortcutRecorder: View {
    @Binding var stored: String
    @ObservedObject private var monitorState = HotKeyMonitor.shared
    @State private var isRecording = false
    @State private var monitor: Any?

    private var combo: HotKeyCombo? { HotKeyCombo(defaultsValue: stored) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
            if monitorState.isUnavailable, !isRecording {
                Text("Another app already uses this shortcut. Record a different one.")
                    .font(.caption)
                    .foregroundStyle(.red)
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
            if event.keyCode == UInt16(kVK_Escape) {
                stopListening()
                return nil
            }
            let candidate = HotKeyCombo(keyCode: UInt32(event.keyCode),
                                        modifiers: carbonModifiers(event.modifierFlags))
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
