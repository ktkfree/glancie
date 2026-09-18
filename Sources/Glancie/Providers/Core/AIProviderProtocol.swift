import SwiftUI
import CryptoKit

/// AI Provider Types supported by Glancie
public enum AIProviderType: String, CaseIterable, Identifiable, Codable {
    case claudeCode = "claude"
    case openAICodex = "codex"
    case antigravity = "agy"
    case cursor = "cursor"
    case copilot = "copilot"
    case deepseek = "deepseek"
    case openrouter = "openrouter"
    case groq = "groq"
    case ollama = "ollama"
    case mistral = "mistral"
    case kimi = "kimi"
    case elevenlabs = "elevenlabs"
    case windsurf = "windsurf"
    case zed = "zed"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .openAICodex: return "Codex"
        case .antigravity: return "Antigravity (AGY)"
        case .cursor: return "Cursor"
        case .copilot: return "GitHub Copilot"
        case .deepseek: return "DeepSeek"
        case .openrouter: return "OpenRouter"
        case .groq: return "Groq"
        case .ollama: return "Ollama"
        case .mistral: return "Mistral AI"
        case .kimi: return "Moonshot Kimi"
        case .elevenlabs: return "ElevenLabs"
        case .windsurf: return "Windsurf"
        case .zed: return "Zed AI"
        }
    }
    
    /// Glyphs chosen to stay legible at 8pt inside the bar's activity ring
    public var sfSymbol: String {
        switch self {
        case .claudeCode: return "sparkle"
        case .openAICodex: return "curlybraces"
        case .antigravity: return "atom"
        case .cursor: return "cursorarrow"
        case .copilot: return "cpu"
        case .deepseek: return "fish"
        case .openrouter: return "point.3.filled.connected.trianglepath.dotted"
        case .groq: return "bolt.fill"
        case .ollama: return "server.rack"
        case .mistral: return "wind"
        case .kimi: return "moon.stars.fill"
        case .elevenlabs: return "waveform"
        case .windsurf: return "water.waves"
        case .zed: return "terminal.fill"
        }
    }

    /// Short label for tight layouts
    public var shortName: String {
        switch self {
        case .claudeCode: return "Claude"
        case .openAICodex: return "Codex"
        case .antigravity: return "Antigravity"
        case .cursor: return "Cursor"
        case .copilot: return "Copilot"
        case .deepseek: return "DeepSeek"
        case .openrouter: return "OpenRouter"
        case .groq: return "Groq"
        case .ollama: return "Ollama"
        case .mistral: return "Mistral"
        case .kimi: return "Kimi"
        case .elevenlabs: return "ElevenLabs"
        case .windsurf: return "Windsurf"
        case .zed: return "Zed"
        }
    }
    /// Web status page URL for this provider
    public var statusPageURL: URL? {
        switch self {
        case .claudeCode: return URL(string: "https://status.anthropic.com")
        case .openAICodex: return URL(string: "https://status.openai.com")
        case .antigravity: return URL(string: "https://status.cloud.google.com")
        case .cursor: return URL(string: "https://status.cursor.com")
        case .copilot: return URL(string: "https://www.githubstatus.com")
        case .deepseek: return URL(string: "https://status.deepseek.com")
        case .openrouter: return URL(string: "https://openrouter.ai/activity")
        case .groq: return URL(string: "https://groq.statuspage.io")
        case .mistral: return URL(string: "https://status.mistral.ai")
        default: return URL(string: "https://google.com")
        }
    }

    /// Account / Dashboard URL
    public var accountDashboardURL: URL? {
        switch self {
        case .claudeCode: return URL(string: "https://claude.ai/settings/billing")
        case .openAICodex: return URL(string: "https://platform.openai.com/usage")
        case .antigravity: return URL(string: "https://aistudio.google.com")
        case .cursor: return URL(string: "https://www.cursor.com/settings")
        case .copilot: return URL(string: "https://github.com/settings/billing")
        case .deepseek: return URL(string: "https://platform.deepseek.com/usage")
        case .openrouter: return URL(string: "https://openrouter.ai/credits")
        case .groq: return URL(string: "https://console.groq.com/usage")
        default: return nil
        }
    }
}

