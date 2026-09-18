import SwiftUI

/// Breathing "live" dot shown while providers are being refreshed — a quieter,
/// more Dynamic-Island-like substitute for a spinner in a 34pt bar.
public struct LiveActivityDot: View {
    public var color: Color
    @State private var pulsing = false

    public init(color: Color) {
        self.color = color
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 12, height: 12)
                .scaleEffect(pulsing ? 1.0 : 0.45)
                .opacity(pulsing ? 0.0 : 0.8)

            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(color: color.opacity(0.8), radius: 3)
        }
        .frame(width: 12, height: 12)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
        .accessibilityLabel(L10n.refreshingUsage.text)
    }
}
