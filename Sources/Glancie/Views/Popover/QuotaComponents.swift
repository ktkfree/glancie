import SwiftUI

/// The one readout that answers "am I okay right now?" — a ring for the session
/// quota plus the wording and countdown that qualify it.
///
/// Shared by the tab bar's detail card and the menu bar's provider screen so the
/// same number never gets two different treatments.
public struct QuotaHeroView: View {
    public let percentage: Double
    public let caption: String
    public var resetCountdown: TimeInterval?
    public var isInUse: Bool
    public var ringSize: CGFloat
    public var isSimulated: Bool
    /// When the window this percentage was measured in rolled over, if it has.
    ///
    /// The figure then describes a window that no longer exists. Leaving it on
    /// screen is how a quota that refilled hours ago went on wearing the 임박
    /// badge — so it is withheld the same way an unread quota is, and the row
    /// that used to hold a countdown says when the reset happened instead.
    public var windowEndedAt: Date?

    public init(
        percentage: Double,
        caption: String = L10n.sessionQuota.text,
        resetCountdown: TimeInterval? = nil,
        isInUse: Bool = false,
        ringSize: CGFloat = 78,
        isSimulated: Bool = false,
        windowEndedAt: Date? = nil
    ) {
        self.percentage = percentage
        self.caption = caption
        self.resetCountdown = resetCountdown
        self.isInUse = isInUse
        self.ringSize = ringSize
        self.isSimulated = isSimulated
        self.windowEndedAt = windowEndedAt
    }

    private var tier: UsageTier { UsageTier.from(percentage) }

    /// Both reasons the ring shows no number: never measured, and measured for
    /// a window that has since ended.
    private var isWithheld: Bool { isSimulated || windowEndedAt != nil }

    private var placeholderCaption: String { isSimulated ? L10n.notConnectedShort.text : L10n.resetShort.text }

    private var withheldBadge: String { isSimulated ? L10n.noData.text : L10n.awaitingRemeasurement.text }

