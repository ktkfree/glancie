import Foundation

/// ElevenLabs Adapter querying subscription and character usage
public final class ElevenLabsAdapter: AIProviderAdapter {
    public let type: AIProviderType = .elevenlabs
    
    private let subscriptionEndpoint = "https://api.elevenlabs.io/v1/user/subscription"
    private let homeDirectory: String
    private let transport: UsageTransport
    
    public init(homeDirectory: String = NSHomeDirectory(), transport: UsageTransport = URLSession.shared) {
        self.homeDirectory = homeDirectory
        self.transport = transport
    }
    
    public var isDetected: Bool {
        if let key = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"] ?? ProcessInfo.processInfo.environment["XI_API_KEY"], !key.isEmpty {
            return true
        }
        let path = homeDirectory + "/.config/elevenlabs/api_key"
        return FileManager.default.fileExists(atPath: path)
    }
    
    public func checkAvailability() async -> Bool {
        return isDetected
    }
    
    /// Reads character usage, or reports why it could not.
    ///
    /// The old failure path returned 78% and "22,000 / 100,000 chars" for the
    /// Creator tier — a whole plausible subscription, invented. The reset field
    /// this still reads from the wrong place is #11.
    public func fetchUsage(forceSync: Bool) async throws -> UsageSnapshot {
        guard let apiKey = resolveAPIKey() else {
            return .unavailable(for: .elevenlabs, reason: .notConfigured)
        }
        guard let url = URL(string: subscriptionEndpoint) else {
            return .unavailable(for: .elevenlabs, reason: .providerError)
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 6.0

        let data: Data
        switch await transport.usageData(for: request) {
        case .success(let payload): data = payload
        case .failure(let reason): return .unavailable(for: .elevenlabs, reason: reason)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let used = Self.numeric(json["character_count"]),
              let limit = Self.numeric(json["character_limit"]), limit > 0 else {
            return .unavailable(for: .elevenlabs, reason: .malformedResponse)
        }

        let tier = json["tier"] as? String ?? "Free"

        let pct = max(0.0, min(100.0, 100.0 - (used / limit * 100.0)))
        let usedInt = Int(used)
        let limitInt = Int(limit)
        let reset = Self.characterResetCountdown(json, now: Date())

        return UsageSnapshot(
            provider: .elevenlabs,
            hourlyRemainingPercentage: pct,
            hourlyResetCountdown: reset,
            weeklyRemainingPercentage: pct,
            weeklyResetCountdown: reset,
            modelQuotas: [
                ModelQuotaItem(name: "Tier: \(tier.capitalized)", remainingPercentage: pct, quotaType: "Characters: \(usedInt)/\(limitInt)", resetCountdown: reset),
                ModelQuotaItem(name: "Remaining Characters", remainingPercentage: pct, quotaType: "\(limitInt - usedInt) Left", resetCountdown: reset)
            ],
            strategyUsed: .oauthKeychain,
            hourlyQuotaName: L10n.elevenLabsCharacterUsage.text
        )
    }

    /// When the character allowance refills, from the field that says so.
    ///
    /// This used to read `next_invoice.next_payment_timestamp` — a key the
    /// documented response does not even carry (it is `next_payment_attempt_unix`)
    /// — and fall back to a flat fifteen days when it came back nil, which it
    /// always did. So every subscription showed the same invented countdown.
    ///
    /// The billing date would be the wrong answer even spelled correctly: an
    /// invoice is when the account is charged, and the character counter resets
    /// on its own schedule. `next_character_count_reset_unix` is the field that
    /// describes the quota, and when it is absent there is no countdown to show.
    static func characterResetCountdown(_ json: [String: Any], now: Date) -> TimeInterval? {
        guard let epoch = numeric(json["next_character_count_reset_unix"]) else { return nil }
        let remaining = Date(timeIntervalSince1970: epoch).timeIntervalSince(now)
        // A reset already in the past says the counters we just read are about
        // to roll over, not that they reset this instant.
        return remaining > 0 ? remaining : nil
    }

    private static func numeric(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        return nil
    }

    public var credentialFingerprint: String? {
        resolveAPIKey().map(UsageSnapshot.fingerprint)
    }

    private func resolveAPIKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"] ?? ProcessInfo.processInfo.environment["XI_API_KEY"], !key.isEmpty {
            return key
        }
        let path = homeDirectory + "/.config/elevenlabs/api_key"
        if let key = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        return nil
    }
}
