import SwiftUI

/// Drill-down for one provider: who the account is, one hero readout, every
/// quota meter, then the actions that only make sense for this provider.
public struct MenuBarProviderDetailScreen: View {
    @ObservedObject private var providerManager = ProviderManager.shared
    @ObservedObject private var navigator = MenuBarNavigator.shared
    @ObservedObject private var preferences = GlanciePreferences.shared

    public let provider: AIProviderType

    public init(provider: AIProviderType) {
        self.provider = provider
    }

    private var snapshot: UsageSnapshot {
        providerManager.snapshots[provider]
            ?? UsageSnapshot(provider: provider, hourlyRemainingPercentage: 100.0)
    }

    private var isInUse: Bool { providerManager.isProviderInUse(provider) }

    private var quotas: [ModelQuotaItem] {
        snapshot.modelQuotas.isEmpty ? Self.fallbackQuotas(for: snapshot) : snapshot.modelQuotas
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            MenuScreenHeader(
                title: provider.displayName,
                // `capturedAt` is when the figures were measured; `lastUpdated`
                // would also move for a restored reading and overstate freshness.
                trailingText: relativeUpdateText(snapshot.capturedAt)
            ) {
                navigator.popToRoot()
            }

            identityHeader

            if !accounts.isEmpty {
                accountSection
            }

            if let error = snapshot.fetchError {
                Label(L10n.refreshFailed(error).text + (snapshot.isSimulated ? "" : L10n.showingLastMeasurement.text),
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            QuotaHeroView(
                percentage: snapshot.hourlyRemainingPercentage,
                caption: snapshot.hourlyQuotaName ?? L10n.sessionQuota.text,
                resetCountdown: snapshot.hourlyResetCountdown,
                isInUse: isInUse,
                ringSize: 74,
                isSimulated: snapshot.isSimulated,
                windowEndedAt: snapshot.isHourlyWindowElapsed() ? snapshot.hourlyResetAt : nil
            )
            .padding(.horizontal, 2)

            if snapshot.isSimulated {
                InsetSection(L10n.connectionStatus.text) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xFF9F0A))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.guidanceTitleNotConfigured.text)
                                .font(GlancieFont.rounded(11, .semibold))
                                .foregroundStyle(.primary)

                            Text(L10n.checkSignInState.text)
                                .font(GlancieFont.rounded(9.5, .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                InsetSection(L10n.quotaDetail.text, footnote: L10n.quotaDetailFootnote.text) {
                    ForEach(Array(quotas.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            RowSeparator(inset: 0)
                                .padding(.vertical, 2)
                        }
                        QuotaMeterRow(item: item)
                    }
                }
            }

            actionSection
        }
        // Drilling in is a request for this provider's current figures, so it
        // reads past the cache the same way the refresh button does.
        .task { await providerManager.refreshOnDemand([provider], trigger: .userAction) }
    }

    // MARK: - Accounts

    private var accounts: [ResolvedAccount] {
        providerManager.accounts(for: provider)
    }

    /// The account the meters above describe.
    private var displayedAccount: ResolvedAccount? {
        providerManager.displayedAccount(for: provider)
    }

