import SwiftUI

/// Reports the dropdown's laid-out size (including shadow bleed) up to the panel
/// controller so the window can hug its content.
struct MenuContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

/// Height of the current screen's content, used to let the scroll area hug it
/// until it hits the ceiling and starts scrolling.
struct MenuStackHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

enum GlancieBuild {
    static let version: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
}

/// The menu bar dropdown.
///
/// Structured as a fixed title bar over a pushable screen stack, the way system
/// menu extras are: identity and freshness stay put while the content drills
/// down, so the panel never loses its anchor.
public struct MenuBarPopoverView: View {
    @ObservedObject private var providerManager = ProviderManager.shared
    @ObservedObject private var navigator = MenuBarNavigator.shared

    @State private var stackHeight: CGFloat = 0

    public init() {}

    private var activeProviders: [AIProviderType] {
        providerManager.activeProviders
    }

    /// The dropdown takes its ambient colour from the provider closest to empty —
    /// the only fact worth reading before any number.
    private var ambientTier: UsageTier {
        let worst = activeProviders
            .compactMap { providerManager.snapshots[$0]?.remainingPercentage }
            .min() ?? 100
        return UsageTier.from(worst)
    }

    public var body: some View {
        VStack(spacing: 0) {
            titleBar

            Rectangle()
                .fill(Surface.hairline)
                .frame(height: 0.5)

            screenStack
        }
        .frame(width: Metric.menuWidth)
        .liquidGlass(
            cornerRadius: Radius.menu,
            tint: ambientTier.accent,
            elevation: 1.2,
            tintStrength: 0.45
        )
        .padding(Metric.menuBleed)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: MenuContentSizeKey.self, value: proxy.size)
            }
        }
        .animation(JellySprings.gauge, value: ambientTier)
    }

    // MARK: - Title bar

    private var titleBar: some View {
        HStack(spacing: 9) {
            IconTile(
                symbol: "sparkles",
                colors: [Color(hex: 0x0A84FF), Color(hex: 0x0050C7)],
                size: 26
            )

            VStack(alignment: .leading, spacing: 1) {
                Text("Glancie")
                    .font(GlancieFont.rounded(14, .bold))
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    if providerManager.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.58)
                            .frame(width: 11, height: 11)
                    }

                    Text(statusSummary)
                        .font(GlancieFont.rounded(9.5, .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
            }

            Spacer(minLength: 4)

            TierBadge(tier: ambientTier, compact: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
    }

    private var statusSummary: String {
        if providerManager.isRefreshing { return L10n.updating.text }
        guard !activeProviders.isEmpty else { return L10n.noProvidersConnected.text }

        let latest = activeProviders
            .compactMap { providerManager.snapshots[$0]?.lastUpdated }
            .max()

        let freshness = latest.map(relativeUpdateText) ?? L10n.waiting.text
        return L10n.connectedCount(activeProviders.count, freshness).text
    }

    // MARK: - Screen stack

    private var screenStack: some View {
        ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .top) {
                switch navigator.screen {
                case .overview:
                    MenuBarOverviewScreen()
                        .transition(.menuPush(forward: navigator.isForward))

                case .providerDetail(let provider):
                    MenuBarProviderDetailScreen(provider: provider)
                        .transition(.menuPush(forward: navigator.isForward))

                case .settings:
                    MenuBarSettingsScreen()
                        .transition(.menuPush(forward: navigator.isForward))

                case .about:
                    MenuBarAboutScreen()
                        .transition(.menuPush(forward: navigator.isForward))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: MenuStackHeightKey.self, value: proxy.size.height)
                }
            }
        }
        // A ScrollView is greedy by default, which would leave the dropdown padded
        // with dead space on short screens. Pinning it to the measured content
        // height keeps the window hugging the content until the ceiling is hit.
        .frame(height: min(max(stackHeight, 1), Metric.menuMaxContentHeight))
        .onPreferenceChange(MenuStackHeightKey.self) { height in
            MainActor.assumeIsolated {
                guard height > 0, abs(height - stackHeight) > 0.5 else { return }
                withAnimation(JellySprings.popover) { stackHeight = height }
            }
        }
    }
}