    public var body: some View {
        HStack(spacing: 14) {
            RingGauge(
                percentage: isWithheld ? 0 : percentage,
                gradientColors: isWithheld ? [Color.secondary.opacity(0.28), Color.secondary.opacity(0.16)] : tier.gradient,
                size: ringSize,
                lineWidth: ringSize * 0.105
            ) {
                VStack(spacing: -2) {
                    if isWithheld {
                        Text("---")
                            .font(GlancieFont.rounded(ringSize * 0.30, .bold))
                            .foregroundStyle(Color.secondary.opacity(0.65))
                        Text(placeholderCaption)
                            .font(GlancieFont.rounded(ringSize * 0.115, .semibold))
                            .foregroundStyle(.tertiary)
                    } else {
                        RollingDigitsView(
                            value: Int(percentage.rounded()),
                            suffix: "%",
                            font: GlancieFont.rounded(ringSize * 0.33, .bold),
                            color: .primary,
                            suffixFont: GlancieFont.rounded(ringSize * 0.16, .bold)
                        )
                        Text(L10n.remainingSuffix.text)
                            .font(GlancieFont.rounded(ringSize * 0.115, .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    if isWithheld {
                        Text(withheldBadge)
                            .font(GlancieFont.rounded(10, .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background {
                                Capsule().fill(Surface.plateFill)
                            }
                    } else {
                        TierBadge(tier: tier)
                    }
                    if isInUse {
                        LiveStreamBadge()
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Text(caption)
                    .font(GlancieFont.rounded(12.5, .bold))
                    .foregroundStyle(.primary)

                // A passed reset used to make the countdown nil, and a nil
                // countdown simply drew nothing — the one moment the user most
                // needs explaining was the one the card went quiet about.
                if let windowEndedAt {
                    resetRow(quotaResetAtText(windowEndedAt))
                } else if !isSimulated, let resetCountdown {
                    resetRow(quotaCountdownText(resetCountdown))
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private func resetRow(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 9.5, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
            Text(text)
                .font(GlancieFont.rounded(10.5, .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
    }

    private var accessibilityText: String {
        if isSimulated { return L10n.captionNoData(caption).text }
        if let windowEndedAt {
            return L10n.captionAwaiting(caption, quotaResetAtText(windowEndedAt)).text
        }
        return L10n.captionRemaining(caption, Int(percentage.rounded()), tier.label).text
    }
}

/// Horizontal quota bar with an inset track, duotone fill, specular sheen and an
/// optional pace reference notch.
///
/// The notch marks where usage *should* sit to last until reset, so fill short of
/// it means burning too fast. It is drawn as a light-cored dark tick rather than
/// a flat red line so it stays legible over both the filled and empty portions.
public struct QuotaBar: View {
    public let percentage: Double
    public let gradientColors: [Color]
    public var height: CGFloat
    public var paceMarkerPercentage: Double?

    public init(
        percentage: Double,
        gradientColors: [Color],
        height: CGFloat = 7,
        paceMarkerPercentage: Double? = nil
    ) {
        self.percentage = max(0, min(100, percentage))
        self.gradientColors = gradientColors
        self.height = height
        self.paceMarkerPercentage = paceMarkerPercentage
    }

    public var body: some View {
        GeometryReader { geo in
            let trackWidth = geo.size.width
            let fillWidth = max(0, min(trackWidth, trackWidth * CGFloat(percentage / 100.0)))

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Surface.track)
                    .frame(width: trackWidth, height: height)

                if fillWidth > 0.5 {
                    ZStack(alignment: .top) {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.45), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: height * 0.46)
                            .padding(.horizontal, height * 0.3)
                            .blendMode(.plusLighter)
                    }
                    .frame(width: fillWidth, height: height)
                    .shadow(color: (gradientColors.first ?? .clear).opacity(0.35), radius: 2.5, y: 0.5)
                }

                if let marker = paceMarkerPercentage, marker > 0, marker < 100 {
                    let markerX = trackWidth * CGFloat(marker / 100.0)
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 2, height: height + 4)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.65), lineWidth: 0.5)
                        }
                        .offset(x: markerX - 1)
                        .accessibilityLabel(L10n.suggestedPace(Int(marker)).text)
                }
            }
            .frame(height: max(height, height + 4), alignment: .center)
        }
        .frame(height: height + 4)
        .animation(JellySprings.gauge, value: percentage)
    }
}

/// A full-width quota meter: title and percentage, the bar, then the supporting
/// pace line and reset countdown.
public struct QuotaMeterRow: View {
    public let item: ModelQuotaItem

    public init(item: ModelQuotaItem) {
        self.item = item
    }

    private var tier: UsageTier { UsageTier.from(item.remainingPercentage) }
    private var isDepleted: Bool { item.remainingPercentage <= 0.0 && !isWithheld }
    /// This row's window has rolled over, so its figure is about a window that
    /// is gone. Without this the hero could read 리셋됨 while the row for the
    /// very same window still showed the old percentage two lines below it.
    private var endedAt: Date? { item.isWindowElapsed() ? item.resetAt : nil }
    private var isWithheld: Bool { endedAt != nil }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.name)
                    .font(GlancieFont.rounded(12, .semibold))
                    .foregroundStyle(isDepleted || isWithheld ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if isWithheld {
                    Text("---")
                        .font(GlancieFont.rounded(12.5, .bold))
                        .monospaced()
                        .foregroundStyle(Color.secondary.opacity(0.65))
                } else if isDepleted {
                    Text(L10n.empty.text)
                        .font(GlancieFont.rounded(10, .bold))
                        .foregroundStyle(tier.accent)
                } else {
                    RollingDigitsView(
                        value: Int(item.remainingPercentage.rounded()),
                        suffix: "%",
                        font: GlancieFont.rounded(12.5, .bold),
                        color: tier.accent,
                        suffixFont: GlancieFont.rounded(9, .bold)
                    )
                }
            }

            QuotaBar(
                percentage: isWithheld ? 0 : item.remainingPercentage,
                gradientColors: isWithheld
                    ? [Color.secondary.opacity(0.28), Color.secondary.opacity(0.16)]
                    : tier.gradient,
                height: 6.5,
                paceMarkerPercentage: isWithheld ? nil : item.paceMarkerPercentage
            )

            HStack(alignment: .top, spacing: 6) {
                Text(item.paceText?.isEmpty == false ? item.paceText! : item.quotaType)
                    .font(GlancieFont.rounded(9.5, .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                if let endedAt {
                    Text(quotaResetAtText(endedAt))
                        .font(GlancieFont.rounded(9.5, .semibold))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .fixedSize()
                } else if let reset = item.resetCountdown {
                    Text(quotaCountdownText(reset))
                        .font(GlancieFont.rounded(9.5, .semibold))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .fixedSize()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.modelQuotaAccessibility(item.name, item.quotaType, Int(item.remainingPercentage.rounded())).text)
    }
}

/// Dense single-line variant for the per-model list inside the detail card.
public struct ModelQuotaCompactRow: View {
    public let model: ModelQuotaItem

    @State private var isHovered: Bool = false

    public init(model: ModelQuotaItem) {
        self.model = model
    }

    private var tier: UsageTier { UsageTier.from(model.remainingPercentage) }

    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(LinearGradient(colors: tier.gradient, startPoint: .top, endPoint: .bottom))
                .frame(width: 6, height: 6)
                .shadow(color: tier.accent.opacity(0.55), radius: 2)

            VStack(alignment: .leading, spacing: 1.5) {
                Text(model.name)
                    .font(GlancieFont.rounded(11, .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(model.quotaType)
                    .font(GlancieFont.rounded(8.5, .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

            QuotaBar(
                percentage: model.remainingPercentage,
                gradientColors: tier.gradient,
                height: 4.5
            )
            .frame(width: 46)

            Text("\(Int(model.remainingPercentage.rounded()))%")
                .font(GlancieFont.rounded(10.5, .bold))
                .monospacedDigit()
                .foregroundStyle(tier.accent)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Surface.hoverWash : .clear)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.13)) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.modelQuotaAccessibility(model.name, model.quotaType, Int(model.remainingPercentage.rounded())).text)
    }
}

/// Compact glass action button used in card footers and action strips.
public struct GlassActionButton: View {
    public let title: String
    public let symbol: String
    public var isProminent: Bool
    public let action: () -> Void

    @State private var isHovered: Bool = false

    public init(
        title: String,
        symbol: String,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.isProminent = isProminent
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(GlancieFont.rounded(11, .semibold))
            }
            .foregroundStyle(isProminent ? Color.white : (isHovered ? Color.accentColor : Color.primary))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isProminent
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.82)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            : AnyShapeStyle(Surface.plateFill)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isHovered && !isProminent ? Surface.hoverWash : .clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(
                                isProminent ? Color.white.opacity(0.25) : Surface.plateRim,
                                lineWidth: 0.5
                            )
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(PressableStyle(pressedScale: 0.97, pressedOpacity: 0.85, haptics: false))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.13)) { isHovered = hovering }
        }
        .accessibilityLabel(title)
    }
}
