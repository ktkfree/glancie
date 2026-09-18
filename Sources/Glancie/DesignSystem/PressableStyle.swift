import SwiftUI

/// iOS-style tactile button: springs down on press, springs back with a touch of
/// bounce, and fires a haptic on the *down* edge so feedback precedes the action.
public struct PressableStyle: ButtonStyle {
    public var pressedScale: CGFloat
    public var pressedOpacity: Double
    public var haptics: Bool

    public init(pressedScale: CGFloat = 0.93, pressedOpacity: Double = 0.75, haptics: Bool = true) {
        self.pressedScale = pressedScale
        self.pressedOpacity = pressedOpacity
        self.haptics = haptics
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(JellySprings.hover, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed && haptics {
                    SoundEffectsEngine.shared.playSelectionFeedback()
                }
            }
    }
}

public extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}
