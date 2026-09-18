import Foundation

/// Ollama Adapter querying local Ollama instance (http://localhost:11434/api/tags & ps)
public final class OllamaAdapter: AIProviderAdapter {
    public let type: AIProviderType = .ollama
    
    private let tagsEndpoint = "http://localhost:11434/api/tags"
    private let psEndpoint = "http://localhost:11434/api/ps"
    
    public init() {}
    
    public var isDetected: Bool {
        if FileManager.default.fileExists(atPath: "/usr/local/bin/ollama") ||
           FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ollama") {
            return true
        }
        return false
    }
    
    public func checkAvailability() async -> Bool {
        guard let url = URL(string: tagsEndpoint) else { return isDetected }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                return true
            }
        } catch {}
        return isDetected
    }
    
    public func fetchUsage(forceSync: Bool) async throws -> UsageSnapshot {
        do {
            guard let tagsUrl = URL(string: tagsEndpoint) else { return fallbackSnapshot() }
            var request = URLRequest(url: tagsUrl)
            request.timeoutInterval = 2.0
            
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                return fallbackSnapshot()
            }
            
            var modelQuotas: [ModelQuotaItem] = []
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                
                for model in models {
                    let name = model["name"] as? String ?? "Ollama Model"
                    let size = model["size"] as? Double ?? 0.0
                    let sizeGB = size / (1024 * 1024 * 1024)
                    let sizeFormatted = String(format: "%.1f GB", sizeGB)
                    
                    modelQuotas.append(ModelQuotaItem(
                        name: "\(name) (\(sizeFormatted))",
                        remainingPercentage: 100.0,
                        quotaType: "Local Model"
                    ))
                }
            }
            
            if modelQuotas.isEmpty {
                modelQuotas.append(ModelQuotaItem(name: "Local Service Ready", remainingPercentage: 100.0, quotaType: "Unlimited"))
            }
            
            return UsageSnapshot(
                provider: .ollama,
                hourlyRemainingPercentage: 100.0,
                hourlyResetCountdown: nil,
                weeklyRemainingPercentage: 100.0,
                weeklyResetCountdown: nil,
                modelQuotas: modelQuotas,
                strategyUsed: .cliStatusProbe
            )
        } catch {
            return fallbackSnapshot()
        }
    }
    
    private func fallbackSnapshot() -> UsageSnapshot {
        return UsageSnapshot(
            provider: .ollama,
            hourlyRemainingPercentage: 100.0,
            hourlyResetCountdown: nil,
            weeklyRemainingPercentage: 100.0,
            weeklyResetCountdown: nil,
            modelQuotas: [
                ModelQuotaItem(name: "Local Instance (Offline / Standby)", remainingPercentage: 100.0, quotaType: "Local Unlimited")
            ],
            strategyUsed: isDetected ? .cliStatusProbe : .simulated
        )
    }
}
