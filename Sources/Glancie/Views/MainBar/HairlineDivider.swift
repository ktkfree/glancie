import SwiftUI

/// 0.5px vertical separator, fading out at both ends so it never reads as a hard rule.
public struct HairlineDivider: View {
    public var height: CGFloat

    public init(height: CGFloat = 14) {
        self.height = height
    }

    public var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.primary.opacity(0.0),
                        Color.primary.opacity(0.14),
                        Color.primary.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 0.5, height: height)
            .accessibilityHidden(true)
    }
}
