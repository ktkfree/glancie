import SwiftUI

/// Carries the laid-out content size (width & height) from SwiftUI up to the panel controller.
struct ContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(
            width: max(value.width, next.width),
            height: max(value.height, next.height)
        )
    }
}

/// Carries the measured width of the capsule bar for aligning companion elements
struct BarWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 180
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The floating capsule bar — a Dynamic Island for AI quota. Slim and calm at
/// rest, it blooms with the color of whichever provider is closest to empty and
/// morphs open into a detail card on tap.
public struct MultiProviderBarView: View {
    @ObservedObject public var providerManager = ProviderManager.shared
    @ObservedObject public var preferences = GlanciePreferences.shared
    @ObservedObject public var panelController = FloatingPanelController.shared
    /// See `MenuBarPanelHostView`: the bar is its own hosting root, so the
    /// language has to be observed here too for a switch to reach it.
    @ObservedObject public var localization = Localization.shared

    @State private var isBarHovered: Bool = false
    @State private var actualBarWidth: CGFloat = 180

    public init() {}

    /// The bar takes on the color of the provider in the most trouble — the one
    /// piece of information worth surfacing before the user reads any number.
    private var ambientTier: UsageTier {
        let realPercentages = providerManager.activeProviders
            .compactMap { provider -> Double? in
                guard let snap = providerManager.snapshots[provider], !snap.isSimulated else { return nil }
                return snap.remainingPercentage
            }
        let worst = realPercentages.min() ?? 100
        return UsageTier.from(worst)
    }

    private var visibleProviders: [AIProviderType] {
        providerManager.activeProviders.filter { providerManager.snapshots[$0] != nil }
    }

    public var body: some View {
        // Fully self-sizing dynamic width & height: the laid-out size is pushed to the
        // panel, which resizes the NSPanel window to hug the content perfectly.
        content
            .fixedSize()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: ContentSizeKey.self, value: proxy.size)
                }
            }
            .onPreferenceChange(ContentSizeKey.self) { size in
                MainActor.assumeIsolated {
                    FloatingPanelController.shared.updateContentSize(size)
                }
            }
            .onPreferenceChange(BarWidthKey.self) { width in
                if width > 0 {
                    actualBarWidth = width
                }
            }
    }

    private var content: some View {
        VStack(spacing: Metric.stackGap) {
            if panelController.opensUpward {
                detailCard
                barWithCat
            } else {
                barWithCat
                detailCard
            }
        }
        .padding(Metric.panelBleed)
    }

    // MARK: - Bar with Cat Companion

    private var barWithCat: some View {
        bar
            .overlay(alignment: .topLeading) {
                if preferences.pixelCatEnabled {
                    PixelCatView(isBarHovered: isBarHovered, barWidth: actualBarWidth)
                        .frame(height: 24)
                        .offset(y: -Metric.pixelCatBand)
                        .zIndex(999)
                }
            }
            .padding(.top, preferences.pixelCatEnabled ? Metric.pixelCatBand : 0)
    }

    // MARK: - Bar

    private var bar: some View {
        HStack(spacing: 5) {
            GrabberHandle(isActive: isBarHovered)
                .padding(.leading, 9)

            HairlineDivider()
                .padding(.trailing, 1)

            ForEach(visibleProviders) { provider in
                if let snapshot = providerManager.snapshots[provider] {
                    ProviderSegmentView(
                        snapshot: snapshot,
                        isSelected: providerManager.selectedProvider == provider,
                        onTap: { select(provider) }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
        .padding(.trailing, 9)
        .frame(height: Metric.barHeight)
        .overlay(alignment: .bottom) {
            TabBarLoadingBar(
                isRefreshing: providerManager.isRefreshing,
                tint: ambientTier.accent
            )
        }
        .liquidGlass(
            cornerRadius: Radius.bar,
            tint: ambientTier.accent,
            isHovered: isBarHovered,
            elevation: isBarHovered ? 1.0 : 0.85
        )
        .background {
            // Measure actual rendered width of the bar
            GeometryReader { proxy in
                Color.clear.preference(key: BarWidthKey.self, value: proxy.size.width)
            }
        }
        .animation(JellySprings.layout, value: visibleProviders)
        .animation(JellySprings.layout, value: providerManager.isRefreshing)
        .animation(JellySprings.gauge, value: ambientTier)
        .onHover { isBarHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.usageBar.text)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailCard: some View {
        if let selected = providerManager.selectedProvider,
           let snapshot = providerManager.snapshots[selected] {
            DetailGlassCardView(snapshot: snapshot) {
                select(selected)
            }
        }
    }

    private func select(_ provider: AIProviderType) {
        guard !FloatingPanelController.shared.isDragging,
              !FloatingPanelController.shared.hasDraggedRecently else { return }

        // Evaluate orientation before opening
        FloatingPanelController.shared.checkPlacementDirection()
        
        // No animation on purpose: the card and the window it lives in have to
        // change size together, and any transition means frames where one has
        // moved and the other has not — which is what read as a blink.
        SoundEffectsEngine.shared.playImpactFeedback()
        providerManager.selectedProvider = (providerManager.selectedProvider == provider) ? nil : provider
    }
}
