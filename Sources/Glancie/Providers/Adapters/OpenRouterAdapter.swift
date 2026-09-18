import Foundation

/// OpenRouter Adapter fetching credit balance and API key usage
public final class OpenRouterAdapter: AIProviderAdapter {
    public let type: AIProviderType = .openrouter
    
    private let creditsEndpoint = "https://openrouter.ai/api/v1/credits"
    private let keyEndpoint = "https://openrouter.ai/api/v1/key"
    private let homeDirectory: String
    private let transport: UsageTransport
    
    public init(homeDirectory: String = NSHomeDirectory(), transport: UsageTransport = URLSession.shared) {
        self.homeDirectory = homeDirectory
        self.transport = transport
    }
    
    public var isDetected: Bool {
        if let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty {
            return true
        }
        let path = homeDirectory + "/.config/openrouter/api_key"
        return FileManager.default.fileExists(atPath: path)
    }
    
    public func checkAvailability() async -> Bool {
        return isDetected
    }
    
    /// Reads the account balance *and* the budget of the key doing the spending.
    ///
    /// `keyEndpoint` was declared and never called, so the reading was the
    /// account's credits alone. Those are different budgets: a key with
    /// `limit: 5` and `limit_remaining: 0` cannot make another request no matter
    /// how much the account has left, and the bar showed 90% because the account
    /// still held 90 credits. A `total_credits` of 0 was treated as "no
    /// denominator, therefore full" and reported 100%, which is the same mistake
    /// in the other direction.
    public func fetchUsage(forceSync: Bool) async throws -> UsageSnapshot {
        guard let apiKey = resolveAPIKey() else {
            return .unavailable(for: .openrouter, reason: .notConfigured)
        }
        guard let creditsURL = URL(string: creditsEndpoint), let keyURL = URL(string: keyEndpoint) else {
            return .unavailable(for: .openrouter, reason: .providerError)
        }

        async let creditsResult = transport.usageData(for: request(apiKey, url: creditsURL))
        async let keyResult = transport.usageData(for: request(apiKey, url: keyURL))

        let credits: Credits?
        switch await creditsResult {
        case .success(let data): credits = Credits(json: Self.payload(data))
        case .failure(let reason):
            // The account balance is the only endpoint that must answer: without
            // it there is nothing to fall back on but the key's own budget, and
            // a failure there is a failure to read.
            return .unavailable(for: .openrouter, reason: reason)
        }

        // A key budget that could not be read is absent, not unlimited. The
        // account balance is still a real reading and is shown on its own.
        var keyBudget: KeyBudget?
        if case .success(let data) = await keyResult {
            keyBudget = KeyBudget(json: Self.payload(data))
        }

        guard let credits else {
            return .unavailable(for: .openrouter, reason: .malformedResponse)
        }

        var quotas: [ModelQuotaItem] = []
        if let keyBudget {
            quotas.append(keyBudget.quotaItem)
        }
        if let accountShare = credits.share {
            quotas.append(
                ModelQuotaItem(
                    name: L10n.openRouterAccountBalanceWith(Self.dollars(credits.balance)).text,
                    remainingPercentage: accountShare,
                    quotaType: "Prepaid Balance"
                )
            )
        }

        // The key's budget leads when it has one, because that is the limit a
        // request actually hits first.
        let headline: (percentage: Double, name: String)?
        if let limited = keyBudget?.limitedShare {
            headline = (limited, L10n.openRouterKeyBudget.text)
        } else if let accountShare = credits.share {
            headline = (accountShare, L10n.openRouterAccountBalance.text)
        } else if keyBudget?.isUnlimited == true {
            headline = (100, L10n.openRouterKeyUnlimited.text)
        } else {
            headline = nil
        }

        // No key ceiling, no credits ever bought, nothing spent: there is no
        // proportion to report, and 100% was never one.
        guard let headline else {
            return .unavailable(for: .openrouter, reason: .notMeasured)
        }

        return UsageSnapshot(
            provider: .openrouter,
            hourlyRemainingPercentage: headline.percentage,
            hourlyResetCountdown: nil,
            weeklyRemainingPercentage: credits.share,
            weeklyResetCountdown: nil,
            modelQuotas: quotas,
            strategyUsed: .oauthKeychain,
            hourlyQuotaName: headline.name
        )
    }

    private func request(_ apiKey: String, url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("Glancie", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 8.0
        return request
    }

    private static func payload(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [String: Any]
    }

    private static func dollars(_ amount: Double) -> String {
        String(format: "$%.2f", amount)
    }

    /// `/api/v1/credits`: what the account has bought and spent in total.
    struct Credits {
        var totalCredits: Double
        var totalUsage: Double

        init?(json: [String: Any]?) {
            guard let json,
                  let total = OpenRouterAdapter.numeric(json["total_credits"]),
                  let usage = OpenRouterAdapter.numeric(json["total_usage"]) else { return nil }
            totalCredits = total
            totalUsage = usage
        }

        var balance: Double { max(0.0, totalCredits - totalUsage) }

        /// The share of purchased credits still unspent, or nil when nothing was
        /// ever purchased — in which case there is no denominator, and saying
        /// "100%" invents one.
        var share: Double? {
            guard totalCredits > 0 else { return nil }
            return max(0.0, min(100.0, (balance / totalCredits) * 100.0))
        }
    }

    /// `/api/v1/key`: the budget of the key making the requests.
    struct KeyBudget {
        var limit: Double?
        var limitRemaining: Double?
        var usage: Double
        var isFreeTier: Bool

        init?(json: [String: Any]?) {
            guard let json else { return nil }
            // `limit: null` is OpenRouter's way of saying the key is uncapped —
            // a fact about the key, not a missing field.
            limit = OpenRouterAdapter.numeric(json["limit"])
            limitRemaining = OpenRouterAdapter.numeric(json["limit_remaining"])
            usage = OpenRouterAdapter.numeric(json["usage"]) ?? 0
            isFreeTier = (json["is_free_tier"] as? Bool) ?? false
        }

        var isUnlimited: Bool { limit == nil }

        /// The share of this key's own ceiling still available.
        var limitedShare: Double? {
            guard let limit, limit > 0, let limitRemaining else { return nil }
            return max(0.0, min(100.0, (limitRemaining / limit) * 100.0))
        }

        var quotaItem: ModelQuotaItem {
            if let share = limitedShare, let limit, let remaining = limitRemaining {
                return ModelQuotaItem(
                    name: L10n.openRouterKeyBudgetWith(OpenRouterAdapter.dollars(remaining), OpenRouterAdapter.dollars(limit)).text,
                    remainingPercentage: share,
                    quotaType: isFreeTier ? "Free Tier Key" : "Key Limit"
                )
            }
            return ModelQuotaItem(
                name: L10n.openRouterKeyUsed(OpenRouterAdapter.dollars(usage)).text,
                remainingPercentage: 100,
                quotaType: isFreeTier ? "Free Tier Key" : "Key Limit",
                paceText: L10n.unlimited.text
            )
        }
    }

    static func numeric(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        return nil
    }

    public var credentialFingerprint: String? {
        resolveAPIKey().map(UsageSnapshot.fingerprint)
    }

    private func resolveAPIKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty {
            return key
        }
        let path = homeDirectory + "/.config/openrouter/api_key"
        if let key = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        return nil
    }
}
