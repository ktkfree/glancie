import Foundation

/// Finds the Codex / ChatGPT accounts on this machine.
///
/// The CLI writes an OAuth `id_token` into `~/.codex/auth.json` whose claims
/// already carry the address, the plan and the account id — nothing has to be
/// fetched. The desktop app keeps a directory per workspace under its own
/// container and stamps the workspace id into each directory name.
public final class CodexAccountResolver: AccountResolver {
    public let provider: AIProviderType = .openAICodex
    /// `OpenAI_CodexAdapter` reads `~/.codex`, not the desktop app's container.
    public let primarySourceID: String = "codex.cli"

    public init() {}

    public func resolveAccounts() async -> [AccountIdentity] {
        cliAccounts() + desktopAccounts()
    }

    // MARK: - CLI

    /// One Codex CLI configuration on this machine.
    public struct Profile: Equatable {
        public var authPath: String
        /// The directory whose file-system activity means this profile is working.
        public var homeDirectory: String
        public var isDefault: Bool
    }

    /// Every Codex profile on this machine, the one a bare `codex` would use first.
    public static func profiles() -> [Profile] {
        var found: [Profile] = []
        var seen = Set<String>()

        func append(homeDirectory: String, isDefault: Bool) {
            let authPath = (homeDirectory as NSString).appendingPathComponent("auth.json")
            guard FileManager.default.fileExists(atPath: authPath),
                  seen.insert(authPath).inserted else { return }
            found.append(Profile(authPath: authPath, homeDirectory: homeDirectory, isDefault: isDefault))
        }

        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
            append(homeDirectory: codexHome, isDefault: true)
        }
        for directory in AccountFileReader.siblingProfileDirectories(prefix: ".codex") {
            append(homeDirectory: directory, isDefault: found.isEmpty)
        }
        return found
    }

    /// The identity claims of one `auth.json`, or nil if it holds an API key
    /// rather than an OAuth login.
    public static func identityClaims(atPath path: String) -> (
        email: String?,
        name: String?,
        accountID: String?,
        planType: String?,
        organization: String?
    )? {
        guard let root = AccountFileReader.json(atPath: path),
              let tokens = root["tokens"] as? [String: Any],
              let idToken = tokens["id_token"] as? String,
              let claims = JWTClaims.payload(of: idToken) else { return nil }

        let auth = claims["https://api.openai.com/auth"] as? [String: Any] ?? [:]

        let organizations = auth["organizations"] as? [[String: Any]] ?? []
        let defaultOrganization = organizations.first { ($0["is_default"] as? Bool) == true }
            ?? organizations.first

        return (
            email: claims["email"] as? String,
            name: claims["name"] as? String,
            accountID: (auth["chatgpt_account_id"] as? String) ?? (tokens["account_id"] as? String),
            planType: auth["chatgpt_plan_type"] as? String,
            organization: defaultOrganization?["title"] as? String
        )
    }

    public static func planName(fromPlanType raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw {
        case "free": return "ChatGPT Free"
        case "plus": return "ChatGPT Plus"
        case "pro": return "ChatGPT Pro"
        case "team": return "ChatGPT Team"
        case "enterprise": return "ChatGPT Enterprise"
        default: return "ChatGPT \(raw.capitalized)"
        }
    }

    private func cliAccounts() -> [AccountIdentity] {
        Self.profiles().compactMap { profile -> AccountIdentity? in
            guard let claims = Self.identityClaims(atPath: profile.authPath) else { return nil }
            guard let identifier = claims.accountID ?? claims.email else { return nil }

            return AccountIdentity(
                id: identifier,
                provider: .openAICodex,
                source: AccountSource(
                    id: "codex.cli",
                    kind: .cli,
                    displayName: profile.isDefault
                        ? "Codex CLI"
                        : "Codex CLI (\((profile.homeDirectory as NSString).lastPathComponent))",
                    rootPath: profile.homeDirectory
                ),
                email: claims.email,
                displayName: claims.name,
                organization: claims.organization,
                planName: Self.planName(fromPlanType: claims.planType),
                // A profile is readable exactly when one of its own rollouts
                // has recorded a rate limit; a freshly authenticated CODEX_HOME
                // is a known account whose usage nothing has measured yet.
                usageReadable: !OpenAI_CodexAdapter().snapshot(for: profile).isSimulated
            )
        }
    }

    // MARK: - Desktop app

    private func desktopAccounts() -> [AccountIdentity] {
        let appID = "com.openai.chat"
        let root = AccountFileReader.home
            .appendingPathComponent("Library/Application Support/\(appID)")
        guard AccountFileReader.directoryExists(root.path) else { return [] }

        // `activeUserWorkspaceID` is a JSON *string* holding the signed-in
        // workspace and user ids.
        var activeWorkspace: String?
        if let raw = AccountPreferencesReader.string("activeUserWorkspaceID", appID: appID),
           let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            activeWorkspace = object["workspaceID"] as? String
        }

        // Per-workspace conversation stores name themselves after the workspace,
        // so their suffixes are every account the app has held.
        let seenWorkspaces = AccountFileReader.directorySuffixes(
            in: root.path,
            prefix: "conversations-v3-"
        )

        var ordered: [String] = []
        if let activeWorkspace { ordered.append(activeWorkspace) }
        for workspace in seenWorkspaces.sorted() where !ordered.contains(workspace) {
            ordered.append(workspace)
        }
        guard !ordered.isEmpty else { return [] }

        let source = AccountSource(
            id: "codex.desktop",
            kind: .desktopApp,
            displayName: "ChatGPT Desktop",
            rootPath: root.path,
            bundleIdentifiers: ["com.openai.chat", "com.openai.codex"]
        )

        return ordered.map { workspace in
            AccountIdentity(
                id: workspace,
                provider: .openAICodex,
                source: source,
                // The desktop app exposes no quota of its own.
                usageReadable: false
            )
        }
    }
}
