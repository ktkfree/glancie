import SwiftUI

/// Preferences, laid out the way System Settings groups things: which providers
/// to watch, then how the companion behaves.
public struct MenuBarSettingsScreen: View {
    @ObservedObject private var providerManager = ProviderManager.shared
    @ObservedObject private var preferences = GlanciePreferences.shared
    @ObservedObject private var navigator = MenuBarNavigator.shared
    @ObservedObject private var accountRegistry = AccountRegistry.shared
    @ObservedObject private var localization = Localization.shared

    public init() {}

    private var accent: [Color] { [Color(hex: 0x0A84FF), Color(hex: 0x0050C7)] }
    private var amber: [Color] { [Color(hex: 0xFF9F0A), Color(hex: 0xC25B00)] }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MenuScreenHeader(title: L10n.settings.text) {
                navigator.popToRoot()
            }

            providerSection
            accountSection
            experienceSection
            languageSection
        }
    }

    // MARK: - Accounts

    private var green: [Color] { [Color(hex: 0x30D158), Color(hex: 0x18863A)] }

    private var accountSection: some View {
        InsetSection(
            L10n.accounts.text,
            footnote: L10n.accountsFootnote.text
        ) {
            MenuToggleRow(
                symbol: "person.crop.circle",
                colors: green,
                title: L10n.accountDetection.text,
                subtitle: L10n.accountDetectionSubtitle.text,
                isOn: Binding(
                    get: { preferences.accountScanEnabled },
                    set: { newValue in
                        preferences.accountScanEnabled = newValue
                        SoundEffectsEngine.shared.playSelectionFeedback()
                        Task { await providerManager.rescanAccounts() }
                    }
                )
            )

            if preferences.accountScanEnabled {
                RowSeparator(inset: 28)

                MenuToggleRow(
                    symbol: "eye.slash",
                    colors: accent,
                    title: L10n.maskEmail.text,
                    subtitle: L10n.maskEmailSubtitle.text,
                    isOn: $preferences.maskAccountEmails
                )

                RowSeparator(inset: 28)

                ForEach(accountRegistry.allSources) { source in
                    sourceRow(source)
                }

                if accountRegistry.allSources.isEmpty {
                    Text(L10n.noAccountsDetected.text)
                        .font(GlancieFont.rounded(10.5, .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                        .padding(.vertical, 3)
                }

                MenuCommandRow(
                    title: L10n.scanAgain.text,
                    symbol: "arrow.clockwise",
                    isBusy: accountRegistry.isScanning
                ) {
                    SoundEffectsEngine.shared.playImpactFeedback()
                    Task { await providerManager.rescanAccounts() }
                }
            }
        }
    }

    /// Naming the path makes a machine that reports nothing diagnosable without
    /// a debugger — the usual cause is simply that the app was never installed.
    private func sourceRow(_ source: AccountSource) -> some View {
        HStack(spacing: 9) {
            IconTile(symbol: source.kind.symbol, colors: green, size: 19)

            VStack(alignment: .leading, spacing: 1) {
                Text(source.displayName)
                    .font(GlancieFont.rounded(11.5, .medium))
                    .foregroundStyle(.primary)

                if let rootPath = source.rootPath {
                    Text(abbreviate(rootPath))
                        .font(GlancieFont.rounded(9, .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer(minLength: 6)

            Text(source.kind.badgeText)
                .font(GlancieFont.rounded(8.5, .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1.5)
                .background { Capsule().fill(Surface.hoverWash) }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.displayName), \(source.kind.badgeText)")
    }

    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: - Providers

    private var providerSection: some View {
        InsetSection(
            L10n.providersOnBar.text,
            footnote: L10n.providersOnBarFootnote.text
        ) {
            ForEach(Array(AIProviderType.allCases.enumerated()), id: \.element) { index, provider in
                if index > 0 { RowSeparator(inset: 28) }
                providerToggleRow(provider)
            }
        }
    }

    private func providerToggleRow(_ provider: AIProviderType) -> some View {
        let isOn = providerManager.activeProviders.contains(provider)
        let isDetected = providerManager.isProviderDetected(provider)
        // The last enabled provider cannot be turned off, or the bar has nothing to show.
        let isLocked = isOn && providerManager.activeProviders.count <= 1

        return HStack(spacing: 9) {
            IconTile(
                symbol: provider.sfSymbol,
                colors: isOn ? accent : [Color(hex: 0x8E8E93), Color(hex: 0x5A5A60)],
                size: 19
            )

            Text(provider.displayName)
                .font(GlancieFont.rounded(11.5, .medium))
                .foregroundStyle(isOn ? .primary : .secondary)
                .lineLimit(1)

            if isDetected {
                Text(L10n.detected.text)
                    .font(GlancieFont.rounded(8.5, .bold))
                    .foregroundStyle(Color(hex: 0x30D158))
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 1.5)
                    .background {
                        Capsule().fill(Color(hex: 0x30D158).opacity(0.15))
                    }
            }

            Spacer(minLength: 6)

            Toggle("", isOn: Binding(
                get: { isOn },
                set: { _ in
                    SoundEffectsEngine.shared.playSelectionFeedback()
                    providerManager.toggleProvider(provider)
                }
            ))
            .labelsHidden()
            .toggleStyle(.macSwitch)
            .disabled(isLocked)
            .help(isLocked ? L10n.atLeastOneProvider.text : "")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(provider.displayName)
        .accessibilityValue(isOn ? L10n.shown.text : L10n.hidden.text)
    }

    // MARK: - Experience

    private var experienceSection: some View {
        InsetSection(L10n.experienceSection.text) {
            MenuToggleRow(
                symbol: "hand.tap.fill",
                colors: amber,
                title: L10n.hapticsAndSound.text,
                subtitle: L10n.hapticsAndSoundSubtitle.text,
                isOn: $preferences.soundEnabled
            )

            RowSeparator(inset: 28)

            MenuToggleRow(
                symbol: "eyes",
                colors: [Color(hex: 0xBF5AF2), Color(hex: 0x7A2CB0)],
                title: L10n.eyeTracking.text,
                subtitle: L10n.eyeTrackingSubtitle.text,
                isOn: $preferences.eyeTrackingEnabled
            )

            RowSeparator(inset: 28)

            MenuToggleRow(
                symbol: "cat.fill",
                colors: amber,
                title: L10n.pixelCat.text,
                subtitle: L10n.pixelCatSubtitle.text,
                isOn: $preferences.pixelCatEnabled
            )

            if preferences.pixelCatEnabled {
                RowSeparator(inset: 28)
                breedPicker
            }
        }
    }

    private var breedPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                IconTile(symbol: "pawprint.fill", colors: amber, size: 19)

                Text(L10n.coatColor.text)
                    .font(GlancieFont.rounded(11.5, .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 6)

                Text(preferences.pixelCatBreed.displayName)
                    .font(GlancieFont.rounded(10.5, .semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }

            CatBreedSwatchPicker(
                selection: Binding(
                    get: { preferences.pixelCatBreed },
                    set: { preferences.pixelCatBreed = $0 }
                )
            )
            .padding(.leading, 28)
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        InsetSection(L10n.language.text, footnote: L10n.languageFootnote.text) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    IconTile(symbol: "globe", colors: accent, size: 19)

                    Text(L10n.language.text)
                        .font(GlancieFont.rounded(11.5, .medium))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 6)
                }

                LanguageSegmentedPicker(
                    selection: Binding(
                        get: { localization.preference },
                        set: { AppLanguageController.apply($0) }
                    )
                )
                .padding(.leading, 28)
            }
        }
    }
}
