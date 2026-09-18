import XCTest
@testable import Glancie

/// Covers the pure parsing and reconciliation logic behind account discovery.
/// The fixtures mirror the real payload shapes byte for byte, including the
/// six-digit fractional seconds and the "percentage used" convention that the
/// display layer inverts.
final class AccountTests: XCTestCase {

    /// The wording asserted below is the Korean wording. Pin it, so the suite
    /// passes on an English Mac and never reads the tester's own preference.
    override func setUp() {
        super.setUp()
        Localization.renderLanguage(.korean)
    }


    // MARK: - Claude cached usage

    private func claudeConfig(
        signedInUUID: String = "c391e248-6ab3-4b57-b740-edbeeee2188d",
        cachedUUID: String = "c391e248-6ab3-4b57-b740-edbeeee2188d",
        sessionResetsAt: String,
        weeklyResetsAt: String
    ) -> [String: Any] {
        [
            "oauthAccount": [
                "accountUuid": signedInUUID,
                "emailAddress": "someone@example.com",
                "displayName": "Someone",
                "organizationName": "Someone's Organization",
                "organizationType": "claude_pro"
            ],
            "cachedUsageUtilization": [
                "fetchedAtMs": Date().timeIntervalSince1970 * 1000.0,
                "accountUuid": cachedUUID,
                "utilization": [
                    "five_hour": [
                        "utilization": 14,
                        "resets_at": sessionResetsAt
                    ],
                    "seven_day": [
                        "utilization": 91,
                        "resets_at": weeklyResetsAt
                    ],
                    "extra_usage": [
                        "is_enabled": false,
                        "monthly_limit": 1000,
                        "used_credits": 0,
                        "utilization": 0,
                        "currency": "USD"
                    ],
                    "limits": [
                        [
                            "kind": "session",
                            "group": "session",
                            "percent": 14,
                            "severity": "normal",
                            "resets_at": sessionResetsAt,
                            "is_active": false
                        ],
                        [
                            "kind": "weekly_all",
                            "group": "weekly",
                            "percent": 91,
                            "severity": "critical",
                            "resets_at": weeklyResetsAt,
                            "is_active": true
                        ]
                    ]
                ]
            ]
        ]
    }

    /// The payload reports percentage *used*; everything the UI shows is
    /// remaining, so 14% used must surface as 86% left.
    func testClaudeCachedUsageIsInvertedAndAttributed() throws {
        let sessionReset = Date().addingTimeInterval(3600)
        let weeklyReset = Date().addingTimeInterval(86400 * 2)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let config = claudeConfig(
            sessionResetsAt: formatter.string(from: sessionReset),
            weeklyResetsAt: formatter.string(from: weeklyReset)
        )

        let snapshot = try XCTUnwrap(ClaudeCodeAdapter.snapshot(fromConfig: config))

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 86.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(snapshot.weeklyRemainingPercentage), 9.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.accountID, "c391e248-6ab3-4b57-b740-edbeeee2188d")
        XCTAssertEqual(snapshot.accountEmail, "someone@example.com")
        XCTAssertEqual(snapshot.planName, "Claude Pro")
        XCTAssertEqual(snapshot.sourceID, "claude.cli")
        XCTAssertEqual(snapshot.strategyUsed, .localFileCache)

        XCTAssertEqual(try XCTUnwrap(snapshot.hourlyResetCountdown), 3600, accuracy: 5)
        XCTAssertEqual(try XCTUnwrap(snapshot.weeklyResetCountdown), 86400 * 2, accuracy: 5)

