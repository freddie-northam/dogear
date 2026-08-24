import SwiftUI

/// The app's motion vocabulary. Every animation in the app target uses one
/// of these, so the feel stays consistent and a change lands everywhere.
enum Motion {
    /// Hover color and background changes.
    static let hover: Animation = .smooth(duration: 0.15)
    /// Small reveals: a hint line, a badge, a swapped row.
    static let reveal: Animation = .smooth(duration: 0.18)
    /// Cards and rows that leave, arrive, or reorder.
    static let shuffle: Animation = .smooth(duration: 0.25)
    /// Pointer-down feedback. A strong ease-out, so the give reads at once.
    static let press: Animation = .timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
}

/// Pointer-down feedback for plain buttons: a small give under the pointer
/// on press, back to size on release. Reduced motion dims instead of scales
/// so the press is still acknowledged.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// Small targets such as icon buttons.
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
    /// Wide targets such as rows, which need a smaller give.
    static func pressable(scale: CGFloat) -> PressableButtonStyle {
        PressableButtonStyle(scale: scale)
    }
}
