import XCTest
@testable import Glancie

/// Covers reading Codex's quota out of a session rollout. The fixtures mirror
/// the real `token_count` payload, including the all-null block a session writes
/// before the API has reported any limit and the epoch-seconds `resets_at`.
final class CodexUsageTests: XCTestCase {

    /// The wording asserted below is the Korean wording. Pin it, so the suite
    /// passes on an English Mac and never reads the tester's own preference.
    override func setUp() {
        super.setUp()
        Localization.renderLanguage(.korean)
    }


    private func event(
        timestamp: String = "2026-08-31T07:33:29.922Z",
        rateLimits: [String: Any]
    ) -> [String: Any] {
        [
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": NSNull(),
                "rate_limits": rateLimits
            ]
        ]
    }

    private var populatedLimits: [String: Any] {
        [
            "limit_id": "codex",
            "limit_name": NSNull(),
            "primary": [
                "used_percent": 99.0,
                "window_minutes": 43200,
                "resets_at": 1789004232
            ],
            "secondary": NSNull(),
            "credits": ["has_credits": false, "unlimited": false, "balance": NSNull()],
            "individual_limit": NSNull(),
            "spend_control_reached": NSNull(),
            "plan_type": "free",
            "rate_limit_reached_type": NSNull()
        ]
    }

    // MARK: - Decoding

    /// The payload reports percentage *used*; everything downstream is remaining.
    func testUsedPercentIsInvertedAndWindowRetained() throws {
        let limits = try XCTUnwrap(
            OpenAI_CodexAdapter.rateLimits(fromEvent: event(rateLimits: populatedLimits))
        )

        XCTAssertEqual(limits.primary?.remaining, 1.0)
        XCTAssertEqual(limits.primary?.windowMinutes, 43200)
        XCTAssertEqual(limits.primary?.resetsAt, Date(timeIntervalSince1970: 1789004232))
        XCTAssertNil(limits.secondary)
        XCTAssertEqual(limits.planType, "free")
        // The reading is as old as the turn that produced it, not as old as the
        // read — a stale figure has to be able to admit it.
        XCTAssertEqual(
            limits.capturedAt.timeIntervalSince1970,
            1788161609.922,
            accuracy: 0.01
        )
    }

    /// A session that has not yet reached the API writes a block of nulls.
    /// Reading that as full quota would invent the measurement.
    func testAllNullBlockIsNotAReading() {
        let empty: [String: Any] = [
            "limit_id": "premium",
            "primary": NSNull(),
            "secondary": NSNull(),
            "credits": ["has_credits": false, "unlimited": false, "balance": NSNull()],
            "plan_type": NSNull()
        ]
        XCTAssertNil(OpenAI_CodexAdapter.rateLimits(fromEvent: event(rateLimits: empty)))
    }

    /// Older builds wrote the payload at the top level of the line.
    func testPayloadAtTopLevelIsAccepted() throws {
        let flat: [String: Any] = [
            "timestamp": "2026-08-31T07:33:29.922Z",
            "type": "token_count",
            "rate_limits": populatedLimits
        ]
        let limits = try XCTUnwrap(OpenAI_CodexAdapter.rateLimits(fromEvent: flat))
        XCTAssertEqual(limits.primary?.remaining, 1.0)
    }

    func testRelativeResetIsResolvedAgainstNow() throws {
        var raw = populatedLimits
        raw["primary"] = [
            "used_percent": 40.0,
            "window_minutes": 300,
            "resets_in_seconds": 1800
        ]
        let limits = try XCTUnwrap(OpenAI_CodexAdapter.rateLimits(fromEvent: event(rateLimits: raw)))
        let countdown = try XCTUnwrap(limits.primary?.countdown())
        XCTAssertEqual(countdown, 1800, accuracy: 5)
    }

    /// Credits are an amount rather than a proportion, but an unmetered account
    /// still has to be distinguishable from one nothing is known about.
    func testUnlimitedCreditsAloneCountAsAReading() throws {
        let raw: [String: Any] = [
            "primary": NSNull(),
            "secondary": NSNull(),
            "credits": ["has_credits": true, "unlimited": true, "balance": NSNull()]
        ]
        let limits = try XCTUnwrap(OpenAI_CodexAdapter.rateLimits(fromEvent: event(rateLimits: raw)))
        XCTAssertTrue(limits.hasUnlimitedCredits)

        let snapshot = OpenAI_CodexAdapter.snapshot(from: limits, account: nil)
        XCTAssertEqual(snapshot.modelQuotas.map(\.paceText), ["무제한"])
    }

    // MARK: - Snapshot assembly

    func testSnapshotReportsRemainingAndCountdown() throws {
        let limits = try XCTUnwrap(
            OpenAI_CodexAdapter.rateLimits(fromEvent: event(rateLimits: populatedLimits))
        )
        let now = Date(timeIntervalSince1970: 1789004232 - 3600)
        let snapshot = OpenAI_CodexAdapter.snapshot(
            from: limits,
            account: (accountID: "acct", email: "someone@example.com", planName: "ChatGPT Plus"),
            now: now
        )

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 1.0)
        XCTAssertEqual(try XCTUnwrap(snapshot.hourlyResetCountdown), 3600, accuracy: 1)
        XCTAssertNil(snapshot.weeklyRemainingPercentage)
        XCTAssertEqual(snapshot.accountID, "acct")
        XCTAssertEqual(snapshot.sourceID, "codex.cli")
        // Figures read from disk are a measurement and must say so.
        XCTAssertEqual(snapshot.strategyUsed, .localFileCache)
        // The rollout knows which plan the request was billed against; the token
        // was issued weeks earlier and may disagree.
        XCTAssertEqual(snapshot.planName, "ChatGPT Free")
    }

    /// Codex meters the free tier over 30 days and paid tiers over hours, so the
    /// window label is derived from `window_minutes` rather than assumed.
    func testWindowLabelsFollowTheDeclaredWindow() {
        XCTAssertEqual(OpenAI_CodexAdapter.windowLabel(minutes: 43200), "30일 한도")
        XCTAssertEqual(OpenAI_CodexAdapter.windowLabel(minutes: 10080), "1주 한도")
        XCTAssertEqual(OpenAI_CodexAdapter.windowLabel(minutes: 300), "5시간 한도")
        XCTAssertEqual(OpenAI_CodexAdapter.windowLabel(minutes: 45), "45분 한도")
    }

    // MARK: - Rollout scanning

    /// The newest rollout is not always the newest reading: a session can end
    /// without ever having been told a limit.
    func testScanWalksBackPastRolloutsWithoutAReading() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-\(UUID().uuidString)")
        let sessions = root.appendingPathComponent("sessions/2026/09/02")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func write(_ name: String, _ events: [[String: Any]], modified: Date) throws {
            let lines = try events.map { event -> String in
                let data = try JSONSerialization.data(withJSONObject: event)
                return String(decoding: data, as: UTF8.self)
            }
            let url = sessions.appendingPathComponent(name)
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: modified],
                ofItemAtPath: url.path
            )
        }

        let empty: [String: Any] = ["primary": NSNull(), "secondary": NSNull()]
        try write(
            "rollout-2026-09-02T22-22-30-newer.jsonl",
            [event(rateLimits: empty)],
            modified: Date()
        )
        try write(
            "rollout-2026-08-31T16-33-21-older.jsonl",
            [event(rateLimits: populatedLimits)],
            modified: Date().addingTimeInterval(-86400)
        )

        XCTAssertEqual(
            OpenAI_CodexAdapter.rolloutFiles(codexHome: root.path).first?.lastPathComponent,
            "rollout-2026-09-02T22-22-30-newer.jsonl"
        )
        let limits = try XCTUnwrap(OpenAI_CodexAdapter.rateLimits(codexHome: root.path))
        XCTAssertEqual(limits.primary?.remaining, 1.0)
        XCTAssertTrue(OpenAI_CodexAdapter.hasReadableUsage(codexHome: root.path))
    }

    /// A `CODEX_HOME` with no rollouts is a known account whose usage nothing
    /// has measured — not an account at full quota.
    func testHomeWithoutRolloutsHasNoReadableUsage() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex-empty-\(UUID().uuidString)")
        XCTAssertFalse(OpenAI_CodexAdapter.hasReadableUsage(codexHome: root.path))
    }
}