        // `limits[]` drives the meters; extra usage is disabled so it earns no row.
        XCTAssertEqual(snapshot.modelQuotas.count, 2)
        XCTAssertEqual(snapshot.modelQuotas[0].name, "세션 (5시간)")
        XCTAssertEqual(snapshot.modelQuotas[1].name, "주간 (전체 모델)")
        XCTAssertEqual(snapshot.modelQuotas[1].remainingPercentage, 9.0, accuracy: 0.001)
        // severity "critical" plus is_active must reach the pace line.
        let pace = try XCTUnwrap(snapshot.modelQuotas[1].paceText)
        XCTAssertTrue(pace.contains("임박"))
        XCTAssertTrue(pace.contains("현재 적용 중인 한도"))
    }

    /// Right after an account switch the cache still holds the previous
    /// account's numbers. Pairing them with the new account's address would be
    /// worse than showing nothing.
    func testClaudeUsageRejectedWhenCacheBelongsToAnotherAccount() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date().addingTimeInterval(3600))

        let config = claudeConfig(
            signedInUUID: "aaaaaaaa-0000-0000-0000-000000000000",
            cachedUUID: "bbbbbbbb-1111-1111-1111-111111111111",
            sessionResetsAt: stamp,
            weeklyResetsAt: stamp
        )

        XCTAssertNil(ClaudeCodeAdapter.snapshot(fromConfig: config))
    }

    /// A reset that has already passed carries no information, so it must not be
    /// rendered as an imminent countdown.
    func testElapsedResetBecomesNil() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let past = formatter.string(from: Date().addingTimeInterval(-600))
        XCTAssertNil(ClaudeCodeAdapter.countdown(from: past))
    }

    /// The real payload carries six fractional digits, which `ISO8601DateFormatter`
    /// rejects outright.
    func testTimestampWithMicrosecondsParses() throws {
        let date = try XCTUnwrap(
            ClaudeCodeAdapter.parseTimestamp("2026-08-31T18:49:59.848396+00:00")
        )
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 31
        components.hour = 18
        components.minute = 49
        components.second = 59
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(date, try XCTUnwrap(calendar.date(from: components)))
    }

    // MARK: - JWT claims

    func testJWTPayloadDecoding() throws {
        let payload: [String: Any] = [
            "email": "someone@example.com",
            "name": "Someone",
            "https://api.openai.com/auth": [
                "chatgpt_plan_type": "plus",
                "chatgpt_account_id": "7deb1561-9787-4755-8634-bf01847c0044",
                "organizations": [
                    ["title": "Personal", "is_default": true, "role": "owner"]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        // base64url without padding, exactly as a real token is encoded.
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(encoded).signature"

        let claims = try XCTUnwrap(JWTClaims.payload(of: token))
        XCTAssertEqual(claims["email"] as? String, "someone@example.com")

        let auth = try XCTUnwrap(claims["https://api.openai.com/auth"] as? [String: Any])
        XCTAssertEqual(auth["chatgpt_plan_type"] as? String, "plus")
    }

    func testJWTPayloadRejectsMalformedToken() {
        XCTAssertNil(JWTClaims.payload(of: "not-a-token"))
        XCTAssertNil(JWTClaims.payload(of: "header.###.signature"))
    }

    func testCodexPlanNaming() {
        XCTAssertEqual(CodexAccountResolver.planName(fromPlanType: "free"), "ChatGPT Free")
        XCTAssertEqual(CodexAccountResolver.planName(fromPlanType: "plus"), "ChatGPT Plus")
        XCTAssertEqual(CodexAccountResolver.planName(fromPlanType: "business"), "ChatGPT Business")
        XCTAssertNil(CodexAccountResolver.planName(fromPlanType: nil))
        XCTAssertNil(CodexAccountResolver.planName(fromPlanType: ""))
    }

    // MARK: - Gemini account list

    func testGoogleAccountsFileListsActiveAndPrevious() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("google_accounts_\(UUID().uuidString).json")
        let contents = """
        {"active":"current@example.com","old":["previous@example.com"]}
        """
        try contents.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = GeminiAccountResolver.googleAccountEmails(path: url.path)
        XCTAssertEqual(result.active, "current@example.com")
        XCTAssertEqual(result.previous, ["previous@example.com"])
    }

    func testGoogleAccountsFileMissingIsNotAnError() {
        let result = GeminiAccountResolver.googleAccountEmails(path: "/nonexistent/google_accounts.json")
        XCTAssertNil(result.active)
        XCTAssertTrue(result.previous.isEmpty)
    }

    // MARK: - Reconciliation

    private func identity(
        id: String,
        sourceID: String,
        kind: AccountSourceKind,
        email: String? = nil,
        plan: String? = nil,
        usageReadable: Bool = false
    ) -> AccountIdentity {
        AccountIdentity(
            id: id,
            provider: .claudeCode,
            source: AccountSource(id: sourceID, kind: kind, displayName: sourceID),
            email: email,
            planName: plan,
            usageReadable: usageReadable
        )
    }

    /// The CLI and the desktop app report the same account UUID, so they are one
    /// account seen twice — and the desktop entry, which has no address of its
    /// own, inherits the one the CLI knows.
    func testSameAccountAcrossSourcesCollapsesAndEnriches() throws {
        let merged = AccountRegistry.reconcile([
            identity(id: "uuid-a", sourceID: "claude.cli", kind: .cli, email: "a@example.com", plan: "Claude Pro", usageReadable: true),
            identity(id: "uuid-a", sourceID: "claude.desktop", kind: .desktopApp)
        ])

        XCTAssertEqual(merged.count, 1)
        let account = try XCTUnwrap(merged.first)
        XCTAssertEqual(account.email, "a@example.com")
        XCTAssertEqual(account.planName, "Claude Pro")
        XCTAssertEqual(account.sources.count, 2)
        // Readable through the CLI, so the account as a whole is readable even
        // though the desktop app contributes no quota.
        XCTAssertTrue(account.usageReadable)
        XCTAssertEqual(account.sourceBadgeText, "CLI · App")
    }

    /// The case that motivated the feature: a CLI and a desktop app signed into
    /// two different accounts must stay two accounts.
    func testDifferentAccountsAcrossSourcesStaySeparate() {
        let merged = AccountRegistry.reconcile([
            identity(id: "gaia-110748", sourceID: "gemini.cli", kind: .cli, email: "cli@example.com", usageReadable: true),
            identity(id: "gaia-114377", sourceID: "gemini.desktop", kind: .desktopApp)
        ])

        XCTAssertEqual(merged.count, 2)
        // Readable first, so the detail screen leads with live figures.
        XCTAssertEqual(merged.first?.id, "gaia-110748")
        XCTAssertTrue(merged[0].usageReadable)
        XCTAssertFalse(merged[1].usageReadable)
    }

    // MARK: - Presentation

    func testEmailMaskingKeepsDomain() {
        let account = ResolvedAccount(
            id: "uuid",
            provider: .claudeCode,
            email: "someone@example.com"
        )
        XCTAssertEqual(account.maskedLabel, "s***@example.com")
        XCTAssertEqual(account.displayLabel, "someone@example.com")
        XCTAssertEqual(account.label(masked: true), "s***@example.com")
    }

    func testLabelFallsBackWhenNoEmail() {
        let withName = ResolvedAccount(id: "gaia-1143777949", provider: .antigravity, displayName: "Google 계정 ···7949")
        XCTAssertEqual(withName.displayLabel, "Google 계정 ···7949")
        XCTAssertEqual(withName.maskedLabel, "Google 계정 ···7949")

        let bare = ResolvedAccount(id: "1143777949046379617", provider: .antigravity)
        XCTAssertEqual(bare.displayLabel, "114377794904")
    }

    // MARK: - Which account owns the provider's figures

    private struct StubResolver: AccountResolver {
        let provider: AIProviderType
        let primarySourceID: String
        let identities: [AccountIdentity]
        func resolveAccounts() async -> [AccountIdentity] { identities }
    }

    /// Two accounts, only one of which this machine can read. A provider-level
    /// adapter's single snapshot must be attributed to the readable one on the
    /// source that adapter actually reads — never to the alphabetically first.
    @MainActor
    func testAttributionPrefersTheReadableAccountOnThePrimarySource() async throws {
        let cli = AccountIdentity(
            id: "gaia-110748",
            provider: .antigravity,
            source: AccountSource(id: "antigravity.cli", kind: .cli, displayName: "Antigravity CLI"),
            email: "cli@example.com",
            usageReadable: true
        )
        let desktop = AccountIdentity(
            id: "gaia-114377",
            provider: .antigravity,
            source: AccountSource(id: "gemini.desktop", kind: .desktopApp, displayName: "Gemini Desktop"),
            displayName: "AAA sorts first",
            usageReadable: false
        )

        let registry = AccountRegistry(resolvers: [
            StubResolver(
                provider: .antigravity,
                primarySourceID: "antigravity.cli",
                identities: [desktop, cli]
            )
        ])
        await registry.refreshAccounts()

        XCTAssertEqual(registry.accounts(for: .antigravity).count, 2)
        XCTAssertEqual(registry.attributionAccount(for: .antigravity)?.id, "gaia-110748")
        XCTAssertEqual(registry.readableAccounts(for: .antigravity).map(\.id), ["gaia-110748"])
    }

    /// Every source contributes a directory to watch, tagged with its own
    /// account — that mapping is what lets a write under one profile home mean
    /// "this account is working" rather than "this provider is working".
    @MainActor
    func testActivityPathsCarryTheAccountTheyBelongTo() async {
        let registry = AccountRegistry(resolvers: [
            StubResolver(
                provider: .claudeCode,
                primarySourceID: "claude.cli",
                identities: [
                    AccountIdentity(
                        id: "uuid-default",
                        provider: .claudeCode,
                        source: AccountSource(id: "claude.cli", kind: .cli, displayName: "Claude Code", rootPath: "/tmp/.claude"),
                        usageReadable: true
                    ),
                    AccountIdentity(
                        id: "uuid-work",
                        provider: .claudeCode,
                        source: AccountSource(id: "claude.cli", kind: .cli, displayName: "Claude Code (work)", rootPath: "/tmp/.claude-work"),
                        usageReadable: true
                    )
                ]
            )
        ])
        await registry.refreshAccounts()

        let paths = registry.activityPaths
        XCTAssertEqual(paths.count, 2)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: paths.map { ($0.path, $0.accountID) }),
            ["/tmp/.claude": "uuid-default", "/tmp/.claude-work": "uuid-work"]
        )
    }

    // MARK: - Stale snapshots

    /// A restored reading must never advertise a reset that has already
    /// happened; a window that rolled over becomes unknown rather than wrong.
    func testAgingRewindsCountdownsAndDropsElapsedWindows() throws {
        let capturedAt = Date().addingTimeInterval(-1800)
        let snapshot = UsageSnapshot(
            provider: .claudeCode,
            hourlyRemainingPercentage: 60.0,
            hourlyResetCountdown: 3600,
            weeklyRemainingPercentage: 20.0,
            weeklyResetCountdown: 600,
            modelQuotas: [
                ModelQuotaItem(name: "세션", remainingPercentage: 60, quotaType: "5-Hour Session", resetCountdown: 3600),
                ModelQuotaItem(name: "주간", remainingPercentage: 20, quotaType: "Weekly Limit", resetCountdown: 600)
            ],
            capturedAt: capturedAt
        )

        let aged = snapshot.agedToNow()
        XCTAssertEqual(try XCTUnwrap(aged.hourlyResetCountdown), 1800, accuracy: 5)
        XCTAssertNil(aged.weeklyResetCountdown, "a window that already reset must not report a countdown")
        XCTAssertEqual(try XCTUnwrap(aged.modelQuotas[0].resetCountdown), 1800, accuracy: 5)
        XCTAssertNil(aged.modelQuotas[1].resetCountdown)
        // Percentages are left alone: they are what was measured.
        XCTAssertEqual(aged.hourlyRemainingPercentage, 60.0)
        XCTAssertTrue(aged.isStale)
    }

    func testFreshSnapshotIsNotStale() {
        let snapshot = UsageSnapshot(provider: .claudeCode, hourlyRemainingPercentage: 50.0)
        XCTAssertFalse(snapshot.isStale)
    }

    // MARK: - Usage store

    func testUsageStoreRoundTripsAndRefusesOlderWrites() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("account-usage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = AccountUsageStore(fileURL: url)
        let recent = UsageSnapshot(
            provider: .claudeCode,
            hourlyRemainingPercentage: 42.0,
            accountID: "uuid-a",
            capturedAt: Date().addingTimeInterval(-60)
        )
        store.record(recent)

        let restored = try XCTUnwrap(store.snapshot(provider: .claudeCode, accountID: "uuid-a"))
        XCTAssertEqual(restored.hourlyRemainingPercentage, 42.0)

        // A late-arriving older reading must not overwrite a newer one.
        store.record(
            UsageSnapshot(
                provider: .claudeCode,
                hourlyRemainingPercentage: 99.0,
                accountID: "uuid-a",
                capturedAt: Date().addingTimeInterval(-7200)
            )
        )
        let afterStaleWrite = try XCTUnwrap(store.snapshot(provider: .claudeCode, accountID: "uuid-a"))
        XCTAssertEqual(afterStaleWrite.hourlyRemainingPercentage, 42.0)

        // A snapshot with no account has nowhere to be filed.
        store.record(UsageSnapshot(provider: .cursor, hourlyRemainingPercentage: 10.0))
        XCTAssertNil(store.snapshot(provider: .cursor, accountID: ""))
    }

    /// An estimate may be shown live with a `.simulated` badge, but stored it
    /// would later resurface as a dated reading with nothing marking it as a
    /// guess.
    func testUsageStoreRefusesSimulatedReadings() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("account-usage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = AccountUsageStore(fileURL: url)
        store.record(
            UsageSnapshot(
                provider: .openAICodex,
                hourlyRemainingPercentage: 79.0,
                strategyUsed: .simulated,
                accountID: "uuid-b"
            )
        )
        XCTAssertNil(store.snapshot(provider: .openAICodex, accountID: "uuid-b"))
    }

    // MARK: - Profile directory matching

    /// `~/.codexbar` is an unrelated app. Treating it as a Codex profile would
    /// hunt for credentials inside it and attribute its file writes to Codex.
    func testProfileDirectoriesRequireASeparatorAfterThePrefix() throws {
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("profiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        for name in [".codex", ".codex-work", ".codex_alt", ".codexbar", ".codexical"] {
            try FileManager.default.createDirectory(
                at: sandbox.appendingPathComponent(name),
                withIntermediateDirectories: true
            )
        }
        // A file, not a directory: must never be offered as a profile home.
        try Data().write(to: sandbox.appendingPathComponent(".codex.json"))

        let matched = AccountFileReader.profileDirectories(in: sandbox.path, prefix: ".codex")
            .map { ($0 as NSString).lastPathComponent }
            .sorted()

        XCTAssertEqual(matched, [".codex", ".codex-work", ".codex_alt"])
    }

    // MARK: - Multi-profile fetch against real files

    /// The point of the whole account model: two Claude profiles are two
    /// accounts with two separate quotas, and both are readable from disk in one
    /// pass — no process launch, no network, no picking a winner.
    func testEveryClaudeProfileYieldsItsOwnAccountSnapshot() async throws {
        let alternate = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-profile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: alternate, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: alternate) }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let sessionReset = formatter.string(from: Date().addingTimeInterval(3600))
        let weeklyReset = formatter.string(from: Date().addingTimeInterval(86400 * 3))

        let secondAccount: [String: Any] = [
            "oauthAccount": [
                "accountUuid": "ffffffff-1111-2222-3333-444444444444",
                "emailAddress": "second.account@example.com",
                "organizationType": "claude_max"
            ],
            "cachedUsageUtilization": [
                "fetchedAtMs": Date().timeIntervalSince1970 * 1000.0,
                "accountUuid": "ffffffff-1111-2222-3333-444444444444",
                "utilization": [
                    "five_hour": ["utilization": 25, "resets_at": sessionReset],
                    "seven_day": ["utilization": 40, "resets_at": weeklyReset],
                    "limits": [
                        [
                            "kind": "session", "group": "session", "percent": 25,
                            "severity": "normal", "resets_at": sessionReset, "is_active": true
                        ]
                    ]
                ]
            ]
        ]
        try JSONSerialization
            .data(withJSONObject: secondAccount)
            .write(to: alternate.appendingPathComponent(".claude.json"))

        setenv("CLAUDE_CONFIG_DIR", alternate.path, 1)
        defer { unsetenv("CLAUDE_CONFIG_DIR") }

        let snapshots = try await ClaudeCodeAdapter().fetchUsagePerAccount(forceSync: false)

        let second = try XCTUnwrap(
            snapshots.first { $0.accountID == "ffffffff-1111-2222-3333-444444444444" },
            "the alternate profile's own account must be reported"
        )
        XCTAssertEqual(second.hourlyRemainingPercentage, 75.0, accuracy: 0.001)
        XCTAssertEqual(second.weeklyRemainingPercentage ?? -1, 60.0, accuracy: 0.001)
        XCTAssertEqual(second.planName, "Claude Max")
        XCTAssertEqual(second.accountEmail, "second.account@example.com")

        // Each snapshot speaks for exactly one account.
        let ids = snapshots.compactMap(\.accountID)
        XCTAssertEqual(ids.count, snapshots.count)
        XCTAssertEqual(Set(ids).count, ids.count, "two profiles must not collapse into one account")

        // And the resolver agrees with the adapter about who exists.
        let discovered = await ClaudeAccountResolver().resolveAccounts()
        XCTAssertTrue(
            discovered.contains { $0.id == "ffffffff-1111-2222-3333-444444444444" && $0.usageReadable },
            "a profile with its own usage cache must be reported as readable"
        )
    }

    // MARK: - Live discovery on this machine

    /// Not an assertion about which accounts exist — machines differ — but a
    /// guarantee that scanning a real home directory neither crashes nor invents
    /// an account, and a readable report of what it found.
    @MainActor
    func testLiveDiscoveryIsSafeAndSelfConsistent() async {
        let registry = AccountRegistry()
        await registry.refreshAccounts()

        for provider in AIProviderType.allCases {
            let accounts = registry.accounts(for: provider)
            guard !accounts.isEmpty else { continue }

            XCTAssertEqual(
                Set(accounts.map(\.id)).count,
                accounts.count,
                "\(provider.rawValue) reported the same account id twice"
            )
            for account in accounts {
                XCTAssertFalse(account.sources.isEmpty, "every account must name where it came from")
                XCTAssertFalse(account.id.isEmpty)
            }

            print("[discovery] \(provider.rawValue): " + accounts
                .map { "\($0.maskedLabel) [\($0.sourceBadgeText)]\($0.usageReadable ? " *readable*" : "")" }
                .joined(separator: " | "))
        }
    }

    // MARK: - Claude CLI probe parsing

    /// Verbatim `claude -p "/usage"` output.
    private static let claudeUsageReport = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 17% used · resets Sep 2 at 11:19pm (Asia/Seoul)
    Current week (all models): 11% used · resets Sep 8 at 1:59pm (Asia/Seoul)

    What's contributing to your limits usage?
    Approximate, based on local sessions on this machine.

    Last 24h · 318 requests · 4 sessions
      78% of your usage was at >150k context
    """

    func testCLIUsageReportIsParsedIntoRemainingPercentages() throws {
        // Pinned before the fixture's own reset times. Left to the wall clock
        // this passed until 11:19pm on a September 2nd and then began failing,
        // because an elapsed reset correctly stops being a countdown.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 9))
        )
        let snapshot = try XCTUnwrap(
            ClaudeCodeAdapter().parseClaudeUsageOutput(Self.claudeUsageReport, now: now)
        )

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 83.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.weeklyRemainingPercentage ?? -1, 89.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.strategyUsed, .cliStatusProbe)
        // The report carries real reset times; inventing round ones discards them.
        XCTAssertNotNil(snapshot.hourlyResetCountdown)
        XCTAssertNotNil(snapshot.weeklyResetCountdown)
        XCTAssertEqual(snapshot.modelQuotas.count, 2)
    }

    /// Output that carries no percentage used to become a snapshot reporting 90%
    /// remaining, which reached the bar looking exactly like a measurement.
    func testCLIOutputWithoutUsageIsRejected() {
        let adapter = ClaudeCodeAdapter()
        XCTAssertNil(adapter.parseClaudeUsageOutput("Invalid API key · Please run /login"))
        XCTAssertNil(adapter.parseClaudeUsageOutput(""))
        // A probe killed mid-write leaves a prefix of the real report behind.
        XCTAssertNil(adapter.parseClaudeUsageOutput("You are currently using your subscription to po"))
    }

    /// `resets Sep 2 at 11:19pm (Asia/Seoul)` names a zone and omits the year.
    func testResetPhraseResolvesAgainstItsNamedZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 2
        components.hour = 20
        let now = try XCTUnwrap(calendar.date(from: components))

        let countdown = try XCTUnwrap(
            ClaudeCodeAdapter.resetCountdown(
                fromPhrase: " · resets Sep 2 at 11:19pm (Asia/Seoul)",
                now: now
            )
        )
        XCTAssertEqual(countdown, 3 * 3600 + 19 * 60, accuracy: 1.0)
    }

    /// December reports a January reset, and the year is not in the phrase.
    func testResetPhraseRollsOverIntoTheNextYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        var components = DateComponents()
        components.year = 2026
        components.month = 12
        components.day = 31
        components.hour = 23
        let now = try XCTUnwrap(calendar.date(from: components))

        let countdown = try XCTUnwrap(
            ClaudeCodeAdapter.resetCountdown(
                fromPhrase: "resets Jan 1 at 2:00am (Asia/Seoul)",
                now: now
            )
        )
        XCTAssertEqual(countdown, 3 * 3600, accuracy: 1.0)
    }

    // MARK: - Desktop account directories

    /// The desktop app files its state as `<accountUuid>/<organizationUuid>/`,
    /// so only UUID-shaped directory names at the first level are accounts. The
    /// shape check is what keeps a stray sibling out of the account list.
    func testUUIDDirectoryNamesRejectAnythingElse() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("desktop-\(UUID().uuidString)")
        let manager = FileManager.default
        defer { try? manager.removeItem(at: root) }

        let accountA = "c391e248-6ab3-4b57-b740-edbeeee2188d"
        let accountB = "86802002-9ee3-45ba-9c96-64475fa7c0c6"
        for name in [accountA, accountB, "shared", "not-a-uuid"] {
            try manager.createDirectory(
                at: root.appendingPathComponent(name),
                withIntermediateDirectories: true
            )
        }
        // A UUID-named *file* is not an account directory.
        try Data().write(to: root.appendingPathComponent(UUID().uuidString))

        XCTAssertEqual(
            AccountFileReader.uuidDirectoryNames(in: root.path),
            [accountB, accountA].sorted()
        )
    }

    func testUUIDDirectoryNamesOnMissingPathIsEmpty() {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("absent-\(UUID().uuidString)")
        XCTAssertTrue(AccountFileReader.uuidDirectoryNames(in: missing.path).isEmpty)
    }

    // MARK: - Antigravity CLI identity

    /// The CLI holds its own opaque token, so the only place on disk that says
    /// which account it authenticated as is its own log.
    func testAntigravityLogNamesTheAuthenticatedAccount() throws {
        let log = """
        ERROR: logging before google.Init: I0902 22:46:35.047200 1 server_oauth.go:192] \
        applyAuthResult: email=someone@example.com, authMethod=consumer, quotaProject=
        ERROR: logging before google.Init: I0902 22:46:40.191571 1 printmode.go:286] Print mode: /usage
        """
        XCTAssertEqual(
            GeminiAccountResolver.authenticatedEmail(inLog: log),
            "someone@example.com"
        )
    }

    func testAntigravityLogWithoutAnAuthResultYieldsNothing() {
        XCTAssertNil(
            GeminiAccountResolver.authenticatedEmail(inLog: "Print mode: running slash command /usage")
        )
    }

    /// A log line is not a contract; a malformed one must not become an address.
    func testAntigravityLogRejectsAValueThatIsNotAnAddress() {
        XCTAssertNil(
            GeminiAccountResolver.authenticatedEmail(inLog: "applyAuthResult: email=, authMethod=consumer")
        )
    }

    func testAntigravityCLIEmailReadsTheNewestLogFirst() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agy-log-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Names sort chronologically as text, which is what the lookback relies on.
        try "applyAuthResult: email=old@example.com, authMethod=consumer"
            .write(to: root.appendingPathComponent("cli-20260901_120000.log"), atomically: true, encoding: .utf8)
        try "applyAuthResult: email=current@example.com, authMethod=consumer"
            .write(to: root.appendingPathComponent("cli-20260902_224634.log"), atomically: true, encoding: .utf8)
        // A run that never reached authentication answers nothing, and the
        // lookback must fall through it rather than stopping there.
        try "starting up"
            .write(to: root.appendingPathComponent("cli-20260902_230000.log"), atomically: true, encoding: .utf8)

        XCTAssertEqual(
            GeminiAccountResolver.antigravityCLIEmail(logDirectory: root.path),
            "current@example.com"
        )
    }

    // MARK: - Freshness

    /// The adapter must not sit on a reading the display has already labelled
    /// stale: one threshold, or the app shows a stale figure and refreshes
    /// nothing.
    func testStalenessThresholdIsTheOneUsedToDecideRefresh() {
        let borderline = UsageSnapshot(
            provider: .claudeCode,
            hourlyRemainingPercentage: 50.0,
            capturedAt: Date().addingTimeInterval(-UsageSnapshot.stalenessThreshold - 60)
        )
        XCTAssertTrue(borderline.isStale)
        XCTAssertEqual(ClaudeCodeAdapter.cacheFreshnessWindow, UsageSnapshot.stalenessThreshold)
    }

    /// A reset already behind us is not a countdown.
    func testElapsedResetPhraseIsNil() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 3
        components.hour = 22
        let now = try XCTUnwrap(calendar.date(from: components))

        XCTAssertNil(
            ClaudeCodeAdapter.resetCountdown(
                fromPhrase: "resets Sep 2 at 11:19pm (Asia/Seoul)",
                now: now
            )
        )
    }
}
