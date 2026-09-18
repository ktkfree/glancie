import SwiftUI

/// A provider "chip" inside the floating bar: an Activity-ring wrapping the
/// provider glyph, plus an odometer percentage. The chip carries a permanent
/// tint of its quota tier so the bar is readable in a single glance, and lifts
/// into a filled state when selected.
public struct ProviderSegmentView: View {
    @ObservedObject private var providerManager = ProviderManager.shared
    
    public let snapshot: UsageSnapshot
    public var isSelected: Bool
    public var onTap: () -> Void

    @State private var isHovered: Bool = false
    @State private var pulsePhase: Bool = false

    public init(
        snapshot: UsageSnapshot,
        isSelected: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.isSelected = isSelected
        self.onTap = onTap
    }

    private var tier: UsageTier { UsageTier.from(snapshot.remainingPercentage) }
    private var percent: Int { Int(snapshot.remainingPercentage.rounded()) }
    /// Both reasons this chip has no figure to show: nothing was measured, and
    /// what was measured belonged to a window that has since rolled over. The
    /// bar is where a stale percentage does the most damage — a quota that
    /// refilled hours ago sat here in alarm red, which is the one reading a
    /// glance bar exists to get right.
    private var isWithheld: Bool { snapshot.isSimulated || snapshot.isHourlyWindowElapsed() }

    private var isInUse: Bool {
        providerManager.activeInUseProviders.contains(snapshot.provider)
    }

    /// Whose quota this chip is showing. Read off the snapshot rather than the
    /// registry so the label can never name an account the figures do not
    /// actually belong to.
    private var accountLabel: String? {
        guard let email = snapshot.accountEmail, !email.isEmpty else { return nil }
        guard GlanciePreferences.shared.maskAccountEmails,
              let atIndex = email.firstIndex(of: "@"), atIndex > email.startIndex else {
            return email
        }
        return "\(email[email.startIndex..<atIndex].prefix(1))***\(email[atIndex...])"
    }

    /// The chip itself stays purely a percentage — the account only appears on
    /// hover, where it costs no space in the bar.
    private var tooltip: String {
        if snapshot.isSimulated {
            return L10n.segmentNotConnected(snapshot.provider.displayName).text
        }
        if isWithheld {
            return L10n.segmentLimitReset(snapshot.provider.displayName).text
        }
        var parts = [L10n.segmentRemaining(snapshot.provider.displayName, percent).text]
        if let accountLabel { parts.append(accountLabel) }
        if let plan = snapshot.planName { parts.append(plan) }
        if snapshot.isStale { parts.append(accountReadingAgeText(snapshot.capturedAt)) }
        return parts.joined(separator: "\n")
    }

    private var accessibilityValueText: String {
        if snapshot.isSimulated { return L10n.segmentNoData(snapshot.unavailableText).text }
        if isWithheld { return L10n.limitResetAwaiting.text }
        return L10n.remainingPercentTier(percent, tier.label).text + (isInUse ? L10n.suffixCurrentlyWorking.text : "")
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                ZStack {
                    // 1. Glowing outer aura when AI is actively streaming/generating
                    if isInUse {
                        Circle()
                            .stroke(
                                RadialGradient(
                                    colors: [tier.accent.opacity(0.8), tier.accent.opacity(0.1)],
                                    center: .center,
                                    startRadius: 8,
                                    endRadius: 16
                                ),
                                lineWidth: 2.0
                            )
                            .frame(width: 25, height: 25)
                            .scaleEffect(pulsePhase ? 1.28 : 1.0)
                            .opacity(pulsePhase ? 0.9 : 0.35)
                            .blur(radius: pulsePhase ? 1.0 : 0.2)
                            .allowsHitTesting(false)
                    }
                    
                    // 2. Main Ring Gauge
                    RingGauge(
                        percentage: isWithheld ? 0 : snapshot.remainingPercentage,
                        gradientColors: isWithheld ? [Color.secondary.opacity(0.28), Color.secondary.opacity(0.16)] : tier.gradient,
                        size: 19,
                        lineWidth: 2.4
                    ) {
                        Image(systemName: snapshot.provider.sfSymbol)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(isSelected || isInUse ? tier.accent : Color.primary.opacity(isWithheld ? 0.45 : 0.82))
                    }
                    
                    // 3. Mini Live Streaming Beacon Dot (Top-Right of Ring)
                    if isInUse {
                        Circle()
                            .fill(Color(hex: 0x34C759)) // Vibrant Live Green
                            .frame(width: 5, height: 5)
                            .shadow(color: Color(hex: 0x34C759).opacity(0.9), radius: 3)
                            .scaleEffect(pulsePhase ? 1.15 : 0.85)
                            .offset(x: 8, y: -8)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: 20, height: 20)
                .onAppear {
                    if isInUse {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                            pulsePhase = true
                        }
                    }
                }
                .onChange(of: isInUse) { _, active in
                    if active {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                            pulsePhase = true
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.4)) {
                            pulsePhase = false
                        }
                    }
                }

                // Fixed-width percentage container so 100%, 80%, 0%, --- never truncate or shift chip size
                Group {
                    if isWithheld {
                        Text("---")
                            .font(GlancieFont.rounded(11.5, .semibold))
                            .monospaced()
                            .foregroundStyle(Color.secondary.opacity(0.65))
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 0.5) {
                            Text("\(percent)")
                                .font(GlancieFont.barValue)
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(percent)))
                            
                            Text("%")
                                .font(GlancieFont.rounded(8, .semibold))
                                .opacity(0.55)
                        }
                        .foregroundStyle(isInUse ? tier.accent : .primary.opacity(isSelected ? 1.0 : 0.92))
                    }
                }
                .frame(width: 33, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 66, height: 24)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .fill(
                            isSelected
                                ? (isWithheld ? Surface.pressWash : tier.accent.opacity(0.18))
                                : (isInUse
                                    ? tier.accent.opacity(pulsePhase ? 0.14 : 0.07)
                                    : Surface.hoverWash.opacity(isHovered ? 1.0 : 0.45))
                        )

                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? (isWithheld ? Surface.shellRim : tier.accent.opacity(0.85))
                                : (isInUse
                                    ? tier.accent.opacity(pulsePhase ? 0.75 : 0.35)
                                    : Surface.shellRim.opacity(isHovered ? 1.0 : 0.5)),
                            lineWidth: isInUse || isSelected ? 1.0 : 0.75
                        )
                }
            }
            .shadow(
                color: isInUse ? tier.accent.opacity(0.25) : (isSelected ? Color.black.opacity(0.15) : .clear),
                radius: isInUse ? 4 : 3,
                x: 0,
                y: 1.0
            )
            .scaleEffect(isHovered && !isSelected ? 1.03 : 1.0)
            .animation(JellySprings.hover, value: isHovered)
            .animation(JellySprings.hover, value: isSelected)
        }
        .buttonStyle(PressableStyle(pressedScale: 0.94))
        .onHover { isHovered = $0 }
        .help(tooltip)
        .accessibilityLabel(
            accountLabel.map { "\(snapshot.provider.displayName), \($0)" }
                ?? snapshot.provider.displayName
        )
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint(L10n.openQuotaCard.text)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
