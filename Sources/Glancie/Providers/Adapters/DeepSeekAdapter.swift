import Foundation

/// DeepSeek Adapter querying DeepSeek Balance API
public final class DeepSeekAdapter: AIProviderAdapter {
    public let type: AIProviderType = .deepseek
    
    private let balanceEndpoint = "https://api.deepseek.com/user/balance"
    private let homeDirectory: String
    private let transport: UsageTransport
    
    public init(homeDirectory: String = NSHomeDirectory(), transport: UsageTransport = URLSession.shared) {
        self.homeDirectory = homeDirectory
        self.transport = transport
    }
    
    public var isDetected: Bool {
        if let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !key.isEmpty {
            return true
        }
        let configPath = homeDirectory + "/.config/deepseek/api_key"
        return FileManager.default.fileExists(atPath: configPath)
    }
    
    public func checkAvailability() async -> Bool {
        return isDetected
    }
    
    /// Reads the account balance, or reports why it could not.
    ///
    /// Detection used to be enough to produce a figure: an empty
    /// `~/.config/deepseek/api_key` made `isDetected` true, no request was ever
    /// sent, and the adapter returned 100% under `.oauthKeychain` with the
    /// current timestamp. A rejected key and a timeout took the same branch, so
    /// every failure mode read as a full, freshly measured account.
    public func fetchUsage(forceSync: Bool) async throws -> UsageSnapshot {
        guard let apiKey = resolveAPIKey() else {
            return .unavailable(for: .deepseek, reason: .notConfigured)
        }
        guard let url = URL(string: balanceEndpoint) else {
            return .unavailable(for: .deepseek, reason: .providerError)
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8.0
        
        let data: Data
        switch await transport.usageData(for: request) {
        case .success(let payload): data = payload
        case .failure(let reason): return .unavailable(for: .deepseek, reason: reason)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let balanceInfos = json["balance_infos"] as? [[String: Any]],
              let first = balanceInfos.first,
              let totalStr = first["total_balance"] as? String,
              let total = Double(totalStr) else {
            return .unavailable(for: .deepseek, reason: .malformedResponse)
        }
        
        let currency = first["currency"] as? String ?? "USD"
        let grantedStr = first["granted_balance"] as? String ?? "0.00"
        let toppedUpStr = first["topped_up_balance"] as? String ?? "0.00"
        // `is_available` false means the account cannot spend — a real state,
        // and one worth showing as an exhausted balance rather than as no data.
        let isAvailable = json["is_available"] as? Bool ?? true
        
        // DeepSeek publishes no quota ceiling, so there is no denominator to
        // divide by. The arbitrary $20 scale this used to apply is tracked
        // separately in #13; what matters here is that a failed read can no
        // longer arrive at the same place a successful one does.
        let pct = isAvailable ? min(100.0, max(0.0, (total / 20.0) * 100.0)) : 0.0
        
        return UsageSnapshot(
            provider: .deepseek,
            hourlyRemainingPercentage: pct,
            hourlyResetCountdown: nil,
            weeklyRemainingPercentage: pct,
            weeklyResetCountdown: nil,
            modelQuotas: [
                ModelQuotaItem(name: "Total Balance (\(currency) \(totalStr))", remainingPercentage: pct, quotaType: "Account Balance"),
                ModelQuotaItem(name: "Granted Balance (\(currency) \(grantedStr))", remainingPercentage: pct, quotaType: "Credits"),
                ModelQuotaItem(name: "Topped Up (\(currency) \(toppedUpStr))", remainingPercentage: pct, quotaType: "Credits")
            ],
            strategyUsed: .oauthKeychain
        )
    }
    
    public var credentialFingerprint: String? {
        resolveAPIKey().map(UsageSnapshot.fingerprint)
    }

    private func resolveAPIKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !key.isEmpty {
            return key
        }
        let configPath = homeDirectory + "/.config/deepseek/api_key"
        if let key = try? String(contentsOfFile: configPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        return nil
    }
}
