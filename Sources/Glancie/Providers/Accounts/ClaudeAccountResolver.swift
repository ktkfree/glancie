import Foundation

/// Finds the Claude accounts on this machine.
///
/// Claude Code has no native multi-account support; a separate config directory
/// per account (`CLAUDE_CONFIG_DIR`) is the established workaround. Each such
/// directory carries its own `.claude.json` — with its own account *and its own
/// usage cache* — so every profile is a fully readable account, not just a name.
///
/// The desktop app is a second source for the same logins, and contributes only
/// identity: it stores no usage of its own.
public final class ClaudeAccountResolver: AccountResolver {
    public let provider: AIProviderType = .claudeCode
    public let primarySourceID: String = "claude.cli"

    public init() {}

    /// One Claude Code configuration on this machine.
    public struct Profile: Equatable {
        /// The `.claude.json` holding the account and its usage cache.
        public var configPath: String
        /// The directory whose file-system activity means this profile is working.
        public var homeDirectory: String
        /// True for the profile a bare `claude` invocation uses.
        public var isDefault: Bool
    }

    // MARK: - CLI

    /// Every Claude Code profile on this machine, the default one first.
    public static func profiles() -> [Profile] {
        var found: [Profile] = []
        var seenConfigs = Set<String>()

        func append(configPath: String, homeDirectory: String, isDefault: Bool) {
            guard FileManager.default.fileExists(atPath: configPath),
                  seenConfigs.insert(configPath).inserted else { return }
            found.append(Profile(configPath: configPath, homeDirectory: homeDirectory, isDefault: isDefault))
        }

        // An explicit config dir wins, because that is what the shell would use.
        if let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !configDir.isEmpty {
            append(
                configPath: (configDir as NSString).appendingPathComponent(".claude.json"),
                homeDirectory: configDir,
                isDefault: true
            )
        }

        let home = AccountFileReader.home
        append(
            configPath: home.appendingPathComponent(".claude.json").path,
            homeDirectory: home.appendingPathComponent(".claude").path,
            isDefault: found.isEmpty
        )

        // Alternate profile homes keep their config inside the directory itself.
        for directory in AccountFileReader.siblingProfileDirectories(prefix: ".claude") {
            append(
                configPath: (directory as NSString).appendingPathComponent(".claude.json"),
                homeDirectory: directory,
                isDefault: false
            )
        }

        return found
    }

    public func resolveAccounts() async -> [AccountIdentity] {
        cliAccounts() + desktopAccounts()
    }

    private func cliAccounts() -> [AccountIdentity] {
        Self.profiles().compactMap { profile -> AccountIdentity? in
            guard let config = AccountFileReader.json(atPath: profile.configPath),
                  let account = config["oauthAccount"] as? [String: Any] else { return nil }

            let uuid = account["accountUuid"] as? String
            let email = account["emailAddress"] as? String
            guard let identifier = uuid ?? email else { return nil }

            return AccountIdentity(
                id: identifier,
                provider: .claudeCode,
                source: AccountSource(
                    id: "claude.cli",
                    kind: .cli,
                    displayName: profile.isDefault ? "Claude Code" : "Claude Code (\(Self.profileLabel(profile)))",
                    rootPath: profile.homeDirectory
                ),
                email: email,
                displayName: (account["displayName"] as? String) ?? (account["fullName"] as? String),
                organization: account["organizationName"] as? String,
                planName: Self.planName(from: account),
                // A profile is readable exactly when its own config holds usage
                // for the account signed into it.
                usageReadable: ClaudeCodeAdapter.snapshot(fromConfig: config) != nil
            )
        }
    }

    private static func profileLabel(_ profile: Profile) -> String {
        (profile.homeDirectory as NSString).lastPathComponent
    }

    /// `organizationType` carries the subscription tier (`claude_pro`,
    /// `claude_max`, ...); `billingType` only says how it is paid for.
    private static func planName(from account: [String: Any]) -> String? {
        guard let raw = account["organizationType"] as? String, !raw.isEmpty else { return nil }
        switch raw {
        case "claude_pro": return "Claude Pro"
        case "claude_max": return "Claude Max"
        case "claude_team": return "Claude Team"
        case "claude_enterprise": return "Claude Enterprise"
        default:
            return raw
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    // MARK: - Desktop app

    /// Where the desktop app files its per-account state.
    ///
    /// Both trees are laid out `<accountUuid>/<organizationUuid>/`, so the
    /// *first* level enumerates the logins the app has been used with. The
    /// second level does not: an account with two organizations would otherwise
    /// be read as two accounts.
    private static let desktopAccountTrees = [
        "claude-code-sessions",
        "local-agent-mode-sessions"
    ]

    private func desktopAccounts() -> [AccountIdentity] {
        let root = AccountFileReader.home
            .appendingPathComponent("Library/Application Support/Claude")
        guard AccountFileReader.directoryExists(root.path) else { return [] }

        let config = AccountFileReader.json(atPath: root.appendingPathComponent("config.json").path) ?? [:]
        let currentUUID = config["lastKnownAccountUuid"] as? String

        var ordered: [String] = []
        if let currentUUID { ordered.append(currentUUID) }
        for tree in Self.desktopAccountTrees {
            let path = root.appendingPathComponent(tree).path
            for uuid in AccountFileReader.uuidDirectoryNames(in: path) where !ordered.contains(uuid) {
                ordered.append(uuid)
            }
        }
        guard !ordered.isEmpty else { return [] }

        let source = AccountSource(
            id: "claude.desktop",
            kind: .desktopApp,
            displayName: "Claude Desktop",
            rootPath: root.path,
            bundleIdentifiers: ["com.anthropic.claudefordesktop"]
        )

        return ordered.map { uuid in
            AccountIdentity(
                id: uuid,
                provider: .claudeCode,
                source: source,
                // The desktop app stores neither an address nor any usage of its
                // own; the CLI identity fills the address in when UUIDs match.
                email: nil,
                usageReadable: false
            )
        }
    }
}
