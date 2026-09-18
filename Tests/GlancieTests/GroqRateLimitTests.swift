import XCTest
@testable import Glancie

/// A transport that answers 200 with a chosen set of headers.
private struct HeaderTransport: UsageTransport {
    let headers: [String: String]

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return (Data("{}".utf8), response)
    }
}

/// What Groq's rate-limit headers actually mean.
///
/// `x-ratelimit-*-requests` is a daily budget and `x-ratelimit-*-tokens` a
/// per-minute one; both were labelled "Per Minute". The `reset` headers were
/// never read at all — a flat 60 seconds stood in for both, which is not even
/// the right order of magnitude for the daily window.
final class GroqRateLimitTests: XCTestCase {

    /// The wording asserted below is the Korean wording. Pin it, so the suite
    /// passes on an English Mac and never reads the tester's own preference.
    override func setUp() {
        super.setUp()
        Localization.renderLanguage(.korean)
    }


    private func adapter(headers: [String: String]) throws -> GroqAdapter {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glancie-groq-\(UUID().uuidString)")
        let key = root.appendingPathComponent(".config/groq/api_key")
        try FileManager.default.createDirectory(
            at: key.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("gsk-test".utf8).write(to: key)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        return GroqAdapter(homeDirectory: root.path, transport: HeaderTransport(headers: headers))
    }

    private var fullHeaders: [String: String] {
        [
            "x-ratelimit-limit-requests": "14400",
            "x-ratelimit-remaining-requests": "0",
            "x-ratelimit-reset-requests": "2m59.56s",
            "x-ratelimit-limit-tokens": "18000",
            "x-ratelimit-remaining-tokens": "9000",
            "x-ratelimit-reset-tokens": "7.66s"
        ]
    }

    // MARK: - Duration parsing

    func testGoStyleDurationsParse() {
        XCTAssertEqual(GroqAdapter.duration("2m59.56s")!, 179.56, accuracy: 0.001)
        XCTAssertEqual(GroqAdapter.duration("7.66s")!, 7.66, accuracy: 0.001)
        XCTAssertEqual(GroqAdapter.duration("1h30m")!, 5400, accuracy: 0.001)
        XCTAssertEqual(GroqAdapter.duration("840ms")!, 0.84, accuracy: 0.0001)
        XCTAssertEqual(GroqAdapter.duration("1h2m3s")!, 3723, accuracy: 0.001)
        XCTAssertEqual(GroqAdapter.duration("30")!, 30, accuracy: 0.001, "a bare number is seconds")
    }

    func testUnparseableDurationsAreNilRatherThanZero() {
        // Zero would read as "resets right now", which is a claim; nil is not.
        XCTAssertNil(GroqAdapter.duration(nil))
        XCTAssertNil(GroqAdapter.duration(""))
        XCTAssertNil(GroqAdapter.duration("soon"))
        XCTAssertNil(GroqAdapter.duration("2m59"))
        XCTAssertNil(GroqAdapter.duration("--"))
    }

    // MARK: - Units and resets

    func testRequestsAreDailyAndTokensPerMinute() async throws {
        let snapshot = try await adapter(headers: fullHeaders).fetchUsage(forceSync: true)

        let requests = try XCTUnwrap(snapshot.modelQuotas.first { $0.name.contains("RPD") })
        let tokens = try XCTUnwrap(snapshot.modelQuotas.first { $0.name.contains("TPM") })

        XCTAssertEqual(requests.quotaType, "일일 14400 요청")
        XCTAssertEqual(tokens.quotaType, "분당 18000 토큰")
    }

    func testTheReportedResetsAreUsedRatherThanAFlatMinute() async throws {
        let snapshot = try await adapter(headers: fullHeaders).fetchUsage(forceSync: true)

        let requests = try XCTUnwrap(snapshot.modelQuotas.first { $0.name.contains("RPD") })
        let tokens = try XCTUnwrap(snapshot.modelQuotas.first { $0.name.contains("TPM") })

        XCTAssertEqual(try XCTUnwrap(requests.resetCountdown), 179.56, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(tokens.resetCountdown), 7.66, accuracy: 0.001)
        XCTAssertNotEqual(requests.resetCountdown, 60)
        XCTAssertNotEqual(tokens.resetCountdown, 60)
    }

    func testAnExhaustedDailyBudgetReadsAsZero() async throws {
        let snapshot = try await adapter(headers: fullHeaders).fetchUsage(forceSync: true)

        let requests = try XCTUnwrap(snapshot.modelQuotas.first { $0.name.contains("RPD") })
        XCTAssertEqual(requests.remainingPercentage, 0)
        XCTAssertEqual(snapshot.weeklyRemainingPercentage, 0, "the daily budget takes the longer slot")
    }

    func testTheMinuteBudgetLeads() async throws {
        let snapshot = try await adapter(headers: fullHeaders).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 50, "9000 of 18000 tokens")
        XCTAssertEqual(snapshot.hourlyQuotaName, "토큰 한도 (TPM)")
    }

    // MARK: - Partial and missing headers

    func testOnlyRequestHeadersStillProducesAReading() async throws {
        let snapshot = try await adapter(headers: [
            "x-ratelimit-limit-requests": "1000",
            "x-ratelimit-remaining-requests": "250",
            "x-ratelimit-reset-requests": "5m"
        ]).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 25)
        XCTAssertEqual(snapshot.hourlyQuotaName, "요청 한도 (RPD)")
        XCTAssertNil(snapshot.weeklyRemainingPercentage, "the daily budget is not also shown twice")
        XCTAssertEqual(snapshot.modelQuotas.count, 1)
    }

    func testOnlyTokenHeadersStillProducesAReading() async throws {
        let snapshot = try await adapter(headers: [
            "x-ratelimit-limit-tokens": "1000",
            "x-ratelimit-remaining-tokens": "800"
        ]).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 80)
        XCTAssertNil(snapshot.hourlyResetCountdown, "no reset header, no countdown")
    }

    func testNoRateLimitHeadersIsUnknownRatherThanFull() async throws {
        let snapshot = try await adapter(headers: [:]).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.unavailableReason, .malformedResponse)
        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 0)
        XCTAssertTrue(snapshot.modelQuotas.isEmpty)
    }

    func testAZeroLimitIsNotADenominator() async throws {
        let snapshot = try await adapter(headers: [
            "x-ratelimit-limit-tokens": "0",
            "x-ratelimit-remaining-tokens": "0"
        ]).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.unavailableReason, .malformedResponse)
    }

    func testANonNumericHeaderIsIgnoredRatherThanGuessed() async throws {
        let snapshot = try await adapter(headers: [
            "x-ratelimit-limit-tokens": "lots",
            "x-ratelimit-remaining-tokens": "some"
        ]).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.unavailableReason, .malformedResponse)
    }

    // MARK: - The window helper

    func testWindowRefusesToDivideByNothing() {
        XCTAssertNil(GroqAdapter.window(remaining: 5, limit: 0, reset: nil))
        XCTAssertNil(GroqAdapter.window(remaining: nil, limit: 100, reset: nil))
        XCTAssertNil(GroqAdapter.window(remaining: 5, limit: nil, reset: nil))
        XCTAssertEqual(
            GroqAdapter.window(remaining: 25, limit: 100, reset: 30),
            GroqAdapter.RateWindow(percentage: 25, limit: 100, reset: 30)
        )
    }
}

