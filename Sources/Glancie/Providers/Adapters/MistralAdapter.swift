import Foundation

/// Mistral AI Adapter. Detects a configured key; reports no metered quota.
public final class MistralAdapter: AIProviderAdapter {
    public let type: AIProviderType = .mistral
    
    private let homeDirectory: String
    
    public init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }
    
    public var isDetected: Bool {
        if let key = ProcessInfo.processInfo.environment["MISTRAL_API_KEY"], !key.isEmpty {
            return true
        }
        let path = homeDirectory + "/.config/mistral/api_key"
        return FileManager.default.fileExists(atPath: path)
    }
    
    public func checkAvailability() async -> Bool {
        return isDetected
    }
    
    /// Reports whether a key is configured, and nothing more.
    ///
    /// This used to call `/v1/models` and return a flat 95%. That endpoint
    /// lists what the key may call — it carries no spend, no balance and no
    /// rate budget — and the 95% survived an empty model list, an unreachable
    /// API and an expired key alike. Mistral is pay-as-you-go, so until a
    /// usage endpoint is wired up there is no metered figure to show.
    public func fetchUsage(forceSync: Bool) async throws -> UsageSnapshot {
        guard resolveAPIKey() != nil else {
            return .unavailable(for: .mistral, reason: .notConfigured)
        }
        return .unavailable(for: .mistral, reason: .notMeasured)
    }

    private func resolveAPIKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["MISTRAL_API_KEY"], !key.isEmpty {
            return key
        }
        let path = homeDirectory + "/.config/mistral/api_key"
        if let key = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        return nil
    }
}
