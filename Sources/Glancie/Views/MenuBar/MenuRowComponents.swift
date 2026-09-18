import SwiftUI

/// What a command row means, which decides its highlight colour and label tint.
public enum MenuRowRole {
    case standard
    case destructive

    var highlight: Color {
        switch self {
        case .standard: return .accentColor
        case .destructive: return Color(hex: 0xFF453A)
        }
    }

    var restingLabel: Color {
        switch self {
        case .standard: return .primary
        case .destructive: return Color(hex: 0xFF453A)
        }
    }
}

/// A system menu command row.
///
/// The hover highlight is the whole point: macOS menus fill the hovered row with
/// the user's accent colour and flip the label to white. Without it a dropdown
/// reads as a web page in a window no matter how good the material is.
public struct MenuCommandRow: View {
    public let title: String
    public var symbol: String?
    public var shortcut: String?
    public var trailingText: String?
    public var showsChevron: Bool
    public var role: MenuRowRole
    /// Spins the leading glyph, for commands that are already running.
    public var isBusy: Bool
    public let action: () -> Void

    @State private var isHovered: Bool = false
    @State private var spin: Double = 0

    public init(
        title: String,
        symbol: String? = nil,
        shortcut: String? = nil,
        trailingText: String? = nil,
        showsChevron: Bool = false,
        role: MenuRowRole = .standard,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.trailingText = trailingText
        self.showsChevron = showsChevron
        self.role = role
        self.isBusy = isBusy
        self.action = action
    }

    private var labelColor: Color {
        isHovered ? .white : role.restingLabel
    }

    private var secondaryColor: Color {
        isHovered ? Color.white.opacity(0.72) : Color.secondary
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11.5, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isHovered ? Color.white : role.restingLabel.opacity(0.75))
                        .frame(width: 15, alignment: .center)
                        .rotationEffect(.degrees(isBusy ? spin : 0))
                }

                Text(title)
                    .font(GlancieFont.rounded(12, .medium))
                    .foregroundStyle(labelColor)

                Spacer(minLength: 6)

                if let shortcut {
                    Text(shortcut)
                        .font(GlancieFont.rounded(10.5, .medium))
                        .foregroundStyle(secondaryColor)
                        .monospacedDigit()
                } else if let trailingText {
                    Text(trailingText)
                        .font(GlancieFont.rounded(10, .medium))
                        .foregroundStyle(secondaryColor)
                } else if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(secondaryColor)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Radius.menuRow, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                role.highlight.opacity(isHovered ? 0.95 : 0),
                                role.highlight.opacity(isHovered ? 0.82 : 0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.menuRow, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .onChange(of: isBusy) { _, busy in
            if busy {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    spin = 360
                }
            } else {
                spin = 0
            }
        }
        .accessibilityLabel(title)
    }
}

