import SwiftUI

/// iOS Settings-style icon tile: a small squircle filled with a duotone gradient
/// and a white glyph. Gives every row an anchor point and a splash of color.
public struct IconTile: View {
    public let symbol: String
    public let colors: [Color]
    public var size: CGFloat

    public init(symbol: String, colors: [Color], size: CGFloat = 20) {
        self.symbol = symbol
        self.colors = colors
        self.size = size
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.42), Color.white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.22), radius: 0.5, y: 0.5)
            }
            .frame(width: size, height: size)
            .shadow(color: (colors.last ?? .clear).opacity(0.32), radius: 2.5, y: 1.5)
            .accessibilityHidden(true)
    }
}

/// iOS "inset grouped" container — a soft raised plate that gathers related rows.
public struct InsetSection<Content: View>: View {
    public var title: String?
    public var footnote: String?
    /// Rows that manage their own horizontal insets (hover highlights need to
    /// bleed to the plate edge) opt out of the plate's own padding.
    public var flushRows: Bool
    private let content: Content

    public init(
        _ title: String? = nil,
        footnote: String? = nil,
        flushRows: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footnote = footnote
        self.flushRows = flushRows
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let title {
                // Grouped lists read correctly only when a header sits closer to the
                // plate it labels than to whatever precedes it.
                Text(title)
                    .sectionHeaderStyle()
                    .padding(.leading, 4)
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: flushRows ? 0 : 8) {
                content
            }
            .padding(.horizontal, flushRows ? 0 : 10)
            .padding(.vertical, flushRows ? 4 : 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.section, style: .continuous)
                        .fill(Surface.plateFill)
                    RoundedRectangle(cornerRadius: Radius.section, style: .continuous)
                        .strokeBorder(Surface.plateRim, lineWidth: 0.5)
                }
            }

            if let footnote {
                Text(footnote)
                    .font(GlancieFont.rounded(9.5, .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Inset hairline between rows inside a section, matching system list separators.
public struct RowSeparator: View {
    public var inset: CGFloat

    public init(inset: CGFloat = 28) {
        self.inset = inset
    }

    public var body: some View {
        Rectangle()
            .fill(Surface.hairline)
            .frame(height: 0.5)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

/// Status pill: tier color, tier glyph, tier wording. Never color alone.
public struct TierBadge: View {
    public let tier: UsageTier
    public var compact: Bool

    public init(tier: UsageTier, compact: Bool = false) {
        self.tier = tier
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: tier.symbol)
                .font(.system(size: compact ? 7 : 8, weight: .black))
            Text(tier.label)
                .font(GlancieFont.rounded(compact ? 9 : 10, .bold))
        }
        .foregroundStyle(tier.accent)
        .padding(.horizontal, compact ? 5.5 : 7)
        .padding(.vertical, compact ? 2 : 3)
        .background {
            Capsule(style: .continuous)
                .fill(tier.accent.opacity(0.15))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(tier.accent.opacity(0.32), lineWidth: 0.5)
                }
        }
        .accessibilityLabel(tier.label)
    }
}

/// Pulsing "AI is generating right now" pill. Motion is what makes it read as
/// live; the dot alone is indistinguishable from a static status colour.
public struct LiveStreamBadge: View {
    @State private var pulse: Bool = false

    public init() {}

    private static let live = Color(hex: 0x30D158)

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Self.live)
                .frame(width: 5, height: 5)
                .shadow(color: Self.live.opacity(0.85), radius: pulse ? 3.5 : 1.5)
                .scaleEffect(pulse ? 1.18 : 0.86)

            Text(L10n.working.text)
                .font(GlancieFont.rounded(9, .bold))
                .foregroundStyle(Self.live)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background {
            Capsule(style: .continuous)
                .fill(Self.live.opacity(0.14))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Self.live.opacity(0.30), lineWidth: 0.5)
                }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityLabel(L10n.aiTaskInProgress.text)
    }
}

/// "The desktop app is open" pill.
///
/// Static where `LiveStreamBadge` pulses, and that difference is the point: an
/// app being open is a standing fact, not an event, and animating it would claim
/// activity the workspace never reported.
public struct AppOpenBadge: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 3.5) {
            Image(systemName: "macwindow")
                .font(.system(size: 8, weight: .bold))

            Text(L10n.appOpen.text)
                .font(GlancieFont.rounded(9, .bold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                }
        }
        .accessibilityLabel(L10n.desktopAppRunning.text)
    }
}

/// Human-readable countdown ("2일 4시간 후", "1시간 26분 후", "12분 후").
public func quotaCountdownText(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let days = total / 86400
    let hours = (total % 86400) / 3600
    let minutes = (total % 3600) / 60

    if days > 0 { return hours > 0 ? L10n.countdownDaysHours(days, hours).text : L10n.countdownDays(days).text }
    if hours > 0 { return minutes > 0 ? L10n.countdownHoursMinutes(hours, minutes).text : L10n.countdownHours(hours).text }
    if minutes > 0 { return L10n.countdownMinutes(minutes).text }
    return L10n.countdownSoon.text
}

/// Wording for a window whose reset has already happened.
///
/// The counterpart to `quotaCountdownText`: past that moment there is no
/// interval left to count down, and saying nothing — which is what a nil
/// countdown used to produce — leaves the reader to assume the figure beside it
/// still stands.
public func quotaResetAtText(_ date: Date) -> String {
    L10n.resetAtTime(date.formatted(date: .omitted, time: .shortened)).text
}

/// Relative "last synced" wording shared by every surface that shows freshness.
public func relativeUpdateText(_ date: Date) -> String {
    let elapsed = Int(Date().timeIntervalSince(date))
    if elapsed < 60 { return L10n.updatedJustNow.text }
    if elapsed < 3600 { return L10n.updatedMinutesAgo(elapsed / 60).text }
    return L10n.updatedHoursAgo(elapsed / 3600).text
}
