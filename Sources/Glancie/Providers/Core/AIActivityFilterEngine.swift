import Foundation

/// Fast, low-overhead filter engine that evaluates file system events against the rule registry
public final class AIActivityFilterEngine {
    private let registry: AIActivityRuleRegistry
    private var recentEventTimestamps: [AIProviderType: [Date]] = [:]
    private let queue = DispatchQueue(label: "com.glancie.activityfilter", qos: .utility)
    
    public init(registry: AIActivityRuleRegistry = .shared) {
        self.registry = registry
    }
    
    /// Evaluates if an event path is authentic active AI streaming
    public func evaluateEvent(eventPath: String, provider: AIProviderType) -> ActivityEvaluationResult {
        // 1. Global Blacklist check
        let ext = (eventPath as NSString).pathExtension.lowercased()
        if registry.globalBlacklistedExtensions.contains(ext) {
            return .ignored(reason: "Global blacklisted extension: .\(ext)")
        }
        
        for subpath in registry.globalBlacklistedSubpaths {
            if eventPath.contains(subpath) {
                return .ignored(reason: "Global blacklisted subpath: \(subpath)")
            }
        }
        
        // 2. Provider Rule check
        guard let rule = registry.rule(for: provider) else {
            // Fallback for providers without explicit rules: check for log or jsonl
            if eventPath.hasSuffix(".jsonl") || eventPath.hasSuffix(".log") {
                return .candidateBurst(reason: "Default candidate log file")
            }
            return .ignored(reason: "No rule registered for provider \(provider.rawValue)")
        }
        
        // 2-a. Provider path blacklist
        for blacklisted in rule.pathBlacklist {
            if eventPath.contains(blacklisted) {
                return .ignored(reason: "Provider path blacklist: \(blacklisted)")
            }
        }
        
        // 2-b. Provider path whitelist
        var pathMatchesWhitelist = false
        if rule.pathWhitelist.isEmpty {
            pathMatchesWhitelist = true
        } else {
            for whitelisted in rule.pathWhitelist {
                if eventPath.contains(whitelisted) {
                    pathMatchesWhitelist = true
                    break
                }
            }
        }
        
        guard pathMatchesWhitelist else {
            return .ignored(reason: "Path does not match whitelist")
        }
        
        // 3. Lightweight Tail Content Inspection (if file exists and keywords are defined)
        let tailContent = readTail(path: eventPath, maxBytes: 2048)
        
        // 3-a. Custom Rule Evaluator
        if let custom = rule.customEvaluator, let customResult = custom(eventPath, tailContent) {
            return customResult
        }
        
        if let tail = tailContent {
            // Check content blacklist (e.g. /usage, local_command, isMeta: true)
            for kw in rule.contentBlacklistKeywords {
                if tail.contains(kw) {
                    return .ignored(reason: "Content blacklist keyword matched: \(kw)")
                }
            }
            
            // Check content whitelist (e.g. "role":"assistant", PLANNER_RESPONSE)
            for kw in rule.contentWhitelistKeywords {
                if tail.contains(kw) {
                    return .immediateStreaming(reason: "Content whitelist keyword matched: \(kw)")
                }
            }
        }
        
        // 4. Default to Candidate Burst for whitelisted files without immediate content match
        return .candidateBurst(reason: "Path matches whitelist; requires burst qualification")
    }
    
    /// Tracks bursts and returns true if the provider should be triggered for active streaming
    public func shouldDispatchBurst(provider: AIProviderType, eventPath: String) -> (shouldDispatch: Bool, reason: String) {
        let evaluation = evaluateEvent(eventPath: eventPath, provider: provider)
        
        switch evaluation {
        case .ignored(let reason):
            return (false, "Ignored: \(reason)")
            
        case .immediateStreaming(let reason):
            return (true, "Immediate Streaming: \(reason)")
            
        case .candidateBurst:
            let rule = registry.rule(for: provider)
            let window = rule?.burstWindow ?? 2.5
            let threshold = rule?.burstThreshold ?? 2
            let now = Date()
            
            var timestamps = (recentEventTimestamps[provider] ?? []).filter {
                now.timeIntervalSince($0) <= window
            }
            timestamps.append(now)
            recentEventTimestamps[provider] = timestamps
            
            if timestamps.count >= threshold {
                recentEventTimestamps[provider] = [] // reset
                return (true, "Burst qualified (\(timestamps.count) events in \(window)s)")
            }
            
            return (false, "Candidate burst accumulating (\(timestamps.count)/\(threshold))")
        }
    }
    
    /// Reads the last N bytes of a file efficiently without reading the entire file into memory
    private func readTail(path: String, maxBytes: Int) -> String? {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fileHandle.close() }
        
        do {
            let fileSize = try fileHandle.seekToEnd()
            guard fileSize > 0 else { return nil }
            
            let readOffset = max(0, Int64(fileSize) - Int64(maxBytes))
            try fileHandle.seek(toOffset: UInt64(readOffset))
            
            let data = fileHandle.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