/// Model-specific quota details for popup view
public struct ModelQuotaItem: Identifiable, Equatable, Codable {
    public var id: String { name }
    public var name: String
    public var remainingPercentage: Double
    public var quotaType: String
    public var resetCountdown: TimeInterval?
    /// When this row's window rolls over, where the provider says so. Kept for
    /// the same reason the snapshot keeps its own: once the moment passes the
    /// countdown is nil, and nil cannot tell "already reset" from "never said".
    public var resetAt: Date?
    public var paceText: String?
    public var paceMarkerPercentage: Double?

    /// Whether the window this row was measured in has since ended.
    public func isWindowElapsed(now: Date = Date()) -> Bool {
        guard let resetAt else { return false }
        return resetAt <= now
    }
    
    public var gradientColors: [Color] {
        UsageColorTheme.gradientColors(for: remainingPercentage)
    }
    
    public var themeColor: Color {
        UsageColorTheme.primaryColor(for: remainingPercentage)
    }
    
    public init(
        name: String,
        remainingPercentage: Double,
        quotaType: String = "5-Hour",
        resetCountdown: TimeInterval? = nil,
        resetAt: Date? = nil,
        paceText: String? = nil,
        paceMarkerPercentage: Double? = nil
    ) {
        self.name = name
        self.remainingPercentage = max(0.0, min(100.0, remainingPercentage))
        self.quotaType = quotaType
        self.resetCountdown = resetCountdown
        self.resetAt = resetAt
        self.paceText = paceText
        self.paceMarkerPercentage = paceMarkerPercentage
    }
}

public enum FetchStrategy: String, Codable {
    case oauthKeychain = "OAuth/Keychain"
    case cliStatusProbe = "CLI Probe"
    case localFileCache = "Local Cache/DB"
    case simulated = "Simulated Fallback"
}

/// Why a provider is showing no figures.
///
/// A snapshot without a measurement still has to say *something*, and the one
/// thing it must never say is a number. Carrying the reason instead keeps the
/// distinction the display needs — "nothing is signed in here" and "the key was
/// rejected" are different problems with different fixes — without inviting a
/// plausible-looking percentage to stand in for either.
public enum UsageUnavailableReason: String, Codable, Equatable, Sendable {
    /// Nothing on this machine is signed into the provider.
    case notConfigured
    /// Signed in, but nothing this machine can read reports a real quota.
    /// An installed app and a list of available models are not measurements.
    case notMeasured
    /// The credential was rejected — 401, 403, or an auth-flavoured URLError.
    case authenticationFailed
    /// The provider refused the read because we asked too often (429).
    case rateLimited
    /// The request never completed: offline, DNS, TLS, timeout.
    case networkFailure
    /// An answer arrived, but not one carrying the fields a reading needs.
    case malformedResponse
    /// The provider answered with some other error status.
    case providerError

    /// Short label for the badge, in the UI's language.
    public var displayText: String {
        switch self {
        case .notConfigured: return L10n.notConnected.text
        case .notMeasured: return L10n.usageNotMeasured.text
        case .authenticationFailed: return L10n.authenticationFailed.text
        case .rateLimited: return L10n.rateLimited.text
        case .networkFailure: return L10n.networkError.text
        case .malformedResponse: return L10n.malformedResponse.text
        case .providerError: return L10n.providerError.text
        }
    }

    /// Whether this is a condition that may clear on its own.
    ///
    /// The distinction decides what happens to the reading already on screen. A
    /// rejected key or a dropped connection says nothing new about the quota, so
    /// the last real measurement stays and ages visibly. Being signed out, or
    /// having no measurable quota at all, is a statement about the account
    /// itself — that one has to replace whatever was there.
    public var isTransient: Bool {
        switch self {
        case .notConfigured, .notMeasured:
            return false
        case .authenticationFailed, .rateLimited, .networkFailure, .malformedResponse, .providerError:
            return true
        }
    }

    /// Copy for the detail card, which has room to say what the user can do
    /// about it — or that there is nothing to do.
    public struct Notice: Equatable, Sendable {
        public let header: String
        public let title: String
        public let detail: String
        /// `false` where nothing is broken: the provider simply publishes no
        /// quota, so the notice must not wear an alarm colour or send the user
        /// off to check a login that was never the problem.
        public let isFault: Bool
    }

