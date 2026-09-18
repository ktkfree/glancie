import XCTest
@testable import Glancie

/// What `agy -p "/usage"` output turns into.
///
/// Which pools agy prints depends on the plan and on what the account has
/// actually spent, so a partial answer is the normal case rather than the
/// exception. The old assembly filled the gaps with 100%, invented reset
/// windows for pools it had never seen, and attached a usage pace derived from
/// no time series at all.
final class AntigravityQuotaTests: XCTestCase {

    private let adapter = AntigravityAdapter()

    private func line(_ group: String, _ limit: String, _ percent: String, reset: String? = nil) -> String {
        ([group, limit, percent] + (reset.map { [$0] } ?? [])).joined(separator: "\t")
    }

    // MARK: - Missing pools stay missing

    func testPartialAgyMustNotInventGeminiQuota() {
        // Verbatim from the audit. A Claude/GPT session at 0% used to be
        // displayed as a full Gemini bar with a four-hour reset attached.
        let snapshot = adapter.parseAgyUsageOutput(
            line("Claude and GPT models", "Five Hour Limit Remaining", "0%")
        )

        let unwrapped = try? XCTUnwrap(snapshot)
        XCTAssertNotNil(unwrapped)
        XCTAssertEqual(unwrapped?.hourlyRemainingPercentage, 0)
        XCTAssertEqual(unwrapped?.hourlyQuotaName, "Claude/GPT 5-hour", "the bar names the pool it is showing")
        XCTAssertNil(unwrapped?.weeklyRemainingPercentage, "no weekly pool was reported")
        XCTAssertNil(unwrapped?.hourlyResetCountdown, "no reset time was reported")
        XCTAssertNil(unwrapped?.weeklyResetCountdown)
        XCTAssertEqual(unwrapped?.modelQuotas.count, 1, "one pool observed, one row")
    }

