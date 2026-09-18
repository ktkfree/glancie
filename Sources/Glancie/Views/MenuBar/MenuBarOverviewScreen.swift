import SwiftUI

/// Dropdown root: every active provider as one tappable row, then the
/// app-level commands.
///
/// Providers are gathered into a single inset plate rather than floating as
/// separate cards — with four or five of them, individual cards read as a pile of
/// unrelated tiles, while one plate with hairlines reads as a list.
public struct MenuBarOverviewScreen: View {
    @ObservedObject private var providerManager = ProviderManager.shared
    @ObservedObject private var navigator = MenuBarNavigator.shared

    public init() {}

    private var providers: [AIProviderType] {
        providerManager.activeProviders
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if providers.isEmpty {
                emptyState
            } else {
                InsetSection(L10n.providers.text, flushRows: true) {
                    ForEach(Array(providers.enumerated()), id: \.element) { index, provider in
                        if index > 0 { RowSeparator(inset: 46) }
                        providerRow(provider)
                    }
                }
            }

            commandSection
        }
    }

    // MARK: - Provider row

    private func providerRow(_ provider: AIProviderType) -> some View {
        let snapshot = providerManager.snapshots[provider]
        let isSimulated = snapshot?.isSimulated ?? true
        let pct = snapshot?.hourlyRemainingPercentage ?? 0.0
        let tier = UsageTier.from(pct)
        let isInUse = providerManager.isProviderInUse(provider)
        // Generating supersedes merely open: both at once reads as two claims
        // about the same thing.
        let showsAppBadge = !isInUse && providerManager.isAppRunning(provider)

        return MenuPlateRow(
            title: provider.displayName,
            subtitle: isSimulated ? (snapshot?.planName ?? snapshot?.unavailableText ?? L10n.notConnected.text) : (snapshot?.planName ?? "Standard Plan"),
            showsChevron: true,
            action: {
                SoundEffectsEngine.shared.playImpactFeedback()
                navigator.push(.providerDetail(provider))
            },
            leading: {
                RingGauge(
                    percentage: isSimulated ? 0 : pct,
                    gradientColors: isSimulated ? [Color.secondary.opacity(0.28), Color.secondary.opacity(0.16)] : tier.gradient,
                    size: 27,
                    lineWidth: 2.8
                ) {
                    Image(systemName: provider.sfSymbol)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSimulated ? Color.secondary.opacity(0.55) : tier.accent)
                }
            },
            trailing: {
                HStack(spacing: 6) {
                    if isInUse {
                        LiveStreamBadge()
                            .transition(.scale.combined(with: .opacity))
                    } else if showsAppBadge {
                        AppOpenBadge()
                            .transition(.scale.combined(with: .opacity))
                    }

                    if isSimulated {
                        Text("---")
                            .font(GlancieFont.rounded(13, .bold))
                            .foregroundStyle(Color.secondary.opacity(0.65))
                    } else {
                        RollingDigitsView(
                            value: Int(pct.rounded()),
                            suffix: "%",
                            font: GlancieFont.rounded(13, .bold),
                            color: tier.accent,
                            suffixFont: GlancieFont.rounded(9, .bold)
                        )
                    }
                }
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isSimulated
                ? L10n.providerNoData(provider.displayName, snapshot?.unavailableText ?? L10n.notConnected.text).text
                : L10n.providerRemaining(provider.displayName, Int(pct.rounded()), tier.label).text
                    + (isInUse ? L10n.suffixWorking.text : showsAppBadge ? L10n.suffixAppRunning.text : "")
        )
        .accessibilityHint(L10n.openQuotaDetail.text)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        InsetSection {
            VStack(spacing: 7) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)

                Text(L10n.noProvidersToShow.text)
                    .font(GlancieFont.rounded(12, .semibold))
                    .foregroundStyle(.primary)

                Text(L10n.pickProvidersInSettings.text)
                    .font(GlancieFont.rounded(10, .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                GlassActionButton(title: L10n.openSettings.text, symbol: "gearshape", isProminent: true) {
                    navigator.push(.settings)
                }
                .frame(width: 120)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Commands

    private var commandSection: some View {
        VStack(spacing: 1) {
            MenuCommandRow(
                title: providerManager.isRefreshing ? L10n.refreshing.text : L10n.refreshAll.text,
                symbol: "arrow.clockwise",
                shortcut: "⌘R",
                isBusy: providerManager.isRefreshing
            ) {
                SoundEffectsEngine.shared.playImpactFeedback()
                Task { await providerManager.refreshAll(forceSync: true) }
            }

            MenuCommandRow(
                title: L10n.settingsEllipsis.text,
                symbol: "gearshape",
                shortcut: "⌘,"
            ) {
                navigator.push(.settings)
            }

            MenuCommandRow(
                title: L10n.aboutGlancie.text,
                symbol: "info.circle",
                trailingText: "v\(GlancieBuild.version)",
                showsChevron: true
            ) {
                navigator.push(.about)
            }

            Rectangle()
                .fill(Surface.hairline)
                .frame(height: 0.5)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)

            MenuCommandRow(
                title: L10n.quitGlancie.text,
                symbol: "power",
                shortcut: "⌘Q",
                role: .destructive
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
