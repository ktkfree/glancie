import SwiftUI

/// Linear quota gauge with an inset track, duotone fill, specular top line and a
/// colored bloom underneath — the iOS "glossy pill" progress treatment.
public struct LiquidCapsuleGauge: View {
    public let percentage: Double // 0.0 ~ 100.0
    public let gradientColors: [Color]
    public var width: CGFloat
    public var height: CGFloat
    public var showsGlow: Bool

    public init(
        percentage: Double,
        gradientColors: [Color],
        width: CGFloat = 36,
        height: CGFloat = 5,
        showsGlow: Bool = true
    ) {
        self.percentage = max(0, min(100, percentage))
        self.gradientColors = gradientColors
        self.width = width
        self.height = height
        self.showsGlow = showsGlow
    }

    public var body: some View {
        let fillWidth = max(height, width * CGFloat(percentage / 100.0))

        ZStack(alignment: .leading) {
            // Inset track with a faint inner shadow lip
            Capsule()
                .fill(Surface.track)
                .overlay(
                    Capsule().strokeBorder(Surface.shellRim.opacity(0.6), lineWidth: 0.5)
                )
                .frame(width: width, height: height)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(
                        LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing)
                    )

                // Specular highlight riding the top half of the fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.55), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: height * 0.5)
                    .padding(.horizontal, height * 0.28)
                    .blendMode(.plusLighter)
            }
            .frame(width: fillWidth, height: height)
            .shadow(
                color: showsGlow ? (gradientColors.first ?? .clear).opacity(0.55) : .clear,
                radius: height * 0.9,
                x: 0,
                y: 0
            )
        }
        .frame(width: width, height: height)
        .animation(JellySprings.gauge, value: percentage)
    }
}
