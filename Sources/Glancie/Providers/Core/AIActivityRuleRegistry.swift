import Foundation

/// Central registry managing blacklist and whitelist rules for all AI providers
public final class AIActivityRuleRegistry {
    public static let shared = AIActivityRuleRegistry()
    
    /// Global file extensions that never represent active AI token streaming.
    ///
    /// Read on the FSEvents queue for every event and written from wherever a
    /// rule change comes from, so it lives behind the same lock as the rules
    /// rather than beside them as a bare `var`.
    private var _globalBlacklistedExtensions: Set<String> = [
        "lock", "tmp", "temp", "sock", "socket", "pid", "plist",
        "swp", "db-journal", "vscdb-journal", "ds_store", "crumb"
    ]
    
    /// Global path substrings to strictly ignore across all providers
    private var _globalBlacklistedSubpaths: [String] = [
        "/cache/", "/Cache/", "/telemetry/", "/mcp/",
        "Code Cache", "GPUCache", "logs/analytics", "Crashpad",
        "User/globalStorage", "Cookies", "Preferences", "settings.json",
        ".session.lock", "workspaceStorage", ".git/"
    ]
    
    /// Provider-specific rules dictionary
    private var rules: [AIProviderType: ProviderFilterRule] = [:]
    private let lock = NSLock()

