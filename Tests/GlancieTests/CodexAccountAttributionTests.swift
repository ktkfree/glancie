import XCTest
@testable import Glancie

/// Whose usage a Codex rollout is allowed to describe.
///
/// A rollout records the quota the API reported and nothing about whose quota it
/// was, so pairing the newest rollout with whoever `auth.json` names today is an
/// assumption rather than an observation. Leave account A's rollouts in place,
/// sign in as B, refresh — and B's id used to arrive stapled to A's spending,
/// without B having made a single request.
final class CodexAccountAttributionTests: XCTestCase {

    // MARK: - Fixtures

    private func makeLedger() throws -> AccountIdentityLedger {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("glancie-identity-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        return AccountIdentityLedger(fileURL: file)
    }

    private func makeCodexHome() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-attr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    /// An `auth.json` whose `id_token` carries these claims. Unsigned: nothing
    /// in the app verifies the signature, it only reads the payload.
    private func writeAuth(
        in home: URL,
        accountID: String,
        email: String,
        modified: Date? = nil
    ) throws -> CodexAccountResolver.Profile {
        let claims: [String: Any] = [
            "email": email,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": accountID,
                "chatgpt_plan_type": "plus"
            ]
        ]
        let payload = try JSONSerialization.data(withJSONObject: claims)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "header.\(payload).signature"

        let auth: [String: Any] = ["auth_mode": "chatgpt", "tokens": ["id_token": token, "account_id": accountID]]
        let path = home.appendingPathComponent("auth.json")
        try JSONSerialization.data(withJSONObject: auth).write(to: path)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: path.path)
        }

        return CodexAccountResolver.Profile(
            authPath: path.path,
            homeDirectory: home.path,
            isDefault: true
        )
    }

    /// `startedAt` defaults to the moment the reading was written: the ordinary
    /// case, where a session records its rate limit during the same sign-in it
    /// began under. The tests that care about a session outliving a login switch
    /// pass an earlier one.
    private func writeRollout(
        in home: URL,
        day: String,
        name: String,
        timestamp: String,
        usedPercent: Double,
        modified: Date,
        startedAt: String? = nil,
        instructionsBytes: Int = 0
    ) throws {
        let url = home.appendingPathComponent("sessions/\(day)/\(name)")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Codex writes the session's whole `base_instructions` into
        // `session_meta`, which is why the real opening line runs to tens of
        // kilobytes. `instructionsBytes` reproduces that.
        var payload: [String: Any] = ["session_id": UUID().uuidString]
        if instructionsBytes > 0 {
            payload["base_instructions"] = String(repeating: "a", count: instructionsBytes)
        }
        let meta: [String: Any] = [
            "timestamp": startedAt ?? timestamp,
            "type": "session_meta",
            "payload": payload
        ]
        let event: [String: Any] = [
            "timestamp": timestamp,
            "payload": [
                "type": "token_count",
                "rate_limits": ["primary": ["used_percent": usedPercent, "window_minutes": 300]]
            ]
        ]
        let lines = try [meta, event].map {
            String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self)
        }
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    private func reading(capturedAt: Date, startedAt: Date? = nil) -> OpenAI_CodexAdapter.RateLimits {
        OpenAI_CodexAdapter.RateLimits(
            primary: OpenAI_CodexAdapter.RateWindow(remaining: 20, windowMinutes: 300, resetsAt: nil),
            secondary: nil,
            planType: "plus",
            creditBalance: nil,
            hasUnlimitedCredits: false,
            capturedAt: capturedAt,
            sessionStartedAt: startedAt ?? capturedAt
        )
    }

    // MARK: - The ledger's rule

    func testAProfileSeenForTheFirstTimeCarriesNoBoundary() throws {
        // Never having looked is not evidence that the account changed; using
        // the credential's own timestamp instead would discard every reading
        // taken before the CLI last refreshed its token.
        let ledger = try makeLedger()
        XCTAssertNil(
            ledger.attributionBoundary(
                provider: .openAICodex, profile: "/tmp/a", accountID: "acct-A"
            )
        )
    }

    func testSeeingTheSameAccountAgainAddsNoBoundary() throws {
        let ledger = try makeLedger()
        for _ in 0..<3 {
            XCTAssertNil(
                ledger.attributionBoundary(
                    provider: .openAICodex, profile: "/tmp/a", accountID: "acct-A"
                )
            )
        }
    }

    func testASwitchMarksTheMomentAndInvalidatesEarlierReadings() throws {
        let ledger = try makeLedger()
        let switchedAt = Date(timeIntervalSince1970: 2000)

        _ = ledger.attributionBoundary(provider: .openAICodex, profile: "/tmp/a", accountID: "acct-A")
        let boundary = ledger.attributionBoundary(
            provider: .openAICodex, profile: "/tmp/a", accountID: "acct-B", changedAt: switchedAt
        )

        XCTAssertEqual(boundary, switchedAt)
        XCTAssertFalse(
            ledger.isAttributable(
                capturedAt: Date(timeIntervalSince1970: 1999),
                provider: .openAICodex, profile: "/tmp/a", accountID: "acct-B"
            ),
            "A's last turn is not B's usage"
        )
        XCTAssertTrue(
            ledger.isAttributable(
                capturedAt: Date(timeIntervalSince1970: 2001),
                provider: .openAICodex, profile: "/tmp/a", accountID: "acct-B"
            ),
            "a turn B actually ran is B's usage"
        )
    }

    func testSwitchingBackMarksThatSwitchToo() throws {
        // Returning to A must not resurrect A's pre-B figures as current, and
        // must not silently inherit B's either.
        let ledger = try makeLedger()
        _ = ledger.attributionBoundary(provider: .openAICodex, profile: "/tmp/a", accountID: "acct-A")
        _ = ledger.attributionBoundary(
            provider: .openAICodex, profile: "/tmp/a", accountID: "acct-B",
            changedAt: Date(timeIntervalSince1970: 2000)
        )

        let backToA = ledger.attributionBoundary(
            provider: .openAICodex, profile: "/tmp/a", accountID: "acct-A",
            changedAt: Date(timeIntervalSince1970: 3000)
        )

        XCTAssertEqual(backToA, Date(timeIntervalSince1970: 3000))
    }

    func testProfilesAreTrackedSeparately() throws {
        // Two `CODEX_HOME`s are two logins; a switch in one says nothing about
        // the other.
        let ledger = try makeLedger()
        _ = ledger.attributionBoundary(provider: .openAICodex, profile: "/tmp/a", accountID: "acct-A")
        _ = ledger.attributionBoundary(provider: .openAICodex, profile: "/tmp/b", accountID: "acct-B")

        _ = ledger.attributionBoundary(
            provider: .openAICodex, profile: "/tmp/a", accountID: "acct-C",
            changedAt: Date(timeIntervalSince1970: 2000)
        )

        XCTAssertNil(
            ledger.attributionBoundary(provider: .openAICodex, profile: "/tmp/b", accountID: "acct-B"),
            "the untouched profile keeps its clean history"
        )
    }

    func testASwitchWhileTheAppWasClosedIsStillCaught() throws {
        // The ledger is on disk precisely so the evidence survives a relaunch.
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("glancie-identity-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }

        _ = AccountIdentityLedger(fileURL: file)
            .attributionBoundary(provider: .openAICodex, profile: "/tmp/a", accountID: "acct-A")

        let afterRelaunch = AccountIdentityLedger(fileURL: file)
        let boundary = afterRelaunch.attributionBoundary(
            provider: .openAICodex, profile: "/tmp/a", accountID: "acct-B",
            changedAt: Date(timeIntervalSince1970: 2000)
        )

        XCTAssertEqual(boundary, Date(timeIntervalSince1970: 2000))
    }

    func testWithoutACredentialTimestampTheSwitchIsDatedNow() throws {
        let ledger = try makeLedger()
        let now = Date(timeIntervalSince1970: 5000)
        _ = ledger.attributionBoundary(provider: .openAICodex, profile: "/tmp/a", accountID: "acct-A", now: now)

        XCTAssertEqual(
            ledger.attributionBoundary(
                provider: .openAICodex, profile: "/tmp/a", accountID: "acct-B", now: now
            ),
            now
        )
    }

    // MARK: - The adapter's use of it

    func testAnAPIKeyProfileWithNoAccountIDIsAlwaysAttributable() throws {
        // `auth_mode: apikey` carries no id_token, so there is no account to
        // mis-attribute to and nothing to withhold.
        let ledger = try makeLedger()
        let profile = CodexAccountResolver.Profile(
            authPath: "/tmp/none/auth.json", homeDirectory: "/tmp/none", isDefault: true
        )

        XCTAssertTrue(
            OpenAI_CodexAdapter.isAttributable(
                reading(capturedAt: Date(timeIntervalSince1970: 10)),
                to: nil, profile: profile, ledger: ledger
            )
        )
    }

    func testTheAdapterWithholdsThePreviousAccountsRollout() throws {
        // The audit's case, end to end: A's rollout stays on disk, `auth.json`
        // is replaced with B's token, and B has run nothing.
        let home = try makeCodexHome()
        let ledger = try makeLedger()
        let adapter = OpenAI_CodexAdapter(identityLedger: ledger)

        let accountA = try writeAuth(in: home, accountID: "acct-A", email: "a@example.com")
        try writeRollout(
            in: home, day: "2026/09/05", name: "rollout-a.jsonl",
            timestamp: "2026-09-05T10:00:00Z", usedPercent: 80,
            modified: Date(timeIntervalSince1970: 1_788_602_400)
        )

        let asA = adapter.snapshot(for: accountA)
        XCTAssertEqual(asA.hourlyRemainingPercentage, 20, "A's own reading is A's")
        XCTAssertEqual(asA.accountID, "acct-A")

        // Sign out, sign in as B. The rollout is untouched.
        let accountB = try writeAuth(
            in: home, accountID: "acct-B", email: "b@example.com",
            modified: Date(timeIntervalSince1970: 1_788_688_800)
        )

        let asB = adapter.snapshot(for: accountB)
        XCTAssertEqual(asB.accountID, "acct-B")
        XCTAssertTrue(asB.isSimulated, "B has no measurement, so B shows none")
        XCTAssertEqual(asB.hourlyRemainingPercentage, 0)
        XCTAssertEqual(asB.accountEmail, "b@example.com", "who is signed in is still known")
    }

    func testASessionThatOutlivesTheSwitchIsNotRelabelled() throws {
        // A session opened under A keeps appending to the same rollout after the
        // sign-in changes to B. Dated by its last write it looks like B's work;
        // dated by when it opened it is plainly A's, which is what it is.
        let home = try makeCodexHome()
        let ledger = try makeLedger()
        let adapter = OpenAI_CodexAdapter(identityLedger: ledger)

        let accountA = try writeAuth(in: home, accountID: "acct-A", email: "a@example.com")
        try writeRollout(
            in: home, day: "2026/09/05", name: "rollout-long.jsonl",
            timestamp: "2026-09-05T10:00:00Z", usedPercent: 80,
            modified: Date(timeIntervalSince1970: 1_788_602_400),
            startedAt: "2026-09-05T09:00:00Z"
        )
        // The ledger has to have seen A signed in for the switch to be a switch.
        XCTAssertEqual(adapter.snapshot(for: accountA).hourlyRemainingPercentage, 20)

        let accountB = try writeAuth(
            in: home, accountID: "acct-B", email: "b@example.com",
            modified: Date(timeIntervalSince1970: 1_788_688_800)
        )
        // A's session wakes up and writes again, well after the switch.
        try writeRollout(
            in: home, day: "2026/09/07", name: "rollout-long.jsonl",
            timestamp: "2026-09-07T12:00:00Z", usedPercent: 10,
            modified: Date(timeIntervalSince1970: 1_788_782_400),
            startedAt: "2026-09-05T09:00:00Z"
        )

        let asB = adapter.snapshot(for: accountB)
        XCTAssertTrue(asB.isSimulated, "A's session is not B's usage, whenever it wrote")
        XCTAssertEqual(asB.hourlyRemainingPercentage, 0)
    }

    func testARolloutThatDoesNotSayWhenItStartedIsWithheld() throws {
        // Without the opening record there is nothing to date the work by, and
        // a guess here is what relabels one account's usage as another's.
        let ledger = try makeLedger()
        let profile = CodexAccountResolver.Profile(
            authPath: "/tmp/none/auth.json", homeDirectory: "/tmp/none", isDefault: true
        )
        var unprovenanced = reading(capturedAt: Date(timeIntervalSince1970: 10))
        unprovenanced.sessionStartedAt = nil

        XCTAssertFalse(
            OpenAI_CodexAdapter.isAttributable(
                unprovenanced, to: "acct-A", profile: profile, ledger: ledger
            )
        )
        XCTAssertFalse(
            OpenAI_CodexAdapter.isAttributable(
                unprovenanced, to: nil, profile: profile, ledger: ledger
            ),
            "API-key mode does not make unknown provenance knowable"
        )
    }

    func testTheAdapterShowsAReadingTheNewAccountActuallyProduced() throws {
        let home = try makeCodexHome()
        let ledger = try makeLedger()
        let adapter = OpenAI_CodexAdapter(identityLedger: ledger)

        let accountA = try writeAuth(in: home, accountID: "acct-A", email: "a@example.com")
        try writeRollout(
            in: home, day: "2026/09/05", name: "rollout-a.jsonl",
            timestamp: "2026-09-05T10:00:00Z", usedPercent: 80,
            modified: Date(timeIntervalSince1970: 1_788_602_400)
        )
        _ = adapter.snapshot(for: accountA)

        let switchedAt = Date(timeIntervalSince1970: 1_788_688_800)
        let accountB = try writeAuth(
            in: home, accountID: "acct-B", email: "b@example.com", modified: switchedAt
        )
        // B runs a turn of its own, after the switch.
        try writeRollout(
            in: home, day: "2026/09/06", name: "rollout-b.jsonl",
            timestamp: ISO8601DateFormatter().string(from: switchedAt.addingTimeInterval(3600)),
            usedPercent: 30,
            modified: switchedAt.addingTimeInterval(3600)
        )

        let asB = adapter.snapshot(for: accountB)
        XCTAssertFalse(asB.isSimulated)
        XCTAssertEqual(asB.hourlyRemainingPercentage, 70)
        XCTAssertEqual(asB.accountID, "acct-B")
    }

    func testAReusedProfileWithNoSwitchIsUnaffected() throws {
        // The overwhelmingly common case — one account, one profile — must not
        // pay for the guard by losing its reading.
        let home = try makeCodexHome()
        let ledger = try makeLedger()
        let adapter = OpenAI_CodexAdapter(identityLedger: ledger)

        let account = try writeAuth(in: home, accountID: "acct-A", email: "a@example.com")
        try writeRollout(
            in: home, day: "2026/09/06", name: "rollout-a.jsonl",
            timestamp: "2026-09-06T10:00:00Z", usedPercent: 45,
            modified: Date(timeIntervalSince1970: 1_788_688_800)
        )

        for _ in 0..<3 {
            let snapshot = adapter.snapshot(for: account)
            XCTAssertFalse(snapshot.isSimulated, "repeated refreshes keep reading the same account")
            XCTAssertEqual(snapshot.hourlyRemainingPercentage, 55)
        }
    }

    func testALongSessionMetaLineIsStillRead() throws {
        // Codex embeds the full system prompt in `session_meta`, so the opening
        // line is 22KB on 0.153 and 47KB on 0.148 — and grows with the prompt.
        // Reading a fixed-size prefix cut it mid-JSON: the parse failed, the
        // session's start went unknown, and every reading on disk was withheld
        // as unattributable at once.
        let home = try makeCodexHome()
        let ledger = try makeLedger()
        let adapter = OpenAI_CodexAdapter(identityLedger: ledger)

        let account = try writeAuth(in: home, accountID: "acct-A", email: "a@example.com")
        try writeRollout(
            in: home, day: "2026/09/06", name: "rollout-a.jsonl",
            timestamp: "2026-09-06T10:00:00Z", usedPercent: 96,
            modified: Date(timeIntervalSince1970: 1_788_688_800),
            instructionsBytes: 64 * 1024
        )

        let url = home.appendingPathComponent("sessions/2026/09/06/rollout-a.jsonl")
        XCTAssertEqual(
            OpenAI_CodexAdapter.sessionStart(inRolloutAt: url),
            ISO8601DateFormatter().date(from: "2026-09-06T10:00:00Z")
        )

        let snapshot = adapter.snapshot(for: account)
        XCTAssertFalse(snapshot.isSimulated, "a long opening line is not missing provenance")
        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 4)
    }
}