    public var notice: Notice {
        switch self {
        case .notConfigured:
            return Notice(
                header: L10n.guidanceHeaderConnection.text,
                title: L10n.guidanceTitleNotConfigured.text,
                detail: L10n.guidanceDetailNotConfigured.text,
                isFault: true
            )
        case .notMeasured:
            return Notice(
                header: L10n.guidanceHeaderMeasurement.text,
                title: L10n.guidanceTitleNotMeasured.text,
                detail: L10n.guidanceDetailNotMeasured.text,
                isFault: false
            )
        case .authenticationFailed:
            return Notice(
                header: L10n.guidanceHeaderAuthentication.text,
                title: L10n.guidanceTitleAuthFailed.text,
                detail: L10n.guidanceDetailAuthFailed.text,
                isFault: true
            )
        case .rateLimited:
            return Notice(
                header: L10n.guidanceHeaderRateLimit.text,
                title: L10n.guidanceTitleRateLimited.text,
                detail: L10n.guidanceDetailRateLimited.text,
                isFault: true
            )
        case .networkFailure:
            return Notice(
                header: L10n.guidanceHeaderNetwork.text,
                title: L10n.guidanceTitleNetwork.text,
                detail: L10n.guidanceDetailNetwork.text,
                isFault: true
            )
        case .malformedResponse:
            return Notice(
                header: L10n.guidanceHeaderResponse.text,
                title: L10n.guidanceTitleMalformed.text,
                detail: L10n.guidanceDetailMalformed.text,
                isFault: true
            )
        case .providerError:
            return Notice(
                header: L10n.guidanceHeaderProvider.text,
                title: L10n.guidanceTitleProviderError.text,
                detail: L10n.guidanceDetailProviderError.text,
                isFault: true
            )
        }
    }
}

public enum CharacterState: Equatable {
    case energetic   // 80% ~ 100%
    case focused     // 30% ~ 79%
    case tired       // 10% ~ 29%
    case sleeping    // 0% ~ 9%
    case celebrating // Reset celebration
    
    public static func from(percentage: Double) -> CharacterState {
        switch percentage {
        case 80...: return .energetic
        case 30..<80: return .focused
        case 10..<30: return .tired
        default: return .sleeping
        }
    }
}

/// Rich Quota Snapshot: Hourly (Main Bar), Weekly (Popup), and Per-Model Quotas (Popup)
public struct UsageSnapshot: Equatable, Codable {
    public var provider: AIProviderType
    public var accountEmail: String?
    public var planName: String?

    /// Which account these figures belong to, and where that account was read
    /// from. Set by `ProviderManager` once the adapter has returned, so a
    /// snapshot can never be shown next to a different account's address.
    public var accountID: String?
    public var sourceID: String?
    /// When the underlying numbers were actually measured. Distinct from
    /// `lastUpdated`, which a restored snapshot would otherwise refresh.
    public var capturedAt: Date
    /// A failed refresh preserves the original measurement time and admits that
    /// the displayed figures are last-known, even if they are only seconds old.
    public var fetchError: String? = nil

    // 1. 시간별 쿼터 (바에 표시 - 가장 중요 정보)
    public var hourlyRemainingPercentage: Double
    public var hourlyResetCountdown: TimeInterval?
    /// Which pool the headline percentage was read from, when a provider meters
    /// several and the bar can only show one. `nil` leaves the display's own
    /// wording in place.
    public var hourlyQuotaName: String?
    /// When the headline window rolls over, where the provider says so.
    ///
    /// Kept alongside the countdown because the two stop agreeing at exactly
    /// the moment that matters: once it passes, `hourlyResetCountdown` is nil,
    /// which is indistinguishable from a provider that never published a reset
    /// time at all. This still says the window ended, and when — and a window
    /// that has ended is not one the percentage beside it describes.
    public var hourlyResetAt: Date?
    
    // 2. 주간 쿼터 (팝업뷰에 표시)
    public var weeklyRemainingPercentage: Double?
    public var weeklyResetCountdown: TimeInterval?
    /// When the weekly window rolls over. The hourly window's twin, and needed
    /// for the same reason: a week closing is as silent as five hours closing.
    public var weeklyResetAt: Date?
    
    // 3. Model 별 쿼터 (팝업뷰에 표시)
    public var modelQuotas: [ModelQuotaItem]
    
