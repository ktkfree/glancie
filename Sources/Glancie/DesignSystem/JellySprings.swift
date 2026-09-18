import SwiftUI

/// Motion presets built on the iOS 17 / macOS 14 native spring vocabulary
/// (`.smooth` / `.snappy` / `.bouncy`) so timing matches system animations.
public enum JellySprings {
    /// Bar width / segment count morphs — Dynamic Island style
    public static let layout = Animation.snappy(duration: 0.38, extraBounce: 0.12)

    /// Hover and press micro-states — fast, barely bouncy
    public static let hover = Animation.snappy(duration: 0.24, extraBounce: 0.06)

    /// Detail card reveal — the signature "island expands" motion
    public static let popover = Animation.spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.2)

    /// Gauge fills: no overshoot, values must never read higher than they are
    public static let gauge = Animation.smooth(duration: 0.55)

    /// Numeric odometer roll
    public static let digits = Animation.snappy(duration: 0.34, extraBounce: 0.08)

    /// Soft breathing / pulsating ambient motion
    public static let pulse = Animation.easeInOut(duration: 2.2).repeatForever(autoreverses: true)

    /// Snappy blink animation
    public static let blink = Animation.easeInOut(duration: 0.12)

    /// Micro eye-tracking spring
    public static let eyeTrack = Animation.interpolatingSpring(stiffness: 280, damping: 22)
}
