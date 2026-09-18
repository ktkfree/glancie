import SwiftUI

/// Odometer-style numeric readout. Uses the system `.numericText` content
/// transition so digits roll vertically the way iOS timers and the Fitness
/// rings do, instead of hard-cutting between values.
public struct RollingDigitsView: View {
    public let value: Int
    public let suffix: String
    public let font: Font
    public let color: Color
    /// Suffix is typeset at its own (smaller) size rather than scaled, so it
    /// never gets clipped by the layout box reserved for the full-size glyph.
    public let suffixFont: Font

    public init(
        value: Int,
        suffix: String = "%",
        font: Font = GlancieFont.barValue,
        color: Color = .primary,
        suffixFont: Font = GlancieFont.rounded(8, .semibold)
    ) {
        self.value = value
        self.suffix = suffix
        self.font = font
        self.color = color
        self.suffixFont = suffixFont
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(value)")
                .font(font)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .animation(JellySprings.digits, value: value)

            if !suffix.isEmpty {
                Text(suffix)
                    .font(suffixFont)
                    .opacity(0.55)
            }
        }
        .foregroundStyle(color)
        .fixedSize()
    }
}
