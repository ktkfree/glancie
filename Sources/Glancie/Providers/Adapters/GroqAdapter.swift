import Foundation

/// Groq Adapter parsing the `x-ratelimit-*` response headers Groq returns.
///
/// The request budget is daily (RPD) and the token budget is per minute (TPM);
/// they were previously both labelled "Per Minute" with a flat 60-second reset.
public final class GroqAdapter: AIProviderAdapter {
    public let type: AIProviderType = .groq
    
    private let modelsEndpoint = "https://api.groq.com/openai/v1/models"
    private let homeDirectory: String
    private let transport: UsageTransport
    
    public init(homeDirectory: String = NSHomeDirectory(), transport: UsageTransport = URLSession.shared) {
        self.homeDirectory = homeDirectory
        self.transport = transport
    }
    
    public var isDetected: Bool {
        if let key = ProcessInfo.processInfo.environment["GROQ_API_KEY"], !key.isEmpty {
            return true
        }
        let path = homeDirectory + "/.config/groq/api_key"
        return FileManager.default.fileExists(atPath: path)
    }
    
    public func checkAvailability() async -> Bool {
        return isDetected
    }
    
    /// Reads the rate-limit headers, or reports why it could not.
    ///
    /// Two failures used to land on a number here. A 429 — the one status that
    /// literally means "you are out of budget" — returned the 99%/100%
    /// fallback, and a 200 carrying no rate-limit headers at all defaulted both
    /// percentages to 100%.
    ///
    /// The headers describe the budget for *this* endpoint and this key. Groq
    /// meters chat completions per model, so what a `/models` call reports is
    /// the account's budget for `/models`, not for any particular model's
    /// inference — which is why the rows say what window they cover rather than
    /// implying a per-model quota.
    public func fetchUsage(forceSync: Bool) async throws -> UsageSnapshot {
        guard let apiKey = resolveAPIKey() else {
            return .unavailable(for: .groq, reason: .notConfigured)
        }
        guard let url = URL(string: modelsEndpoint) else {
            return .unavailable(for: .groq, reason: .providerError)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 6.0

        let response: HTTPURLResponse
        do {
            let (_, raw) = try await transport.data(for: request)
            guard let http = raw as? HTTPURLResponse else {
                return .unavailable(for: .groq, reason: .malformedResponse)
            }
            guard http.statusCode == 200 else {
                return .unavailable(for: .groq, reason: UsageUnavailableReason(httpStatus: http.statusCode))
            }
            response = http
        } catch {
            return .unavailable(for: .groq, reason: UsageUnavailableReason(transportError: error))
        }

        func value(_ name: String) -> String? {
            response.value(forHTTPHeaderField: name)
        }
        func number(_ name: String) -> Double? {
            value(name).flatMap(Double.init)
        }

        let tokens = Self.window(
            remaining: number("x-ratelimit-remaining-tokens"),
            limit: number("x-ratelimit-limit-tokens"),
            reset: Self.duration(value("x-ratelimit-reset-tokens"))
        )
        let requests = Self.window(
            remaining: number("x-ratelimit-remaining-requests"),
            limit: number("x-ratelimit-limit-requests"),
            reset: Self.duration(value("x-ratelimit-reset-requests"))
        )

        // No headers, no reading. A 200 from `/models` proves the key works; it
        // does not report a budget, and defaulting to 100% said it did.
        guard tokens != nil || requests != nil else {
            return .unavailable(for: .groq, reason: .malformedResponse)
        }

        var modelQuotas: [ModelQuotaItem] = []
        if let tokens {
            modelQuotas.append(
                ModelQuotaItem(
                    name: L10n.groqTokenLimit.text,
                    remainingPercentage: tokens.percentage,
                    quotaType: L10n.groqTokensPerMinute(Int(tokens.limit)).text,
                    resetCountdown: tokens.reset
                )
            )
        }
        if let requests {
            modelQuotas.append(
                ModelQuotaItem(
                    name: L10n.groqRequestLimit.text,
                    remainingPercentage: requests.percentage,
                    quotaType: L10n.groqRequestsPerDay(Int(requests.limit)).text,
                    resetCountdown: requests.reset
                )
            )
        }

        // The token budget refills every minute and the request budget every
        // day, so they are two windows rather than one figure and its weekly
        // shadow. The bar leads with the minute budget — that is what actually
        // stops a request in flight — and the daily one takes the longer slot.
        let headline = tokens ?? requests!
        return UsageSnapshot(
            provider: .groq,
            hourlyRemainingPercentage: headline.percentage,
            hourlyResetCountdown: headline.reset,
            weeklyRemainingPercentage: tokens == nil ? nil : requests?.percentage,
            weeklyResetCountdown: tokens == nil ? nil : requests?.reset,
            modelQuotas: modelQuotas,
            strategyUsed: .oauthKeychain,
            hourlyQuotaName: tokens == nil ? L10n.groqRequestLimit.text : L10n.groqTokenLimit.text
        )
    }

    /// One `x-ratelimit-*` triple, once it describes an actual budget.
    struct RateWindow: Equatable {
        var percentage: Double
        var limit: Double
        var reset: TimeInterval?
    }

    static func window(remaining: Double?, limit: Double?, reset: TimeInterval?) -> RateWindow? {
        guard let remaining, let limit, limit > 0 else { return nil }
        return RateWindow(
            percentage: max(0.0, min(100.0, (remaining / limit) * 100.0)),
            limit: limit,
            reset: reset
        )
    }

    /// Groq reports resets as Go durations: `2m59.56s`, `7.66s`, `1h30m`, `840ms`.
    ///
    /// This used to be ignored entirely and replaced with a flat 60 seconds for
    /// both windows, which is not even the right order of magnitude for the
    /// daily request budget.
    static func duration(_ raw: String?) -> TimeInterval? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return nil }

        // A bare number is already seconds.
        if let seconds = Double(text) { return seconds }

        let units: [(suffix: String, seconds: Double)] = [
            ("ms", 0.001), ("h", 3600), ("m", 60), ("s", 1)
        ]

        var total: TimeInterval = 0
        var number = ""
        var index = text.startIndex
        var matchedAnything = false

        while index < text.endIndex {
            let character = text[index]
            if character.isNumber || character == "." {
                number.append(character)
                index = text.index(after: index)
                continue
            }

            guard let unit = units.first(where: { text[index...].hasPrefix($0.suffix) }),
                  let magnitude = Double(number) else { return nil }
            total += magnitude * unit.seconds
            matchedAnything = true
            number = ""
            index = text.index(index, offsetBy: unit.suffix.count)
        }

        // A trailing number with no unit means the string was not a duration.
        guard matchedAnything, number.isEmpty else { return nil }
        return total
    }

    public var credentialFingerprint: String? {
        resolveAPIKey().map(UsageSnapshot.fingerprint)
    }

    private func resolveAPIKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["GROQ_API_KEY"], !key.isEmpty {
            return key
        }
        let path = homeDirectory + "/.config/groq/api_key"
        if let key = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        return nil
    }
}
