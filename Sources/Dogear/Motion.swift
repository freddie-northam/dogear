import SwiftUI

enum Motion {
    static let hover: Animation = .smooth(duration: 0.15)
    static let reveal: Animation = .smooth(duration: 0.18)
    static let shuffle: Animation = .smooth(duration: 0.25)
    static let press: Animation = .timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
}

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
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
    static func pressable(scale: CGFloat) -> PressableButtonStyle {
        PressableButtonStyle(scale: scale)
    }
}
