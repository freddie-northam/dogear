import Foundation

/// A key and its modifiers, as a system-wide shortcut. The app registers it
/// with Carbon; this type holds the value, draws it, and stores it, so all
/// three have tests.
public struct HotKeyCombo: Equatable, Sendable {
    /// A virtual key code. NSEvent and Carbon use the same numbers.
    public let keyCode: UInt32
    /// A Carbon modifier mask. The constants below name the four Dogear uses.
    public let modifiers: UInt32

    public static let command: UInt32 = 256
    public static let shift: UInt32 = 512
    public static let option: UInt32 = 2048
    public static let control: UInt32 = 4096

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A shortcut with no modifier would swallow a plain keystroke from every
    /// other app, so Dogear refuses to register one.
    public var isValid: Bool {
        modifiers & (Self.command | Self.shift | Self.option | Self.control) != 0
    }

    /// The shortcut as macOS writes it, in Apple's modifier order.
    public var displayString: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "\u{2303}" }
        if modifiers & Self.option != 0 { text += "\u{2325}" }
        if modifiers & Self.shift != 0 { text += "\u{21E7}" }
        if modifiers & Self.command != 0 { text += "\u{2318}" }
        return text + Self.keyName(keyCode)
    }

    // MARK: Storage

    /// "keyCode:modifiers". Two numbers keep the stored default readable and
    /// let an unreadable value fall back to no shortcut at all.
    public var defaultsValue: String { "\(keyCode):\(modifiers)" }

    public init?(defaultsValue: String) {
        let parts = defaultsValue.split(separator: ":")
        guard parts.count == 2,
              let keyCode = UInt32(parts[0]), let modifiers = UInt32(parts[1]) else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: Key names

    static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U",
        34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".",
        50: "`",
        36: "\u{21A9}", 48: "\u{21E5}", 49: "Space", 51: "\u{232B}", 53: "\u{238B}",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
    ]

    static func keyName(_ keyCode: UInt32) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}