    private var identityHeader: some View {
        HStack(spacing: 9) {
            IconTile(
                symbol: provider.sfSymbol,
                colors: UsageTier.from(snapshot.hourlyRemainingPercentage).gradient,
                size: 27
            )

            VStack(alignment: .leading, spacing: 1.5) {
                Text(displayedAccount?.planName ?? snapshot.planName ?? provider.displayName)
                    .font(GlancieFont.rounded(12.5, .bold))
                    .foregroundStyle(.primary)

                Text(headerSubtitle)
                    .font(GlancieFont.rounded(10, .medium))
                    .foregroundStyle(snapshot.isStale ? Color(hex: 0xFF9F0A) : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            Text(snapshot.strategyUsed.rawValue)
                .font(GlancieFont.rounded(9, .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background {
                    Capsule(style: .continuous)
                        .fill(Surface.hoverWash)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Surface.plateRim, lineWidth: 0.5)
                        }
                }
                .help(L10n.howThisWasRead.text)
        }
    }

    /// Says how old the hero figure is when it has gone stale, and who it belongs
    /// to otherwise — never an invented address when no account was found.
    private var headerSubtitle: String {
        if snapshot.isStale {
            return accountReadingAgeText(snapshot.capturedAt)
        }
        if let label = displayedAccount?.label(masked: preferences.maskAccountEmails) {
            return label
        }
        if let email = snapshot.accountEmail {
            return email
        }
        return L10n.noSignInFound.text
    }

    /// Every login found for this provider.
    ///
    /// More than one row is not a redundancy. Quota belongs to the account, so
    /// two accounts are two quotas — and the meters above describe only the one
    /// marked as displayed. The running badge is the separate question of which
    /// of them is working right now.
    private var accountSection: some View {
        InsetSection(
            L10n.accounts.text,
            footnote: accounts.count > 1
                ? L10n.accountsFootnoteAttribution.text
                : nil
        ) {
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 {
                    RowSeparator(inset: 30)
                }
                accountRow(account)
            }
        }
    }

    private func accountRow(_ account: ResolvedAccount) -> some View {
        let reading = providerManager.bestKnownSnapshot(for: provider, accountID: account.id)
        let isDisplayed = account.id == displayedAccount?.id
        let isRunning = providerManager.isAccountRunning(provider: provider, accountID: account.id)

        // Name what is running rather than just that something is: "App" and
        // "CLI" are different answers for the same account.
        let openApps = providerManager.runningApps(for: account)
        let runningLabel: String? = {
            if !openApps.isEmpty {
                var seen = Set<AccountSourceKind>()
                return openApps
                    .map(\.kind)
                    .filter { seen.insert($0).inserted }
                    .map(\.badgeText)
                    .joined(separator: " · ")
            }
            return isRunning ? "CLI" : nil
        }()

        return AccountRow(
            label: account.label(masked: preferences.maskAccountEmails),
            planName: account.planName,
            organization: account.organization,
            sourceBadge: account.sourceBadgeText,
            sourceSymbol: account.sources.first?.kind.symbol ?? "person",
            isDisplayed: isDisplayed,
            isRunning: isRunning,
            runningLabel: runningLabel,
            usageReadable: account.usageReadable,
            // A figure from a window that has already rolled over is not this
            // account's current usage; the row shows no percentage rather than
            // last window's.
            remainingPercentage: (reading?.isHourlyWindowElapsed() ?? false)
                ? nil
                : reading?.hourlyRemainingPercentage,
            readingCapturedAt: (reading?.isStale ?? false) ? reading?.capturedAt : nil
        )
    }

    // MARK: - Actions

    private var actionSection: some View {
        VStack(spacing: 1) {
            MenuCommandRow(
                title: L10n.refreshThisProvider.text,
                symbol: "arrow.clockwise",
                isBusy: providerManager.isRefreshing
            ) {
                SoundEffectsEngine.shared.playImpactFeedback()
                Task { await providerManager.refreshProvider(provider, forceSync: true) }
            }

            if let dashboard = provider.accountDashboardURL {
                MenuCommandRow(
                    title: L10n.planUsageDashboard.text,
                    symbol: "chart.bar.doc.horizontal",
                    showsChevron: true
                ) {
                    NSWorkspace.shared.open(dashboard)
                }
            }

            if let status = provider.statusPageURL {
                MenuCommandRow(
                    title: L10n.serviceStatusPage.text,
                    symbol: "waveform.path.ecg",
                    showsChevron: true
                ) {
                    NSWorkspace.shared.open(status)
                }
            }

            MenuCommandRow(
                title: L10n.providerSettingsEllipsis.text,
                symbol: "slider.horizontal.3"
            ) {
                navigator.push(.settings)
            }
        }
    }

    // MARK: - Fallback

    /// Adapters that only report a single figure still deserve a session and a
    /// weekly meter, so the screen never renders an empty section.
    private static func fallbackQuotas(for snapshot: UsageSnapshot) -> [ModelQuotaItem] {
        var items: [ModelQuotaItem] = [
            ModelQuotaItem(
                name: L10n.providerSession(snapshot.provider.shortName).text,
                remainingPercentage: snapshot.hourlyRemainingPercentage,
                quotaType: "5-Hour Session",
                resetCountdown: snapshot.hourlyResetCountdown,
                resetAt: snapshot.hourlyResetAt
            )
        ]

        if let weekly = snapshot.weeklyRemainingPercentage {
            items.append(
                ModelQuotaItem(
                    name: L10n.providerWeekly(snapshot.provider.shortName).text,
                    remainingPercentage: weekly,
                    quotaType: "Weekly Limit",
                    resetCountdown: snapshot.weeklyResetCountdown,
                    resetAt: snapshot.weeklyResetAt
                )
            )
        }

        return items
    }
}
