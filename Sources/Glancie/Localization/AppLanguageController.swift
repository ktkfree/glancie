import Foundation

/// Applies a language change everywhere it has to land.
///
/// Switching the language is not purely a rendering concern. Quota names —
/// "세션 (5시간)", "Token limit (TPM)" — are formatted by the adapters at the
/// moment a reading is taken and stored as plain strings inside the snapshot, so
/// the rows already on screen keep whatever language they were built in until
/// something re-reads them. Setting the preference alone would leave the bar
/// half-translated for up to a refresh cycle, which reads as a bug.
///
/// So the change is two steps that belong together, and this is the one place
/// that knows they do.
@MainActor
public enum AppLanguageController {
    public static func apply(_ language: AppLanguage) {
        guard language != Localization.shared.preference else { return }
        Localization.shared.setPreference(language)

        // Re-read from each provider's cache rather than forcing a sync: the
        // figures are still correct, it is only their labels that are stale, and
        // a language switch is no reason to spend a CLI probe or an API call.
        Task { await ProviderManager.shared.refreshAll() }
    }
}
