import Foundation

/// Zed AI Adapter reading ~/.config/zed/settings.json
public final class ZedAdapter: AIProviderAdapter {
    public let type: AIProviderType = .zed
    
    private let homeDirectory: String
    private let zedConfigPath = "/.config/zed/settings.json"
    private let zedAppPath = "/Applications/Zed.app"
    
    public init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }
    
    public var isDetected: Bool {
        if FileManager.default.fileExists(atPath: zedAppPath) {
            return true
        }
        let p1 = homeDirectory + zedConfigPath
        return FileManager.default.fileExists(atPath: p1)
    }
    
    public func checkAvailability() async -> Bool {
        return isDetected
    }
    
    /// Zed's settings file names the configured model; it does not meter it.
    ///
    /// The previous 97% was a constant, returned even for a settings file
    /// containing only `{}` — an editor preference presented on the bar as a
    /// measured quota. Which model is selected is a setting, so it is reported
    /// as the plan, and the quota is reported as unmeasured.
    public func fetchUsage(forceSync: Bool) async throws -> UsageSnapshot {
        return .unavailable(
            for: .zed,
            reason: isDetected ? .notMeasured : .notConfigured,
            planName: configuredModelName().map { "Zed AI · \($0)" }
        )
    }

    /// The assistant's default model from the local settings, when set.
    func configuredModelName() -> String? {
        let path = homeDirectory + zedConfigPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assistant = json["assistant"] as? [String: Any],
              let defaultModel = assistant["default_model"] as? [String: Any],
              let modelName = defaultModel["model"] as? String,
              !modelName.isEmpty else { return nil }
        return modelName
    }
}
