import Foundation

/// Moonshot / Kimi Adapter querying user balance
public final class KimiAdapter: AIProviderAdapter {
    public let type: AIProviderType = .kimi
    
    private let balanceEndpoint = "https://api.moonshot.cn/v1/users/me/balance"
    private let homeDirectory: String
    private let transport: UsageTransport
    
    public init(homeDirectory: String = NSHomeDirectory(), transport: UsageTransport = URLSession.shared) {
        self.homeDirectory = homeDirectory
        self.transport = transport
    }
    
    public var isDetected: Bool {
        if let key = ProcessInfo.processInfo.environment["MOONSHOT_API_KEY"] ?? ProcessInfo.processInfo.environment["KIMI_API_KEY"], !key.isEmpty {
            return true
        }
        let path = homeDirectory + "/.config/moonshot/api_key"
        return FileManager.default.fileExists(atPath: path)
    }
    
    public func checkAvailability() async -> Bool {
        return isDetected
    }
    
    /// Reads the account balance, or reports why it could not.
    ///
    /// The old failure path returned 86% and "Balance ¥43.00" — invented
    /// figures, timestamped now, badged `.oauthKeychain`. A rejected key looked
    /// exactly like a healthy account with money in it.
    public func fetchUsage(forceSync: Bool) async throws -> UsageSnapshot {
        guard let apiKey = resolveAPIKey() else {
            return .unavailable(for: .kimi, reason: .notConfigured)
        }
        guard let url = URL(string: balanceEndpoint) else {
            return .unavailable(for: .kimi, reason: .providerError)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 6.0

        let data: Data
        switch await transport.usageData(for: request) {
        case .success(let payload): data = payload
        case .failure(let reason): return .unavailable(for: .kimi, reason: reason)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = json["data"] as? [String: Any],
              let availableBalance = Self.numeric(dataObj["available_balance"]) else {
            return .unavailable(for: .kimi, reason: .malformedResponse)
        }

        // `available_balance` is what the account can actually spend, and
        // Moonshot documents it as already covering cash and vouchers together.
        // Adding `voucher_balance` on top counted every coupon twice: the
        // official example of 49.59 available / 46.59 voucher / 3.00 cash was
        // reported as ¥96.18.
        let voucherBalance = Self.numeric(dataObj["voucher_balance"])
        // Cash can go negative when an account is in arrears, which is a real
        // state and not a floor at zero — it just cannot be shown as a share of
        // anything, so only the amount is displayed.
        let cashBalance = Self.numeric(dataObj["cash_balance"])

        let pct = Self.share(of: availableBalance)

        var modelQuotas: [ModelQuotaItem] = [
            ModelQuotaItem(
                name: "Total Balance (\(Self.yuan(availableBalance)))",
                remainingPercentage: pct,
                quotaType: "CNY Balance"
            )
        ]
        if let cashBalance {
            modelQuotas.append(
                ModelQuotaItem(
                    name: "Cash Balance (\(Self.yuan(cashBalance)))",
                    remainingPercentage: Self.share(of: cashBalance),
                    quotaType: "Cash"
                )
            )
        }
        if let voucherBalance {
            modelQuotas.append(
                ModelQuotaItem(
                    name: "Vouchers (\(Self.yuan(voucherBalance)))",
                    remainingPercentage: Self.share(of: voucherBalance),
                    quotaType: "Voucher"
                )
            )
        }

        return UsageSnapshot(
            provider: .kimi,
            hourlyRemainingPercentage: pct,
            hourlyResetCountdown: nil,
            weeklyRemainingPercentage: pct,
            weeklyResetCountdown: nil,
            modelQuotas: modelQuotas,
            strategyUsed: .oauthKeychain
        )
    }

    /// JSON numbers arrive as `Int` or `Double` depending on how they were
    /// written, and a balance of exactly `0` must stay a value rather than
    /// become "the field was missing".
    private static func numeric(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func yuan(_ amount: Double) -> String {
        String(format: "¥%.2f", amount)
    }

    /// Moonshot publishes no ceiling, so this scale is a display convention
    /// rather than a quota. Tracked in #13 along with the other providers whose
    /// balances are forced into a session percentage.
    private static func share(of amount: Double) -> Double {
        min(100.0, max(0.0, (amount / 50.0) * 100.0))
    }

    public var credentialFingerprint: String? {
        resolveAPIKey().map(UsageSnapshot.fingerprint)
    }

    private func resolveAPIKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["MOONSHOT_API_KEY"] ?? ProcessInfo.processInfo.environment["KIMI_API_KEY"], !key.isEmpty {
            return key
        }
        let path = homeDirectory + "/.config/moonshot/api_key"
        if let key = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        return nil
    }
}