/// A content row inside an inset plate. Lifts on hover instead of taking a full
/// accent fill, because plates carry data rather than commands.
public struct MenuPlateRow<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing
    public var title: String
    public var subtitle: String?
    public var showsChevron: Bool
    public var action: (() -> Void)?

    @State private var isHovered: Bool = false

    public init(
        title: String,
        subtitle: String? = nil,
        showsChevron: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsChevron = showsChevron
        self.action = action
        self.leading = leading()
        self.trailing = trailing()
    }

    private var rowBody: some View {
        HStack(spacing: 9) {
            leading

            VStack(alignment: .leading, spacing: 1.5) {
                Text(title)
                    .font(GlancieFont.rounded(12.5, .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(GlancieFont.rounded(10, .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 6)

            trailing

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1.0 : 0.55)
                    .offset(x: isHovered ? 1.5 : 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Surface.hoverWash : Color.clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    public var body: some View {
        Group {
            if let action {
                Button(action: action) { rowBody }
                    .buttonStyle(.plain)
            } else {
                rowBody
            }
        }
        .onHover { hovering in
            guard action != nil else { return }
            withAnimation(.easeOut(duration: 0.13)) { isHovered = hovering }
        }
    }
}

/// Navigation header for a pushed screen: a back affordance on the left, the
/// screen title centred in the optical sense, and optional trailing metadata.
public struct MenuScreenHeader: View {
    public let backTitle: String
    public let title: String
    public var trailingText: String?
    public let onBack: () -> Void

    @State private var isHovered: Bool = false

    public init(
        backTitle: String = L10n.overview.text,
        title: String,
        trailingText: String? = nil,
        onBack: @escaping () -> Void
    ) {
        self.backTitle = backTitle
        self.title = title
        self.trailingText = trailingText
        self.onBack = onBack
    }

    public var body: some View {
        ZStack {
            // Centred title with the controls overlaid, so the title stays optically
            // centred regardless of how wide the back label or timestamp become.
            Text(title)
                .font(GlancieFont.rounded(12.5, .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .padding(.horizontal, 78)

            HStack(spacing: 8) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text(backTitle)
                            .font(GlancieFont.rounded(11.5, .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isHovered ? Color.accentColor.opacity(0.14) : .clear)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(PressableStyle(pressedScale: 0.96, haptics: false))
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
                }

                Spacer(minLength: 4)

                if let trailingText {
                    Text(trailingText)
                        .font(GlancieFont.rounded(9.5, .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.screenSuffix(title).text)
    }
}

/// macOS System Settings style switch toggle with explicit blue accent on state
public struct MacSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            Button {
                configuration.isOn.toggle()
            } label: {
                Capsule()
                    .fill(configuration.isOn ? Color(hex: 0x007AFF) : Color.primary.opacity(0.16))
                    .frame(width: 28, height: 16)
                    .overlay(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 0.8)
                            .padding(2),
                        alignment: configuration.isOn ? .trailing : .leading
                    )
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isOn)
            .opacity(isEnabled ? 1.0 : 0.45)
        }
    }
}

public extension ToggleStyle where Self == MacSwitchToggleStyle {
    static var macSwitch: MacSwitchToggleStyle { MacSwitchToggleStyle() }
}

/// Settings toggle row with a coloured icon tile, matching System Settings density.
public struct MenuToggleRow: View {
    public let symbol: String
    public let colors: [Color]
    public let title: String
    public var subtitle: String?
    @Binding public var isOn: Bool

    public init(
        symbol: String,
        colors: [Color],
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) {
        self.symbol = symbol
        self.colors = colors
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        HStack(spacing: 9) {
            IconTile(symbol: symbol, colors: colors, size: 19)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(GlancieFont.rounded(11.5, .medium))
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(GlancieFont.rounded(9.5, .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.macSwitch)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? L10n.on.text : L10n.off.text)
    }
}

/// Coat swatches for picking a cat breed.
///
/// A dropdown would hide the one attribute that actually distinguishes the
/// options, so the colours are the control: each breed shows its own coat.
public struct CatBreedSwatchPicker: View {
    @Binding public var selection: PixelCatBreed

    @State private var hovered: PixelCatBreed?

    public init(selection: Binding<PixelCatBreed>) {
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(PixelCatBreed.allCases) { breed in
                swatch(breed)
            }
            Spacer(minLength: 0)
        }
    }

    private func swatch(_ breed: PixelCatBreed) -> some View {
        let palette = breed.palette
        let isSelected = selection == breed
        let isHovered = hovered == breed

        return Button {
            SoundEffectsEngine.shared.playSelectionFeedback()
            withAnimation(JellySprings.hover) { selection = breed }
        } label: {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [palette.body, palette.dark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .bottom) {
                    // The palette's third colour is the chest patch — a tuxedo's bib,
                    // a calico's dark patch. Without it, tuxedo and black read alike.
                    Circle()
                        .fill(palette.white)
                        .frame(width: 12, height: 12)
                        .offset(y: 3.5)
                }
                .overlay(alignment: .topTrailing) {
                    // Eye colour as a last sliver of identity
                    Circle()
                        .fill(palette.eye)
                        .frame(width: 4.5, height: 4.5)
                        .offset(x: -2.5, y: 3)
                }
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(Surface.shellRim, lineWidth: 0.5)
                }
                .frame(width: 21, height: 21)
                .padding(2.5)
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.clear,
                            lineWidth: 1.8
                        )
                }
                .scaleEffect(isHovered && !isSelected ? 1.10 : 1.0)
                .shadow(
                    color: isSelected ? Color.accentColor.opacity(0.35) : .black.opacity(0.18),
                    radius: isSelected ? 4 : 1.5,
                    y: 1
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(JellySprings.hover) { hovered = hovering ? breed : nil }
        }
        .accessibilityLabel(breed.rawValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Relative "as of" wording for a reading that is no longer current.
///
/// Distinct from `relativeUpdateText`, which says when a *sync* happened. This
/// says how old the *numbers* are, which is the honest framing for an account
/// that is not signed in any more.
public func accountReadingAgeText(_ date: Date) -> String {
    let elapsed = Int(Date().timeIntervalSince(date))
    if elapsed < 60 { return L10n.syncedJustNow.text }
    if elapsed < 3600 { return L10n.syncedMinutesAgo(elapsed / 60).text }
    if elapsed < 86400 { return L10n.syncedHoursAgo(elapsed / 3600).text }
    return L10n.syncedDaysAgo(elapsed / 86400).text
}

/// One provider login.
///
/// Two independent facts share the row, and the layout keeps them apart: the
/// quota on the right belongs to the *account*, while the running badge on the
/// left belongs to the *sources* it is signed into. An account can hold quota it
/// is not currently spending, and an app can be open on an account whose quota
/// this machine cannot read.
public struct AccountRow: View {
    public let label: String
    public var planName: String?
    public var organization: String?
    public let sourceBadge: String
    public let sourceSymbol: String
    /// This account's figures are the ones the bar is showing.
    public let isDisplayed: Bool
    /// Something is working on this account right now.
    public var isRunning: Bool
    /// What is running, e.g. "CLI" or "App".
    public var runningLabel: String?
    /// Whether this machine can read this account's quota at all.
    public var usageReadable: Bool
    public var remainingPercentage: Double?
    /// When those figures were measured. Non-nil only when they are dated.
    public var readingCapturedAt: Date?

    public init(
        label: String,
        planName: String? = nil,
        organization: String? = nil,
        sourceBadge: String,
        sourceSymbol: String,
        isDisplayed: Bool = false,
        isRunning: Bool = false,
        runningLabel: String? = nil,
        usageReadable: Bool = true,
        remainingPercentage: Double? = nil,
        readingCapturedAt: Date? = nil
    ) {
        self.label = label
        self.planName = planName
        self.organization = organization
        self.sourceBadge = sourceBadge
        self.sourceSymbol = sourceSymbol
        self.isDisplayed = isDisplayed
        self.isRunning = isRunning
        self.runningLabel = runningLabel
        self.usageReadable = usageReadable
        self.remainingPercentage = remainingPercentage
        self.readingCapturedAt = readingCapturedAt
    }

    private var tileColors: [Color] {
        if isRunning { return [Color(hex: 0x30D158), Color(hex: 0x18863A)] }
        if isDisplayed { return [Color(hex: 0x0A84FF), Color(hex: 0x0050C7)] }
        return [Color(hex: 0x8E8E93), Color(hex: 0x5A5A60)]
    }

    /// Plan and organisation are the same class of fact, so they share a line
    /// rather than competing for the row's only subtitle slot.
    private var subtitle: String? {
        let parts = [planName, organization].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public var body: some View {
        HStack(spacing: 9) {
            IconTile(symbol: sourceSymbol, colors: tileColors, size: 21)

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 5) {
                    Text(label)
                        .font(GlancieFont.rounded(11.5, .semibold))
                        .foregroundStyle(usageReadable ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(sourceBadge)
                        .font(GlancieFont.rounded(8.5, .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1.5)
                        .background { Capsule().fill(Surface.hoverWash) }

                    if isRunning {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(hex: 0x30D158))
                                .frame(width: 5, height: 5)
                            Text(runningLabel ?? L10n.running.text)
                                .font(GlancieFont.rounded(8.5, .bold))
                        }
                        .foregroundStyle(Color(hex: 0x30D158))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1.5)
                        .background { Capsule().fill(Color(hex: 0x30D158).opacity(0.15)) }
                    }
                }

                if let subtitle {
                    Text(subtitle)
                        .font(GlancieFont.rounded(9.5, .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1.5) {
                if let remainingPercentage {
                    Text("\(Int(remainingPercentage.rounded()))%")
                        .font(GlancieFont.rounded(12, .bold))
                        .monospacedDigit()
                        .foregroundStyle(
                            readingCapturedAt == nil
                                ? UsageColorTheme.primaryColor(for: remainingPercentage)
                                : Color.secondary
                        )
                }

                if let readingCapturedAt {
                    Text(accountReadingAgeText(readingCapturedAt))
                        .font(GlancieFont.rounded(9, .medium))
                        .foregroundStyle(.tertiary)
                } else if !usageReadable {
                    // Saying so beats an empty column: the account is real, the
                    // quota simply is not on this disk.
                    Text(L10n.noUsage.text)
                        .font(GlancieFont.rounded(9, .medium))
                        .foregroundStyle(.tertiary)
                } else if isDisplayed {
                    Text(L10n.onTheBar.text)
                        .font(GlancieFont.rounded(9, .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .opacity(usageReadable || isRunning ? 1.0 : 0.72)
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(label), \(sourceBadge)\(isRunning ? ", \(L10n.running.text)" : "")\(isDisplayed ? ", \(L10n.onTheBar.text)" : "")"
        )
    }
}

/// Segmented picker for the app's language.
///
/// Three options is few enough to lay out flat, which matters more here than
/// elsewhere in Settings: someone opening this screen may be looking at a
/// language they cannot read, and a menu that has to be opened to see its
/// choices would hide the very thing they came for.
public struct LanguageSegmentedPicker: View {
    @Binding public var selection: AppLanguage

    @State private var hovered: AppLanguage?

    public init(selection: Binding<AppLanguage>) {
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(AppLanguage.allCases) { language in
                segment(language)
            }
        }
        .padding(2.5)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Surface.hoverWash)
        }
    }

    private func segment(_ language: AppLanguage) -> some View {
        let isSelected = selection == language
        let isHovered = hovered == language

        return Button {
            SoundEffectsEngine.shared.playSelectionFeedback()
            withAnimation(JellySprings.hover) { selection = language }
        } label: {
            Text(language.displayName)
                .font(GlancieFont.rounded(10.5, isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Surface.plateFill : (isHovered ? Surface.hoverWash : .clear))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(isSelected ? Surface.shellRim : .clear, lineWidth: 0.5)
                        }
                }
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(PressableStyle(pressedScale: 0.97, haptics: false))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { hovered = hovering ? language : nil }
        }
        .accessibilityLabel(language.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
