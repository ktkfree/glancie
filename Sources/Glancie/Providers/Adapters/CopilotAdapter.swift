import Foundation

/// GitHub Copilot Adapter using local ~/.config/github-copilot/ tokens and GitHub Copilot User API
public final class CopilotAdapter: AIProviderAdapter {
    public let type: AIProviderType = .copilot
    
    private let homeDirectory: String
    private let transport: UsageTransport
    private let configPath = "/.config/github-copilot/hosts.json"
    private let appsConfigPath = "/.config/github-copilot/apps.json"
    private let usageEndpoint = "https://api.github.com/copilot_internal/user"
    
    public init(homeDirectory: String = NSHomeDirectory(), transport: UsageTransport = URLSession.shared) {
        self.homeDirectory = homeDirectory
        self.transport = transport
    }
    
    public var isDetected: Bool {
        if ProcessInfo.processInfo.environment["GITHUB_TOKEN"] != nil ||
           ProcessInfo.processInfo.environment["COPILOT_TOKEN"] != nil {
            return true
        }
        let path1 = homeDirectory + configPath
        let path2 = homeDirectory + appsConfigPath
        return FileManager.default.fileExists(atPath: path1) || FileManager.default.fileExists(atPath: path2)
    }
    
    public func checkAvailability() async -> Bool {
        return isDetected
    }
    
    /// Reads the Copilot quota snapshots, or reports why it could not.
    ///
    /// The old failure path returned 92%/96% under `.localFileCache` — the badge
    /// claiming a local cache had been read when in fact a request had failed.
    public func fetchUsage(forceSync: Bool) async throws -> UsageSnapshot {
        guard let token = resolveToken() else {
            return .unavailable(for: .copilot, reason: .notConfigured)
        }
        guard let url = URL(string: usageEndpoint) else {
            return .unavailable(for: .copilot, reason: .providerError)
        }

        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("CopilotChat/0.24.1", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("Glancie", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0

        let data: Data
        switch await transport.usageData(for: request) {
        case .success(let payload): data = payload
        case .failure(let reason): return .unavailable(for: .copilot, reason: reason)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let snapshots = json["quota_snapshots"] as? [String: Any] else {
            return .unavailable(for: .copilot, reason: .malformedResponse)
        }

        /// A pool's remaining share, or nil when the response does not describe it.
        func remaining(_ pool: String) -> Double? {
            guard let entry = snapshots[pool] as? [String: Any] else { return nil }
            let used = (entry["credits_used"] as? Double) ?? (entry["used"] as? Double)
            let total = (entry["credits_total"] as? Double) ?? (entry["limit"] as? Double)
            guard let used, let total, total > 0 else { return nil }
            return max(0.0, min(100.0, 100.0 - (used / total * 100.0)))
        }

        let premiumPct = remaining("premium_interactions")
        let chatPct = remaining("chat")

        // A `quota_snapshots` object naming neither pool describes no quota.
        // Defaulting both to 100% turned that into a full month's allowance.
        guard let primary = premiumPct ?? chatPct else {
            return .unavailable(for: .copilot, reason: .malformedResponse)
        }

        var modelQuotas: [ModelQuotaItem] = []
        if let premiumPct {
            modelQuotas.append(ModelQuotaItem(name: "Premium Interactions", remainingPercentage: premiumPct, quotaType: "Monthly"))
        }
        if let chatPct {
            modelQuotas.append(ModelQuotaItem(name: "Chat Requests", remainingPercentage: chatPct, quotaType: "Monthly"))
        }

        return UsageSnapshot(
            provider: .copilot,
            hourlyRemainingPercentage: primary,
            hourlyResetCountdown: 86400 * 10,
            weeklyRemainingPercentage: chatPct,
            weeklyResetCountdown: chatPct == nil ? nil : 86400 * 10,
            modelQuotas: modelQuotas,
            strategyUsed: .oauthKeychain
        )
    }
    
    public var credentialFingerprint: String? {
        resolveToken().map(UsageSnapshot.fingerprint)
    }

    private func resolveToken() -> String? {
        if let env = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] ?? ProcessInfo.processInfo.environment["COPILOT_TOKEN"], !env.isEmpty {
            return env
        }
        
        let path1 = homeDirectory + configPath
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path1)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (_, value) in json {
                if let dict = value as? [String: Any], let token = dict["oauth_token"] as? String, !token.isEmpty {
                    return token
                }
            }
        }
        
        let path2 = homeDirectory + appsConfigPath
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path2)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (_, value) in json {
                if let dict = value as? [String: Any], let token = dict["oauth_token"] as? String, !token.isEmpty {
                    return token
                }
            }
        }
        
        return nil
    }
}
