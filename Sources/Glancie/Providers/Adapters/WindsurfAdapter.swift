import Foundation

/// Windsurf / Codeium Adapter reading ~/.codeium/ or ~/.windsurf/ local credentials and status
public final class WindsurfAdapter: AIProviderAdapter {
    public let type: AIProviderType = .windsurf
    
    private let homeDirectory: String
    private let codeiumConfigPath = "/.codeium/config.json"
    private let codeiumDatabasePath = "/.codeium/database.sqlite"
    private let windsurfAppPath = "/Applications/Windsurf.app"
    
    public init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }
    
    public var isDetected: Bool {
        if FileManager.default.fileExists(atPath: windsurfAppPath) {
            return true
        }
        let p1 = homeDirectory + codeiumConfigPath
        let p2 = homeDirectory + codeiumDatabasePath
        return FileManager.default.fileExists(atPath: p1) || FileManager.default.fileExists(atPath: p2)
    }
    
    public func checkAvailability() async -> Bool {
        return isDetected
    }
    
    /// Reads the plan name, and nothing else.
    ///
    /// `~/.codeium/config.json` names the subscription; it does not count
    /// Cascade requests. The 94% this used to return was a constant that did
    /// not move when the plan changed, when the config was empty, or when the
    /// quota was actually spent — so the plan travels on as account metadata
    /// and the quota is reported as unmeasured.
    public func fetchUsage(forceSync: Bool) async throws -> UsageSnapshot {
        return .unavailable(
            for: .windsurf,
            reason: isDetected ? .notMeasured : .notConfigured,
            planName: readPlanName()
        )
    }

    /// The subscription tier from the local config, when it names one.
    func readPlanName() -> String? {
        let path = homeDirectory + codeiumConfigPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = json["user"] as? [String: Any],
              let plan = user["plan"] as? String,
              !plan.isEmpty else { return nil }
        return "Windsurf \(plan.capitalized)"
    }
}
