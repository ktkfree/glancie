import Foundation

/// Finds the Google accounts behind Gemini and Antigravity.
///
/// Worth spelling out because it is the case that motivated this whole feature:
/// the CLI and the Gemini desktop app authenticate independently, and they are
/// routinely signed into *different* Google accounts. Collapsing them into one
/// "Gemini" figure would attribute one account's quota to the other.
public final class GeminiAccountResolver: AccountResolver {
    public let provider: AIProviderType = .antigravity
    /// `AntigravityAdapter` reads `~/.gemini/antigravity-cli`, so the desktop
    /// app's separate Google login must not claim the provider's figures.
    public let primarySourceID: String = "antigravity.cli"

    public init() {}

    public func resolveAccounts() async -> [AccountIdentity] {
        cliAccounts() + antigravityAccounts() + desktopAccounts()
    }

    // MARK: - Gemini CLI

    private var geminiRoot: URL {
        AccountFileReader.home.appendingPathComponent(".gemini")
    }

    /// `google_accounts.json` is literally `{"active": ..., "old": [...]}` — the
    /// account list, no inference required.
    public static func googleAccountEmails(
        path: String = AccountFileReader.home
            .appendingPathComponent(".gemini/google_accounts.json")
            .path
    ) -> (active: String?, previous: [String]) {
        guard let root = AccountFileReader.json(atPath: path) else { return (nil, []) }
        return (
            root["active"] as? String,
            (root["old"] as? [String]) ?? []
        )
    }

    /// The subject (GAIA id) of the credentials the CLI currently holds, used to
    /// tell a CLI login apart from a desktop login for the same provider.
    private func cliSubject() -> String? {
        let path = geminiRoot.appendingPathComponent("oauth_creds.json").path
        guard let root = AccountFileReader.json(atPath: path),
              let idToken = root["id_token"] as? String,
              let claims = JWTClaims.payload(of: idToken) else { return nil }
        return claims["sub"] as? String
    }

    /// The id every source of the signed-in Google account must agree on.
    ///
    /// The Gemini CLI, the Antigravity CLI and the Antigravity IDE all resolve
    /// against the same `google_accounts.json`, so keying them differently would
    /// split one login into three accounts on the detail screen.
    private func activeAccountKey(activeEmail: String?) -> String? {
        guard let activeEmail else { return nil }
        return cliSubject() ?? activeEmail
    }

    private func cliAccounts() -> [AccountIdentity] {
        guard AccountFileReader.directoryExists(geminiRoot.path) else { return [] }

        let (active, previous) = Self.googleAccountEmails()

        let source = AccountSource(
            id: "gemini.cli",
            kind: .cli,
            displayName: "Gemini CLI",
            rootPath: geminiRoot.path
        )

        var accounts: [AccountIdentity] = []

        if let active, let key = activeAccountKey(activeEmail: active) {
            accounts.append(
                AccountIdentity(
                    id: key,
                    provider: .antigravity,
                    source: source,
                    email: active,
                    usageReadable: false
                )
            )
        }

        // Previously signed-in addresses have no credentials left behind, so
        // they carry identity only — their last known usage comes from the store.
        for email in previous where email != active {
            accounts.append(
                AccountIdentity(
                    id: email,
                    provider: .antigravity,
                    source: source,
                    email: email,
                    usageReadable: false
                )
            )
        }

        return accounts
    }

    // MARK: - Antigravity CLI and IDE

    /// How many of the CLI's logs to read back through before giving up on
    /// finding the address it authenticated as. The newest run normally answers
    /// on the first file; a run that failed before authenticating does not.
    private static let antigravityLogLookback = 8

    /// The address the Antigravity CLI actually authenticated as.
    ///
    /// It holds its own OAuth token and that token is opaque — there is nothing
    /// in it to decode. `google_accounts.json` answers a different question:
    /// who the *shared* Google login is, and the CLI is routinely signed in as
    /// someone else, which is how one account's quota ends up displayed under
    /// another account's address. The CLI does name the account on every run, in
    /// its own log, and that is the only place on disk that says so.
    ///
    /// Reading a log line is not a contract, so a miss falls back to the shared
    /// list rather than dropping the source.
    public static func antigravityCLIEmail(
        logDirectory: String = AccountFileReader.home
            .appendingPathComponent(".gemini/antigravity-cli/log")
            .path
    ) -> String? {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: logDirectory) else { return nil }

