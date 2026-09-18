import SwiftUI

/// Web-browser style slim bottom loading progress bar for the floating capsule bar.
/// Displays an animated shimmering indeterminate progress beam along the bottom edge when refreshing.
public struct TabBarLoadingBar: View {
    public var isRefreshing: Bool
    public var tint: Color

    @State private var shimmerOffset: CGFloat = -0.5

    public init(isRefreshing: Bool, tint: Color = Color(hex: 0x0A84FF)) {
        self.isRefreshing = isRefreshing
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width

            if isRefreshing {
                ZStack(alignment: .leading) {
                    // 1. Subtle background track along bottom edge
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.18))
                        .frame(height: 2)

                    // 2. Animated indeterminate progress beam (like Safari / Chrome web loading bar)
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(0.0),
                                    tint.opacity(0.4),
                                    tint,
                                    tint.opacity(0.95),
                                    tint.opacity(0.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(35, totalWidth * 0.5), height: 2)
                        .shadow(color: tint.opacity(0.85), radius: 3, y: 0.5)
                        .offset(x: shimmerOffset * totalWidth)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .clipShape(Capsule(style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
            }
        }
        .frame(height: 2)
        .padding(.horizontal, 12)
        .padding(.bottom, 1.5)
        .onAppear {
            if isRefreshing {
                startAnimation()
            }
        }
        .onChange(of: isRefreshing) { _, newValue in
            if newValue {
                startAnimation()
            } else {
                shimmerOffset = -0.5
            }
        }
    }

    private func startAnimation() {
        shimmerOffset = -0.5
        withAnimation(
            .easeInOut(duration: 1.1)
            .repeatForever(autoreverses: false)
        ) {
            shimmerOffset = 1.1
        }
    }
}
