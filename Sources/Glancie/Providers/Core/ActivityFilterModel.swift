import Foundation

/// Result of evaluating a file system event for AI activity
public enum ActivityEvaluationResult: Equatable {
    case ignored(reason: String)
    case immediateStreaming(reason: String)
    case candidateBurst(reason: String)
    
    public var isIgnored: Bool {
        if case .ignored = self { return true }
        return false
    }
    
    public var isImmediateStreaming: Bool {
        if case .immediateStreaming = self { return true }
        return false
    }
}

/// Declarative rule defining how a specific AI Provider's activity is detected and filtered
public struct ProviderFilterRule {
    public var provider: AIProviderType
    
    /// Root directory paths relative to user home or absolute
    public var relativeRootPaths: [String]
    
    /// Path substrings to strictly ignore for this provider
    public var pathBlacklist: [String]
    
    /// Whitelist path substrings (e.g. "messages", "transcripts", "chat")
    public var pathWhitelist: [String]
    
    /// Content keywords in the file tail that indicate NON-AI or local meta command (e.g. "/usage", "local_command")
    public var contentBlacklistKeywords: [String]
    
    /// Content keywords in the file tail that indicate authentic AI generation/response
    public var contentWhitelistKeywords: [String]
    
    /// Time window in seconds to count burst write events
    public var burstWindow: TimeInterval
    
    /// Number of write events required within the window to qualify as a burst
    public var burstThreshold: Int
    
    /// Custom evaluation hook for specialized provider logic
    public var customEvaluator: ((_ path: String, _ tailContent: String?) -> ActivityEvaluationResult?)?
    
    public init(
        provider: AIProviderType,
        relativeRootPaths: [String],
        pathBlacklist: [String] = [],
        pathWhitelist: [String] = [],
        contentBlacklistKeywords: [String] = [],
        contentWhitelistKeywords: [String] = [],
        burstWindow: TimeInterval = 2.5,
        burstThreshold: Int = 2,
        customEvaluator: ((_ path: String, _ tailContent: String?) -> ActivityEvaluationResult?)? = nil
    ) {
        self.provider = provider
        self.relativeRootPaths = relativeRootPaths
        self.pathBlacklist = pathBlacklist
        self.pathWhitelist = pathWhitelist
        self.contentBlacklistKeywords = contentBlacklistKeywords
        self.contentWhitelistKeywords = contentWhitelistKeywords
        self.burstWindow = burstWindow
        self.burstThreshold = burstThreshold
        self.customEvaluator = customEvaluator
    }
}
