import Foundation
import SwiftUI

/// Which language the user asked for.
///
/// `system` is the default and means "decide from macOS", which is what a user
/// who never opens Settings expects. The other two are a deliberate override:
/// someone running an English system who wants Korean text, or a Korean system
/// who wants the English wording because that is what the provider docs use.
public enum AppLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case korean
    case english

    public var id: String { rawValue }
}

/// The language actually being rendered, after `system` has been resolved.
///
/// Separate from `AppLanguage` on purpose: every call site that formats a string
/// wants a definite answer, and none of them should have to re-run the system
/// lookup to get one.
public enum ResolvedLanguage: String, Sendable {
    case korean
    case english
}

/// Holds the current language and tells SwiftUI when it changes.
///
/// The resolved value lives in a `Locked` rather than behind the `@Published`
/// property because adapters read it from the cooperative pool while formatting
/// quota names — `L10n.text` must be answerable from any thread, and reading an
/// `ObservableObject` off the main actor is not that.
public final class Localization: ObservableObject {
    public static let shared = Localization()

    static let storageKey = "appLanguage"

    private static let resolvedLanguage = Locked<ResolvedLanguage>(.english)

    /// The language every string formats itself in. Safe to read from any thread.
    public static var current: ResolvedLanguage {
        resolvedLanguage.value
    }

    @Published public private(set) var preference: AppLanguage {
        didSet {
            Self.resolvedLanguage.value = Self.resolve(preference)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.storageKey).flatMap(AppLanguage.init(rawValue:))
        let preference = stored ?? .system
        self.preference = preference
        Self.resolvedLanguage.value = Self.resolve(preference)
    }

    /// Records the choice and re-renders. It does not rebuild text that was
    /// already fetched — quota names are formatted when a snapshot is made, not
    /// when it is drawn — so callers go through `AppLanguageController`, which
    /// does both.
    public func setPreference(_ newValue: AppLanguage) {
        guard newValue != preference else { return }
        defaults.set(newValue.rawValue, forKey: Self.storageKey)
        preference = newValue
    }

    /// Renders in `language` without touching the stored preference.
    ///
    /// For tests and previews. Assertions about wording have to name the
    /// language they were written against, and they must not read — let alone
    /// write — the preference of whoever is running them.
    static func renderLanguage(_ language: ResolvedLanguage) {
        resolvedLanguage.value = language
    }

    /// What `system` means on this Mac.
    ///
    /// `Locale.preferredLanguages` is the list the user dragged into order in
    /// System Settings, most-wanted first, as IETF tags (`ko-KR`, `en-US`). Only
    /// the first entry is consulted: a Korean user with English second still
    /// wants Korean, and matching further down the list would flip the app to
    /// Korean for an English user who merely lists it as a fallback.
    static func resolve(
        _ preference: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> ResolvedLanguage {
        switch preference {
        case .korean:
            return .korean
        case .english:
            return .english
        case .system:
            guard let first = preferredLanguages.first else { return .english }
            // `ko`, `ko-KR`, `ko-Kore-KR` — the language subtag is what decides,
            // and it is everything before the first separator.
            let languageCode = first.split(whereSeparator: { $0 == "-" || $0 == "_" }).first
            return languageCode?.lowercased() == "ko" ? .korean : .english
        }
    }
}

extension AppLanguage {
    /// Shown in Settings. Each option is written in the language it selects, so
    /// it stays readable to someone who has the app in a language they cannot
    /// read and is looking for the way out.
    public var displayName: String {
        switch self {
        case .system: return L10n.languageSystem.text
        case .korean: return "한국어"
        case .english: return "English"
        }
    }
}