    public var globalBlacklistedExtensions: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return _globalBlacklistedExtensions
    }

    public var globalBlacklistedSubpaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _globalBlacklistedSubpaths
    }
    
    public init() {
        registerDefaultRules()
    }
    
    // MARK: - Default Rules Registration
    
    private func registerDefaultRules() {
        // 1. Claude Code
        registerRule(ProviderFilterRule(
            provider: .claudeCode,
            relativeRootPaths: [
                ".claude",
                // The desktop app's own Claude Code sessions land here. Its
                // plain chat does not: that conversation lives on the server and
                // leaves only IndexedDB churn behind, which says a window is
                // open rather than that a model is answering — `runningApps`
                // answers that question from the workspace instead.
                "Library/Application Support/Claude/claude-code-sessions",
                "Library/Application Support/Claude/local-agent-mode-sessions"
            ],
            pathBlacklist: [
                "/cache/", "projects_metadata", "cost_", ".session.lock",
                // Glancie's own `/usage` probe writes a transcript like any
                // other invocation. Reading it as the user working would make
                // the probe the cause of the next probe.
                ClaudeCodeAdapter.probeWorkingDirectoryName
            ],
            pathWhitelist: [
                "messages", "transcripts", "projects", "conversation",
                "claude-code-sessions", "local-agent-mode-sessions"
            ],
            contentBlacklistKeywords: [
                "<command-name>/usage",
                "<command-name>/cost",
                "<command-name>/help",
                "subtype\":\"local_command\"",
                "\"local_command\"",
                "local-command-caveat",
                "\"isMeta\":true"
            ],
            contentWhitelistKeywords: [
                "\"role\":\"assistant\"",
                "\"type\":\"assistant\"",
                "\"role\":\"user\"",
                "\"type\":\"user\""
            ],
            burstWindow: 2.0,
            burstThreshold: 2
        ))
        
        // 2. Antigravity (AGY)
        registerRule(ProviderFilterRule(
            provider: .antigravity,
            relativeRootPaths: [
                ".gemini/antigravity-cli",
                ".gemini"
            ],
            pathBlacklist: [
                ".session.lock", "mcp-servers.json", "analytics"
            ],
            pathWhitelist: [
                "transcript", "brain", "logs", "tasks"
            ],
            contentBlacklistKeywords: [
                "\"/usage\"",
                "local_command"
            ],
            contentWhitelistKeywords: [
                "PLANNER_RESPONSE",
                "USER_INPUT",
                "USER_EXPLICIT",
                "tool_calls",
                "\"role\":\"model\"",
                "\"source\":\"MODEL\"",
                "\"source\":\"USER_EXPLICIT\""
            ],
            burstWindow: 2.5,
            burstThreshold: 2
        ))
        
        // 3. Cursor
        registerRule(ProviderFilterRule(
            provider: .cursor,
            relativeRootPaths: [
                "Library/Application Support/Cursor",
                ".cursor"
            ],
            pathBlacklist: [
                "state.vscdb", "GPUCache", "Crashpad", "logs/analytics"
            ],
            pathWhitelist: [
                "chat", "aiservice", "composer", "conversations"
            ],
            contentBlacklistKeywords: ["heartbeat", "telemetry", "ping"],
            contentWhitelistKeywords: ["assistant", "generation", "message"],
            burstWindow: 2.5,
            burstThreshold: 2
        ))
        
        // 5. OpenAI Codex
        registerRule(ProviderFilterRule(
            provider: .openAICodex,
            relativeRootPaths: [".codex"],
            pathBlacklist: ["cache", "credentials"],
            pathWhitelist: ["sessions", "stream", "chat", "history"],
            contentBlacklistKeywords: ["usage", "ping"],
            contentWhitelistKeywords: ["assistant", "choices", "delta"],
            burstWindow: 2.0,
            burstThreshold: 2
        ))
        
        // 6. GitHub Copilot
        registerRule(ProviderFilterRule(
            provider: .copilot,
            relativeRootPaths: [".config/github-copilot"],
            pathBlacklist: ["telemetry", "hosts.json"],
            pathWhitelist: ["logs", "chat", "conversations"],
            contentBlacklistKeywords: ["auth", "token", "ping"],
            contentWhitelistKeywords: ["completion", "assistant"],
            burstWindow: 2.0,
            burstThreshold: 2
        ))
        
        // 7. Windsurf & Zed
        registerRule(ProviderFilterRule(
            provider: .windsurf,
            relativeRootPaths: [".codeium"],
            pathBlacklist: ["cache", "analytics"],
            pathWhitelist: ["chat", "logs", "conversations"],
            burstWindow: 2.5,
            burstThreshold: 2
        ))
        
        registerRule(ProviderFilterRule(
            provider: .zed,
            relativeRootPaths: [".config/zed"],
            pathBlacklist: ["settings.json", "keymap.json"],
            pathWhitelist: ["conversations", "assistant", "threads"],
            burstWindow: 2.0,
            burstThreshold: 2
        ))
    }
    
    // MARK: - Rule Management APIs (Easy to Add, Modify, Delete)
    
    /// Register or replace a provider filter rule
    public func registerRule(_ rule: ProviderFilterRule) {
        lock.lock()
        defer { lock.unlock() }
        rules[rule.provider] = rule
    }
    
    /// Retrieve the rule for a provider
    public func rule(for provider: AIProviderType) -> ProviderFilterRule? {
        lock.lock()
        defer { lock.unlock() }
        return rules[provider]
    }
    
    /// Retrieve all active rules
    public var allRules: [ProviderFilterRule] {
        lock.lock()
        defer { lock.unlock() }
        return Array(rules.values)
    }
    
    /// Remove a rule for a provider
    public func removeRule(for provider: AIProviderType) {
        lock.lock()
        defer { lock.unlock() }
        rules.removeValue(forKey: provider)
    }
    
    /// Mutate an existing rule with a closure
    public func updateRule(for provider: AIProviderType, update: (inout ProviderFilterRule) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        if var existing = rules[provider] {
            update(&existing)
            rules[provider] = existing
        }
    }
    
    /// Add global extension to ignore
    public func addGlobalBlacklistExtension(_ ext: String) {
        lock.lock()
        defer { lock.unlock() }
        _globalBlacklistedExtensions.insert(ext.lowercased())
    }
    
    /// Add global path substring to ignore
    public func addGlobalBlacklistSubpath(_ subpath: String) {
        lock.lock()
        defer { lock.unlock() }
        _globalBlacklistedSubpaths.append(subpath)
    }
    
    /// Add keyword to content blacklist for a specific provider
    public func addContentBlacklistKeyword(_ keyword: String, for provider: AIProviderType) {
        updateRule(for: provider) { rule in
            if !rule.contentBlacklistKeywords.contains(keyword) {
                rule.contentBlacklistKeywords.append(keyword)
            }
        }
    }
    
    /// Add keyword to content whitelist for a specific provider
    public func addContentWhitelistKeyword(_ keyword: String, for provider: AIProviderType) {
        updateRule(for: provider) { rule in
            if !rule.contentWhitelistKeywords.contains(keyword) {
                rule.contentWhitelistKeywords.append(keyword)
            }
        }
    }
}