        let newestFirst = names
            .filter { $0.hasPrefix("cli-") && $0.hasSuffix(".log") }
            // The name carries `cli-<yyyymmdd>_<hhmmss>.log`, which sorts
            // chronologically as text — cheaper than stat-ing 3,000 files.
            .sorted(by: >)
            .prefix(antigravityLogLookback)

        for name in newestFirst {
            let path = (logDirectory as NSString).appendingPathComponent(name)
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            if let email = authenticatedEmail(inLog: text) { return email }
        }
        return nil
    }

    /// `applyAuthResult: email=someone@example.com, authMethod=consumer, ...`
    static func authenticatedEmail(inLog text: String) -> String? {
        let marker = "applyAuthResult: email="
        guard let range = text.range(of: marker) else { return nil }
        let rest = text[range.upperBound...]
        let email = rest.prefix { !$0.isWhitespace && $0 != "," }
        return email.contains("@") ? String(email) : nil
    }

    /// Antigravity splits its CLI and its IDE into separate homes with separate
    /// OAuth tokens, and they are not always the same login. The IDE resolves
    /// against the shared Google account list; the CLI is asked directly.
    private func antigravityAccounts() -> [AccountIdentity] {
        let (active, _) = Self.googleAccountEmails()
        let cliEmail = Self.antigravityCLIEmail() ?? active
        let candidates: [(relativePath: String, id: String, name: String, kind: AccountSourceKind)] = [
            (".gemini/antigravity-cli", "antigravity.cli", "Antigravity CLI", .cli),
            (".gemini/antigravity", "antigravity.ide", "Antigravity IDE", .ide)
        ]

        return candidates.compactMap { candidate in
            let path = AccountFileReader.home.appendingPathComponent(candidate.relativePath).path
            guard AccountFileReader.directoryExists(path) else { return nil }

            let isCLI = candidate.id == "antigravity.cli"
            let email = isCLI ? cliEmail : active

            // Only the shared login gets the shared key. An address the CLI
            // signed in as on its own is its own account, and keying it to the
            // active login is exactly the mistake that filed the CLI's figures
            // under someone else.
            let key: String? = (email == active)
                ? activeAccountKey(activeEmail: active)
                : email
            guard let key, let email else { return nil }

            return AccountIdentity(
                id: key,
                provider: .antigravity,
                source: AccountSource(
                    id: candidate.id,
                    kind: candidate.kind,
                    displayName: candidate.name,
                    rootPath: path,
                    bundleIdentifiers: candidate.kind == .ide ? ["com.google.antigravity"] : []
                ),
                email: email,
                usageReadable: isCLI
            )
        }
    }

    // MARK: - Gemini desktop app

    private func desktopAccounts() -> [AccountIdentity] {
        let appID = "com.google.GeminiMacOS"
        let root = AccountFileReader.home
            .appendingPathComponent("Library/Application Support/\(appID)")
        guard AccountFileReader.directoryExists(root.path) else { return [] }

        // The desktop app has no plain-text account file; it suffixes several
        // preference keys with the signed-in account's GAIA id instead.
        let gaiaIDs = AccountPreferencesReader.keySuffixes(
            appID: appID,
            prefix: "discoveryInteractionRecords_"
        )
        guard !gaiaIDs.isEmpty else { return [] }

        let source = AccountSource(
            id: "gemini.desktop",
            kind: .desktopApp,
            displayName: "Gemini Desktop",
            rootPath: root.path,
            bundleIdentifiers: ["com.google.GeminiMacOS"]
        )

        return gaiaIDs.map { gaia in
            AccountIdentity(
                id: gaia,
                provider: .antigravity,
                source: source,
                displayName: L10n.googleAccountSuffix(String(gaia.suffix(4))).text,
                // The desktop app leaves an account id in its preferences and
                // nothing else — this login is known but its quota is not
                // readable from disk.
                usageReadable: false
            )
        }
    }
}
