import XCTest
@testable import Glancie

/// When ElevenLabs' character allowance actually refills.
///
/// The adapter read `next_invoice.next_payment_timestamp` — a key the
/// documented response does not carry — and fell back to a flat fifteen days
/// when it came back nil, which it always did. Every subscription therefore
/// showed the same invented countdown, and it was measuring the wrong thing
/// anyway: an invoice is when the account is charged.
final class ElevenLabsResetTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    private func adapter(_ body: String) throws -> ElevenLabsAdapter {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glancie-11l-\(UUID().uuidString)")
        let key = root.appendingPathComponent(".config/elevenlabs/api_key")
        try FileManager.default.createDirectory(
            at: key.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("xi-test".utf8).write(to: key)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        return ElevenLabsAdapter(homeDirectory: root.path, transport: StubTransport.ok(body))
    }

    // MARK: - The field that describes the quota

    func testTheCharacterResetFieldIsTheOneRead() {
        let json: [String: Any] = ["next_character_count_reset_unix": now.timeIntervalSince1970 + 3600]

        XCTAssertEqual(
            try XCTUnwrap(ElevenLabsAdapter.characterResetCountdown(json, now: now)),
            3600,
            accuracy: 0.001
        )
    }

    func testTheBillingDateIsNotUsedAsTheUsageReset() {
        // Both spellings of the invoice field, neither of which describes when
        // the character counter rolls over.
        let json: [String: Any] = [
            "next_invoice": [
                "next_payment_timestamp": now.timeIntervalSince1970 + 86_400 * 20,
                "next_payment_attempt_unix": now.timeIntervalSince1970 + 86_400 * 20
            ]
        ]

        XCTAssertNil(ElevenLabsAdapter.characterResetCountdown(json, now: now))
    }

    func testAMissingResetFieldProducesNoCountdownAtAll() {
        // Not fifteen days. Not any number.
        XCTAssertNil(ElevenLabsAdapter.characterResetCountdown([:], now: now))
        XCTAssertNil(
            ElevenLabsAdapter.characterResetCountdown(
                ["next_character_count_reset_unix": NSNull()], now: now
            )
        )
    }

    func testAResetAlreadyInThePastIsNotACountdown() {
        let json: [String: Any] = ["next_character_count_reset_unix": now.timeIntervalSince1970 - 60]

        XCTAssertNil(ElevenLabsAdapter.characterResetCountdown(json, now: now))
    }

    func testAnIntegerTimestampParsesAsWellAsADouble() {
        let json: [String: Any] = ["next_character_count_reset_unix": Int(now.timeIntervalSince1970) + 120]

        XCTAssertEqual(
            try XCTUnwrap(ElevenLabsAdapter.characterResetCountdown(json, now: now)),
            120,
            accuracy: 1.0
        )
    }

    // MARK: - End to end

    func testTheReportedResetReachesTheSnapshot() async throws {
        let resetAt = Date().timeIntervalSince1970 + 3600
        let body = """
        {"tier": "creator", "character_count": 1000, "character_limit": 10000,
         "next_character_count_reset_unix": \(resetAt),
         "next_invoice": {"next_payment_attempt_unix": \(Date().timeIntervalSince1970 + 86400 * 20)}}
        """
        let snapshot = try await adapter(body).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 90)
        let countdown = try XCTUnwrap(snapshot.hourlyResetCountdown)
        XCTAssertEqual(countdown, 3600, accuracy: 30)
        XCTAssertNotEqual(countdown, 86400 * 15, "the fifteen-day default is gone")
    }

    func testASubscriptionWithoutAResetFieldShowsUsageAndNoCountdown() async throws {
        let body = #"{"tier": "free", "character_count": 5000, "character_limit": 10000}"#
        let snapshot = try await adapter(body).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 50, "the usage figure is still real")
        XCTAssertNil(snapshot.hourlyResetCountdown)
        XCTAssertNil(snapshot.weeklyResetCountdown)
        for quota in snapshot.modelQuotas {
            XCTAssertNil(quota.resetCountdown, "\(quota.name) invented a reset")
        }
    }

    func testTwoAccountsWithDifferentResetsDoNotShowTheSameCountdown() async throws {
        // The tell for the old behaviour: the countdown never varied.
        let base = Date().timeIntervalSince1970
        var countdowns: [TimeInterval] = []
        for offset in [3600.0, 86_400.0] {
            let body = """
            {"tier": "creator", "character_count": 0, "character_limit": 10000,
             "next_character_count_reset_unix": \(base + offset)}
            """
            let snapshot = try await adapter(body).fetchUsage(forceSync: true)
            countdowns.append(try XCTUnwrap(snapshot.hourlyResetCountdown))
        }

        XCTAssertEqual(countdowns.count, 2)
        XCTAssertNotEqual(countdowns[0], countdowns[1])
    }

    func testAZeroCharacterLimitIsNotADenominator() async throws {
        let body = #"{"tier": "free", "character_count": 0, "character_limit": 0}"#
        let snapshot = try await adapter(body).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.unavailableReason, .malformedResponse)
    }

    func testAnExhaustedAllowanceReadsAsZeroRatherThanUnknown() async throws {
        let body = #"{"tier": "free", "character_count": 10000, "character_limit": 10000}"#
        let snapshot = try await adapter(body).fetchUsage(forceSync: true)

        XCTAssertNil(snapshot.unavailableReason)
        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 0)
    }
}
