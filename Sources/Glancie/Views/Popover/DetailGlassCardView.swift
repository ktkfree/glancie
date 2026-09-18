import SwiftUI

/// Quota detail card that blooms out of the floating bar.
///
/// Ordered the way a detail screen should be: identity, then one hero readout
/// that answers "am I okay right now?", then inset plates for everything
/// secondary, then the two actions worth taking from here.
public struct DetailGlassCardView: View {
    @ObservedObject private var providerManager = ProviderManager.shared

    public let snapshot: UsageSnapshot
    public var onClose: () -> Void

    @State private var isCloseHovered: Bool = false

    public init(snapshot: UsageSnapshot, onClose: @escaping () -> Void) {
        self.snapshot = snapshot
        self.onClose = onClose
    }

    private var tier: UsageTier { UsageTier.from(snapshot.hourlyRemainingPercentage) }
    private var isInUse: Bool { providerManager.activeInUseProviders.contains(snapshot.provider) }
    private var isSimulated: Bool { snapshot.isSimulated }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

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
                ringSize: 76,
                isSimulated: isSimulated,
                windowEndedAt: snapshot.isHourlyWindowElapsed() ? snapshot.hourlyResetAt : nil
            )
            .padding(.horizontal, 2)

            if isSimulated {
                simulatedNoticeSection
            } else {
                weeklySection
                modelSection
            }
            actionStrip
        }
        .padding(14)
        .frame(width: Metric.detailWidth)
        .liquidGlass(
            cornerRadius: Radius.card,
            tint: isSimulated ? Color.secondary.opacity(0.15) : tier.accent,
            elevation: 1.35,
            tintStrength: isSimulated ? 0.2 : 0.5
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.quotaDetailFor(snapshot.provider.displayName).text)
    }

    private var simulatedNoticeSection: some View {
        let notice = (snapshot.unavailableReason ?? .notConfigured).notice
        return InsetSection(notice.header) {
            HStack(spacing: 10) {
                Image(systemName: notice.isFault ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(notice.isFault ? Color(hex: 0xFF9F0A) : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(notice.title)
                        .font(GlancieFont.rounded(11, .semibold))
                        .foregroundStyle(.primary)

                    Text(notice.detail)
                        .font(GlancieFont.rounded(9.5, .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 9) {
            IconTile(
                symbol: snapshot.provider.sfSymbol,
                colors: isSimulated ? [Color.secondary.opacity(0.4), Color.secondary.opacity(0.2)] : tier.gradient,
                size: 29
            )

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 5) {
                    Text(snapshot.provider.displayName)
                        .font(GlancieFont.rounded(14.5, .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let plan = snapshot.planName {
                        Text(plan)
                            .font(GlancieFont.rounded(9, .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(Surface.hoverWash)
                            }
                            .lineLimit(1)
                    }
                }

                Text(isSimulated ? L10n.noDataWithReason(snapshot.unavailableText).text : "\(snapshot.strategyUsed.rawValue) · \(relativeUpdateText(snapshot.lastUpdated))")
                    .font(GlancieFont.rounded(9.5, .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isCloseHovered ? .primary : .secondary)
                    .frame(width: 21, height: 21)
                    .background {
                        Circle()
                            .fill(isCloseHovered ? Surface.pressWash : Surface.plateFill)
                            .overlay {
                                Circle().strokeBorder(Surface.plateRim, lineWidth: 0.5)
                            }
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle(pressedScale: 0.88))
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { isCloseHovered = hovering }
            }
            .accessibilityLabel(L10n.close.text)
        }
    }

    // MARK: - Weekly

    @ViewBuilder
    private var weeklySection: some View {
        if let weekly = snapshot.weeklyRemainingPercentage {
            let weeklyTier = UsageTier.from(weekly)
            // The week closes as silently as the five hours did: past its reset
            // the figure describes a window that no longer exists.
            let endedAt = snapshot.isWeeklyWindowElapsed() ? snapshot.weeklyResetAt : nil

            InsetSection(L10n.weeklyQuota.text) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(L10n.weeklyRemaining.text)
                            .font(GlancieFont.rounded(11.5, .semibold))
                            .foregroundStyle(endedAt == nil ? .primary : .secondary)

                        Spacer(minLength: 4)

                        if endedAt == nil {
                            RollingDigitsView(
                                value: Int(weekly.rounded()),
                                suffix: "%",
                                font: GlancieFont.rounded(12.5, .bold),
                                color: weeklyTier.accent,
                                suffixFont: GlancieFont.rounded(9, .bold)
                            )
                        } else {
                            Text("---")
                                .font(GlancieFont.rounded(12.5, .bold))
                                .monospaced()
                                .foregroundStyle(Color.secondary.opacity(0.65))
                        }
                    }

                    QuotaBar(
                        percentage: endedAt == nil ? weekly : 0,
                        gradientColors: endedAt == nil
                            ? weeklyTier.gradient
                            : [Color.secondary.opacity(0.28), Color.secondary.opacity(0.16)],
                        height: 6.5
                    )

                    if let endedAt {
                        weeklyResetLine(quotaResetAtText(endedAt))
                    } else if let weeklyReset = snapshot.weeklyResetCountdown {
                        weeklyResetLine(L10n.resetLine(weeklyReset).text)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    endedAt == nil
                        ? L10n.weeklyQuotaAccessibility(Int(weekly.rounded()), weeklyTier.label).text
                        : L10n.weeklyQuotaAwaiting(quotaResetAtText(endedAt!)).text
                )
            }
        }
    }

    private func weeklyResetLine(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 8.5, weight: .bold))
            Text(text)
                .font(GlancieFont.rounded(9.5, .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.tertiary)
    }

    // MARK: - Per-model

    @ViewBuilder
    private var modelSection: some View {
        if !snapshot.modelQuotas.isEmpty {
            InsetSection(L10n.remainingByModel.text, flushRows: true) {
                ForEach(Array(snapshot.modelQuotas.enumerated()), id: \.element.id) { index, model in
                    if index > 0 { RowSeparator(inset: 22) }
                    ModelQuotaCompactRow(model: model)
                }
            }
        }
    }

    // MARK: - Actions

    private var actionStrip: some View {
        HStack(spacing: 7) {
            if let dashboard = snapshot.provider.accountDashboardURL {
                GlassActionButton(title: L10n.dashboard.text, symbol: "chart.bar.doc.horizontal") {
                    NSWorkspace.shared.open(dashboard)
                }
            }

            GlassActionButton(
                title: providerManager.isRefreshing ? L10n.updating.text : L10n.refresh.text,
                symbol: "arrow.clockwise",
                isProminent: true
            ) {
                SoundEffectsEngine.shared.playImpactFeedback()
                Task { await providerManager.refreshProvider(snapshot.provider, forceSync: true) }
            }
            .disabled(providerManager.isRefreshing)
        }
    }
}
