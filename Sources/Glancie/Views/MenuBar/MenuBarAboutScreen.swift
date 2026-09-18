import SwiftUI
import AppKit

/// What Glancie is, who made it, and what else they have shipped.
///
/// A pushed screen rather than `orderFrontStandardAboutPanel`, which opened a
/// separate window the menu had no say over — wrong for an app whose whole
/// surface is this dropdown, and with nowhere to put anything but a version
/// number.
public struct MenuBarAboutScreen: View {
    @ObservedObject private var navigator = MenuBarNavigator.shared
    @ObservedObject private var localization = Localization.shared

    public init() {}

    /// The lab's own accent, lightened for Dark Mode where the print-weight
    /// orange goes muddy against a near-black plate.
    private static let labAccent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.898, green: 0.514, blue: 0.290, alpha: 1)
            : NSColor(srgbRed: 0.753, green: 0.373, blue: 0.094, alpha: 1)
    })

    /// The same accent as a fill under white text. Kept separate from
    /// `labAccent` because the Dark Mode value there is lightened for legibility
    /// as text, and white on it would sit near 2.6:1.
    private static let labAccentFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.745, green: 0.361, blue: 0.188, alpha: 1)
            : NSColor(srgbRed: 0.753, green: 0.373, blue: 0.094, alpha: 1)
    })

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MenuScreenHeader(title: L10n.about.text) {
                navigator.popToRoot()
            }

            identityBlock
            appSection
            makerSection
            productsSection
        }
    }

    // MARK: - Glancie itself

    private var identityBlock: some View {
        VStack(spacing: 7) {
            appIcon
                .frame(width: 52, height: 52)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Glancie")
                    .font(GlancieFont.title)
                    .foregroundStyle(.primary)

                Text(GlancieBuild.version)
                    .font(GlancieFont.caption)
                    .foregroundStyle(.secondary)
            }

            Text(L10n.glancieTagline.text)
                .font(GlancieFont.rounded(11, .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    /// The bundle's own icon, so the screen shows what the user sees in the
    /// Dock and Finder rather than a second drawing of it that can drift.
    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSApplication.shared.applicationIconImage {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            IconTile(symbol: "sparkles", colors: [Color(hex: 0x0A84FF), Color(hex: 0x0050C7)], size: 52)
        }
    }

    private var appSection: some View {
        InsetSection(flushRows: true) {
            MenuCommandRow(
                title: L10n.viewSourceOnGitHub.text,
                symbol: "chevron.left.forwardslash.chevron.right"
            ) {
                SoundEffectsEngine.shared.playSelectionFeedback()
                NSWorkspace.shared.open(MakerShowcase.sourceURL)
            }

            RowSeparator(inset: 24)

            HStack(spacing: 9) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 11.5, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary.opacity(0.75))
                    .frame(width: 15)

                Text(L10n.license.text)
                    .font(GlancieFont.rounded(11.5, .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 6)

                Text("MIT")
                    .font(GlancieFont.rounded(10.5, .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - The maker

    private var makerSection: some View {
        InsetSection(L10n.theMaker.text) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                        .fill(Self.labAccent)
                        .frame(width: 26, height: 26)
                        .overlay {
                            Image(systemName: "flask")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.makerName.text)
                            .font(GlancieFont.rounded(12, .bold))
                            .foregroundStyle(.primary)

                        Text(L10n.makerSite.text)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)
                }
                .accessibilityElement(children: .combine)

                Text(L10n.makerTagline.text)
                    .font(.system(size: 14.5, weight: .semibold, design: .serif))
                    .foregroundStyle(Self.labAccent)
                    .padding(.top, 11)
                    .padding(.bottom, 5)
                    .fixedSize(horizontal: false, vertical: true)

                Text(L10n.makerBio.text)
                    .font(GlancieFont.rounded(10.5, .medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    statChip(value: String(format: "%02d", MakerShowcase.products.count), label: L10n.makerStatProducts.text)
                    statChip(value: String(format: "%02d", MakerShowcase.liveCount), label: L10n.makerStatLive.text)
                    statChip(value: nil, label: L10n.makerLocation.text)
                }
                .padding(.top, 10)
                .padding(.bottom, 11)

                LabButton(title: L10n.enterTheLab.text, fill: Self.labAccentFill) {
                    SoundEffectsEngine.shared.playImpactFeedback()
                    NSWorkspace.shared.open(MakerShowcase.siteURL)
                }
            }
        }
    }

    private func statChip(value: String?, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if let value {
                Text(value)
                    .font(GlancieFont.rounded(11, .bold))
                    .foregroundStyle(.primary)
            }

            Text(label)
                .font(GlancieFont.rounded(9.5, .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Surface.hoverWash)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - The maker's other work

    private var productsSection: some View {
        InsetSection(L10n.otherProducts.text, flushRows: true) {
            ForEach(Array(MakerShowcase.products.enumerated()), id: \.element.id) { index, product in
                if index > 0 {
                    RowSeparator(inset: 33)
                }
                ProductRow(product: product)
            }
        }
    }
}

/// One of the maker's products, as a row that opens it.
private struct ProductRow: View {
    let product: MakerProduct

    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            SoundEffectsEngine.shared.playSelectionFeedback()
            NSWorkspace.shared.open(product.url)
        } label: {
            HStack(spacing: 9) {
                IconTile(symbol: product.category.symbol, colors: product.category.colors, size: 22)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(product.name)
                            .font(GlancieFont.rounded(11.5, .semibold))
                            .foregroundStyle(isHovered ? Color.white : .primary)

                        if product.isExperimental {
                            Text(L10n.experimental.text)
                                .font(GlancieFont.rounded(8.5, .bold))
                                .foregroundStyle(isHovered ? Color.white.opacity(0.8) : .secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background {
                                    Capsule().fill(isHovered ? Color.white.opacity(0.18) : Surface.hoverWash)
                                }
                        }
                    }

                    Text(product.summary)
                        .font(GlancieFont.rounded(9.5, .medium))
                        .foregroundStyle(isHovered ? Color.white.opacity(0.72) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 6)

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(isHovered ? Color.white.opacity(0.72) : .secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: Radius.menuRow, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: Radius.menuRow, style: .continuous)
                    .fill(isHovered ? Color.accentColor : .clear)
            }
        }
        .buttonStyle(PressableStyle(pressedScale: 0.985, haptics: false))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(product.name), \(product.summary)")
    }
}

/// `GlassActionButton` in the lab's colour.
///
/// Not a parameter on that one: its prominent style is the system accent
/// everywhere else in the app, and one screen borrowing it for a different brand
/// would make the shared component answer to two ideas at once.
private struct LabButton: View {
    let title: String
    let fill: Color
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(GlancieFont.rounded(11, .semibold))
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fill)
                    .brightness(isHovered ? 0.05 : 0)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(PressableStyle(pressedScale: 0.97))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}