    public var usedTokens: Int
    public var totalTokens: Int
    public var lastUpdated: Date
    public var strategyUsed: FetchStrategy
    /// Set only when there are no figures to show; `nil` on every measurement.
    public var unavailableReason: UsageUnavailableReason?
    /// Identifies the credential this reading came from, so a reading is never
    /// carried across a key change. `nil` where there is no credential to
    /// fingerprint — which is also what every snapshot stored before this field
    /// existed decodes as.
    public var credentialFingerprint: String?
    
    public init(
        provider: AIProviderType,
        hourlyRemainingPercentage: Double,
        hourlyResetCountdown: TimeInterval? = 7200,
        weeklyRemainingPercentage: Double? = nil,
        weeklyResetCountdown: TimeInterval? = nil,
        modelQuotas: [ModelQuotaItem] = [],
        accountEmail: String? = nil,
        planName: String? = nil,
        usedTokens: Int = 0,
        totalTokens: Int = 100_000,
        lastUpdated: Date = Date(),
        strategyUsed: FetchStrategy = .localFileCache,
        accountID: String? = nil,
        sourceID: String? = nil,
        capturedAt: Date? = nil,
        unavailableReason: UsageUnavailableReason? = nil,
        hourlyQuotaName: String? = nil,
        hourlyResetAt: Date? = nil,
        weeklyResetAt: Date? = nil,
        credentialFingerprint: String? = nil
    ) {
        self.provider = provider
        self.hourlyRemainingPercentage = max(0.0, min(100.0, hourlyRemainingPercentage))
        self.hourlyResetCountdown = hourlyResetCountdown
        self.weeklyRemainingPercentage = weeklyRemainingPercentage != nil ? max(0.0, min(100.0, weeklyRemainingPercentage!)) : nil
        self.weeklyResetCountdown = weeklyResetCountdown
        self.modelQuotas = modelQuotas
        self.accountEmail = accountEmail
        self.planName = planName
        self.usedTokens = usedTokens
        self.totalTokens = totalTokens
        self.lastUpdated = lastUpdated
        self.strategyUsed = strategyUsed
        self.accountID = accountID
        self.sourceID = sourceID
        self.capturedAt = capturedAt ?? lastUpdated
        self.unavailableReason = unavailableReason
        self.hourlyQuotaName = hourlyQuotaName
        self.hourlyResetAt = hourlyResetAt
        self.weeklyResetAt = weeklyResetAt
        self.credentialFingerprint = credentialFingerprint
    }

    public var remainingPercentage: Double {
        hourlyRemainingPercentage
    }

    public var isSimulated: Bool {
        strategyUsed == .simulated
    }

    /// Whether the window the headline percentage was measured in has since
    /// ended.
    ///
    /// A rate limit window rolling over is not the reading going stale — a stale
    /// reading is still the last thing known to be true, while this one is
    /// known to be false. The quota refilled at `hourlyResetAt`; how much of the
    /// new window is already spent is something no file on disk has said yet, so
    /// the figure is withheld rather than carried forward or replaced with the
    /// full 100% that nobody measured.
    public func isHourlyWindowElapsed(now: Date = Date()) -> Bool {
        guard let hourlyResetAt else { return false }
        return hourlyResetAt <= now
    }

    /// The same question for the weekly window, which closes on its own clock:
    /// the five-hour limit rolling over says nothing about the week, and the
    /// week rolling over says nothing about the five hours.
    public func isWeeklyWindowElapsed(now: Date = Date()) -> Bool {
        guard let weeklyResetAt else { return false }
        return weeklyResetAt <= now
    }

    /// What to show where a percentage would otherwise go.
    public var unavailableText: String {
        (unavailableReason ?? .notConfigured).displayText
    }

