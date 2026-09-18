import SwiftUI

/// Activity-ring style circular gauge: rounded caps, angular duotone sweep, and a
/// soft bloom behind the stroke. Optional center content (icon or readout).
public struct RingGauge<Center: View>: View {
    public let percentage: Double
    public let gradientColors: [Color]
    public var size: CGFloat
    public var lineWidth: CGFloat
    public var showsGlow: Bool
    private let center: Center

    public init(
        percentage: Double,
        gradientColors: [Color],
        size: CGFloat = 20,
        lineWidth: CGFloat = 2.6,
        showsGlow: Bool = true,
        @ViewBuilder center: () -> Center = { EmptyView() }
    ) {
        self.percentage = max(0, min(100, percentage))
        self.gradientColors = gradientColors
        self.size = size
        self.lineWidth = lineWidth
        self.showsGlow = showsGlow
        self.center = center()
    }

    private var trim: CGFloat {
        // Keep a visible nub at 0% so an empty ring never looks like a render bug
        max(0.012, CGFloat(percentage / 100.0))
    }

    private var sweep: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: gradientColors + [gradientColors.first ?? .clear]),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Surface.track, lineWidth: lineWidth)

            if showsGlow {
                Circle()
                    .trim(from: 0, to: trim)
                    .stroke(sweep, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .blur(radius: lineWidth * 0.35)
                    .opacity(0.35)
            }

            Circle()
                .trim(from: 0, to: trim)
                .stroke(sweep, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            center
        }
        .frame(width: size, height: size)
        .animation(JellySprings.gauge, value: percentage)
    }
}