    func testAgyClaudeWeeklyOnlyIsReadable() throws {
        // The old guard demanded a Gemini figure or a Claude session figure, so
        // a valid weekly-only answer was thrown away entirely.
        let snapshot = try XCTUnwrap(
            adapter.parseAgyUsageOutput(line("Claude and GPT models", "Weekly Limit Remaining", "20%"))
        )

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 20)
        XCTAssertEqual(snapshot.hourlyQuotaName, "Claude/GPT weekly")
        XCTAssertNil(snapshot.weeklyRemainingPercentage, "the weekly pool is not also shown twice")
    }

    func testGeminiWeeklyOnlyIsReadable() throws {
        let snapshot = try XCTUnwrap(
            adapter.parseAgyUsageOutput(line("Gemini Models", "Weekly Limit Remaining", "72%"))
        )

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 72)
        XCTAssertEqual(snapshot.hourlyQuotaName, "Gemini weekly")
    }

    func testAMissingWeeklyPoolIsNotFilledInAt100() throws {
        let snapshot = try XCTUnwrap(
            adapter.parseAgyUsageOutput(line("Gemini Models", "Five Hour Limit Remaining", "40%"))
        )

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 40)
        XCTAssertNil(snapshot.weeklyRemainingPercentage)
    }

    func testNoRecognisablePoolReadsAsNothing() {
        XCTAssertNil(adapter.parseAgyUsageOutput(""))
        XCTAssertNil(adapter.parseAgyUsageOutput("Some unrelated CLI banner\nUsage: agy [options]"))
        XCTAssertNil(adapter.parseAgyUsageOutput(line("Unknown Models", "Weekly Limit Remaining", "50%")))
    }

    // MARK: - The full answer

    func testAFullAnswerKeepsEveryPoolAndLeadsWithTheSession() throws {
        let output = [
            line("Gemini Models", "Weekly Limit Remaining", "72%", reset: "2126-09-03T13:36:55Z"),
            line("Gemini Models", "Five Hour Limit Remaining", "98%", reset: "2126-08-30T14:30:07Z"),
            line("Claude and GPT models", "Weekly Limit Remaining", "33%"),
            line("Claude and GPT models", "Five Hour Limit Remaining", "0%")
        ].joined(separator: "\n")

        let snapshot = try XCTUnwrap(adapter.parseAgyUsageOutput(output))

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 98, "Gemini's session pool leads")
        XCTAssertEqual(snapshot.hourlyQuotaName, "Gemini 5-hour")
        XCTAssertEqual(snapshot.weeklyRemainingPercentage, 72)
        XCTAssertEqual(snapshot.modelQuotas.count, 4, "every observed pool gets a row")
        XCTAssertEqual(
            snapshot.modelQuotas.map(\.name),
            ["Gemini 5-hour", "Claude/GPT 5-hour", "Gemini weekly", "Claude/GPT weekly"]
        )
    }

    func testAReportedResetTimeIsUsedAsGiven() throws {
        let snapshot = try XCTUnwrap(
            adapter.parseAgyUsageOutput(
                line("Gemini Models", "Five Hour Limit Remaining", "50%", reset: "2126-08-30T14:30:07Z")
            )
        )

        let countdown = try XCTUnwrap(snapshot.hourlyResetCountdown)
        XCTAssertGreaterThan(countdown, 0)
        XCTAssertNotEqual(countdown, 14400, "not the old four-hour default")
    }

    func testAnExhaustedPoolStaysAtZero() throws {
        let snapshot = try XCTUnwrap(
            adapter.parseAgyUsageOutput(line("Gemini Models", "Five Hour Limit Remaining", "0%"))
        )

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 0)
        XCTAssertFalse(snapshot.isSimulated, "0% is a measurement, not an absence")
    }

    // MARK: - Nothing invented alongside the figures

    func testNoPaceOrForecastIsAttachedWithoutATimeSeries() throws {
        // "4.1 세션 할당량 남음", "1d 2h 후 소진" and the 57/68% pace markers were
        // all derived from the single percentage in front of them.
        let output = [
            line("Gemini Models", "Weekly Limit Remaining", "72%"),
            line("Gemini Models", "Five Hour Limit Remaining", "98%"),
            line("Claude and GPT models", "Weekly Limit Remaining", "33%"),
            line("Claude and GPT models", "Five Hour Limit Remaining", "12%")
        ].joined(separator: "\n")

        let snapshot = try XCTUnwrap(adapter.parseAgyUsageOutput(output))

        for quota in snapshot.modelQuotas {
            XCTAssertNil(quota.paceText, "\(quota.name) carries a forecast nothing measured")
            XCTAssertNil(quota.paceMarkerPercentage, "\(quota.name) carries an invented marker")
        }
    }

    func testNoTokenCountsAreInvented() throws {
        // agy reports percentages. The 12,000 / 200,000 tokens came from nowhere.
        let snapshot = try XCTUnwrap(
            adapter.parseAgyUsageOutput(line("Gemini Models", "Five Hour Limit Remaining", "98%"))
        )

        XCTAssertEqual(snapshot.usedTokens, 0)
    }

    // MARK: - Parsing shapes

    func testSpaceSeparatedOutputParsesToo() throws {
        let snapshot = try XCTUnwrap(
            adapter.parseAgyUsageOutput("Gemini Models   Five Hour Limit Remaining   65%")
        )

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 65)
    }

    func testAPercentageWithADecimalIsKept() throws {
        let snapshot = try XCTUnwrap(
            adapter.parseAgyUsageOutput(line("Gemini Models", "Five Hour Limit Remaining", "12.5%"))
        )

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 12.5, accuracy: 0.001)
    }

    func testTheProbeIsReportedAsACLIProbe() throws {
        let snapshot = try XCTUnwrap(
            adapter.parseAgyUsageOutput(line("Gemini Models", "Five Hour Limit Remaining", "65%"))
        )

        XCTAssertEqual(snapshot.strategyUsed, FetchStrategy.cliStatusProbe)
        XCTAssertNil(snapshot.unavailableReason)
    }
}