    /// A stable, non-reversible name for a credential.
    ///
    /// Hashed rather than kept: this travels into the snapshot store on disk,
    /// and an API key does not belong there. Only equality is ever asked of it.
    public static func fingerprint(_ credential: String) -> String {
        SHA256.hash(data: Data(credential.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// A snapshot that reports no usage at all, and says why.
    ///
    /// Every field that could be mistaken for a reading is left empty on
    /// purpose: no percentage, no countdown, no per-model rows. `planName` and
    /// `accountEmail` survive because they describe the account rather than its
    /// quota, and the detail screen still has to name who is signed in.
    public static func unavailable(
        for provider: AIProviderType,
        reason: UsageUnavailableReason,
        accountEmail: String? = nil,
        planName: String? = nil,
        accountID: String? = nil,
        sourceID: String? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            hourlyRemainingPercentage: 0.0,
            hourlyResetCountdown: nil,
            weeklyRemainingPercentage: nil,
            weeklyResetCountdown: nil,
            modelQuotas: [],
            accountEmail: accountEmail,
            planName: planName,
            strategyUsed: .simulated,
            accountID: accountID,
            sourceID: sourceID,
            unavailableReason: reason
        )
    }

    public static func simulatedFallback(for provider: AIProviderType) -> UsageSnapshot {
        .unavailable(for: provider, reason: .notConfigured)
    }

    /// How old a reading may be before it stops describing the present.
    ///
    /// One threshold, because two would contradict each other: an adapter that
    /// considered a cache fresh for longer than this would sit on figures the
    /// display had already labelled stale, and refresh nothing.
    public static let stalenessThreshold: TimeInterval = 15 * 60

    /// Old enough that the figures should be presented as a last-known reading
    /// rather than the current state — which is exactly what a snapshot restored
    /// for an account that is no longer signed in always is.
    public var isStale: Bool {
        fetchError != nil || Date().timeIntervalSince(capturedAt) > Self.stalenessThreshold
    }

    /// Rewinds the countdowns by however long this snapshot sat unused, so a
    /// restored reading never advertises a reset that has already happened.
    /// A window that has since elapsed becomes `nil`: once it rolls over the
    /// old percentages say nothing about the new one.
    public func agedToNow(referenceDate: Date = Date()) -> UsageSnapshot {
        let elapsed = referenceDate.timeIntervalSince(capturedAt)
        guard elapsed > 0 else { return self }

        func remaining(_ countdown: TimeInterval?) -> TimeInterval? {
            guard let countdown else { return nil }
            let left = countdown - elapsed
            return left > 0 ? left : nil
        }

        var aged = self
        aged.hourlyResetCountdown = remaining(hourlyResetCountdown)
        aged.weeklyResetCountdown = remaining(weeklyResetCountdown)
        aged.modelQuotas = modelQuotas.map { item in
            var quota = item
            quota.resetCountdown = remaining(item.resetCountdown)
            return quota
        }
        return aged
    }
    
    public var gradientColors: [Color] {
        UsageColorTheme.gradientColors(for: hourlyRemainingPercentage)
    }
    
    public var themeColor: Color {
        UsageColorTheme.primaryColor(for: hourlyRemainingPercentage)
    }
    
    public var state: CharacterState {
        CharacterState.from(percentage: hourlyRemainingPercentage)
    }
}

public protocol AIProviderAdapter {
    var type: AIProviderType { get }
    var isDetected: Bool { get }
    func checkAvailability() async -> Bool
    func fetchUsage(forceSync: Bool) async throws -> UsageSnapshot

    /// One snapshot per account whose quota this machine can read.
    ///
    /// Quota is a property of the account, not of the CLI or desktop app it was
    /// read through, so an adapter that can see several accounts should report
    /// all of them rather than picking one. Each snapshot must carry its own
    /// `accountID`; `ProviderManager` files them separately.
    func fetchUsagePerAccount(forceSync: Bool) async throws -> [UsageSnapshot]

    /// Names the credential the adapter would read with right now.
    ///
    /// The manager needs this to tell "the same key was refused" from "a
    /// different key is in place now". Only the first may keep the previous
    /// reading on screen; the second describes another account entirely.
    /// `nil` for providers with no credential to name.
    var credentialFingerprint: String? { get }
}

public extension AIProviderAdapter {
    func fetchUsage() async throws -> UsageSnapshot {
        try await fetchUsage(forceSync: false)
    }

    /// CLI and local-file providers read no credential of their own.
    var credentialFingerprint: String? { nil }

    /// Providers that expose one signed-in account at a time report a single
    /// snapshot, which the manager attributes to whichever account that is.
    func fetchUsagePerAccount(forceSync: Bool) async throws -> [UsageSnapshot] {
        [try await fetchUsage(forceSync: forceSync)]
    }
}
