import XCTest
@testable import Glancie

/// Answers `/credits` and `/key` separately, so the two budgets can disagree.
private struct RoutingTransport: UsageTransport {
    var credits: String?
    var key: String?
    var creditsStatus: Int = 200
    var keyStatus: Int = 200

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""
        let isKey = path.hasSuffix("/key")
        let body = (isKey ? key : credits) ?? "{}"
        let status = isKey ? keyStatus : creditsStatus
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        return (Data(body.utf8), response)
    }
}

/// Which OpenRouter budget the bar is actually reporting.
///
/// `keyEndpoint` was declared and never called, so a key whose own allowance was
/// spent still showed the account's remaining credits — 90% for a key that could
/// not make one more request.
final class OpenRouterKeyBudgetTests: XCTestCase {

    /// The wording asserted below is the Korean wording. Pin it, so the suite
    /// passes on an English Mac and never reads the tester's own preference.
    override func setUp() {
        super.setUp()
        Localization.renderLanguage(.korean)
    }


    private func adapter(_ transport: RoutingTransport) throws -> OpenRouterAdapter {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glancie-or-\(UUID().uuidString)")
        let key = root.appendingPathComponent(".config/openrouter/api_key")
        try FileManager.default.createDirectory(
            at: key.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("sk-or-test".utf8).write(to: key)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        return OpenRouterAdapter(homeDirectory: root.path, transport: transport)
    }

    private func row(_ snapshot: UsageSnapshot, containing text: String) -> ModelQuotaItem? {
        snapshot.modelQuotas.first { $0.name.contains(text) }
    }

    // MARK: - The reported case

    func testAnExhaustedKeyIsNotHiddenByAHealthyAccountBalance() async throws {
        // The audit's fixture: 90 credits left on the account, and a key that
        // cannot spend another cent.
        let snapshot = try await adapter(RoutingTransport(
            credits: #"{"data": {"total_credits": 100, "total_usage": 10}}"#,
            key: #"{"data": {"limit": 5, "limit_remaining": 0, "usage": 5, "is_free_tier": false}}"#
        )).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 0, "the key is what a request hits first")
        XCTAssertEqual(snapshot.hourlyQuotaName, "API 키 예산")
        XCTAssertEqual(snapshot.weeklyRemainingPercentage, 90, "the account balance is still shown, separately")
    }

    func testBothBudgetsGetTheirOwnRow() async throws {
        let snapshot = try await adapter(RoutingTransport(
            credits: #"{"data": {"total_credits": 100, "total_usage": 10}}"#,
            key: #"{"data": {"limit": 20, "limit_remaining": 5, "usage": 15, "is_free_tier": false}}"#
        )).fetchUsage(forceSync: true)

        XCTAssertEqual(row(snapshot, containing: "API 키 예산")?.name, "API 키 예산 ($5.00 / $20.00)")
        XCTAssertEqual(row(snapshot, containing: "계정 잔액")?.name, "계정 잔액 ($90.00)")
        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 25)
    }

    // MARK: - Unlimited, free and empty

    func testANullLimitIsUnlimitedRatherThanMissing() async throws {
        // OpenRouter says "uncapped" by sending `limit: null`; that is a fact
        // about the key, and the account balance remains the real constraint.
        let snapshot = try await adapter(RoutingTransport(
            credits: #"{"data": {"total_credits": 50, "total_usage": 20}}"#,
            key: #"{"data": {"limit": null, "limit_remaining": null, "usage": 20, "is_free_tier": false}}"#
        )).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 60, "the account balance leads")
        XCTAssertEqual(snapshot.hourlyQuotaName, "계정 잔액")
        XCTAssertEqual(row(snapshot, containing: "API 키")?.paceText, "무제한")
    }

    func testAFreeTierKeyIsLabelledAsOne() async throws {
        let snapshot = try await adapter(RoutingTransport(
            credits: #"{"data": {"total_credits": 0, "total_usage": 0}}"#,
            key: #"{"data": {"limit": null, "limit_remaining": null, "usage": 0, "is_free_tier": true}}"#
        )).fetchUsage(forceSync: true)

        XCTAssertEqual(row(snapshot, containing: "API 키")?.quotaType, "Free Tier Key")
        XCTAssertEqual(snapshot.hourlyQuotaName, "API 키 (무제한)")
    }

    func testZeroCreditsAndNoKeyCeilingIsUnknownRatherThanFull() async throws {
        // No purchases, nothing spent, no key limit: there is no proportion to
        // report. The old code called that 100%.
        let snapshot = try await adapter(RoutingTransport(
            credits: #"{"data": {"total_credits": 0, "total_usage": 0}}"#,
            key: nil,
            keyStatus: 404
        )).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.unavailableReason, .notMeasured)
        XCTAssertNotEqual(snapshot.hourlyRemainingPercentage, 100)
    }

    func testAnAccountThatHasSpentEverythingReadsAsZero() async throws {
        let snapshot = try await adapter(RoutingTransport(
            credits: #"{"data": {"total_credits": 40, "total_usage": 40}}"#,
            key: #"{"data": {"limit": null, "limit_remaining": null, "usage": 40}}"#
        )).fetchUsage(forceSync: true)

        XCTAssertNil(snapshot.unavailableReason, "spent is measured, not unknown")
        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 0)
    }

    // MARK: - Partial failures

    func testAFailedKeyLookupStillReportsTheAccountBalance() async throws {
        // A key budget that could not be read is absent, not unlimited.
        let snapshot = try await adapter(RoutingTransport(
            credits: #"{"data": {"total_credits": 100, "total_usage": 25}}"#,
            key: nil,
            keyStatus: 500
        )).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 75)
        XCTAssertEqual(snapshot.hourlyQuotaName, "계정 잔액")
        XCTAssertNil(row(snapshot, containing: "API 키"), "nothing is claimed about the key")
    }

    func testAFailedCreditsLookupIsAFailedRead() async throws {
        let snapshot = try await adapter(RoutingTransport(
            credits: nil,
            key: #"{"data": {"limit": 5, "limit_remaining": 5, "usage": 0}}"#,
            creditsStatus: 401
        )).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.unavailableReason, .authenticationFailed)
        XCTAssertTrue(snapshot.modelQuotas.isEmpty)
    }

    func testAMalformedCreditsBodyIsNotGuessedAt() async throws {
        let snapshot = try await adapter(RoutingTransport(
            credits: #"{"data": {"total_credits": 100}}"#,
            key: #"{"data": {"limit": 5, "limit_remaining": 5, "usage": 0}}"#
        )).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.unavailableReason, .malformedResponse)
    }

    // MARK: - The budget models

    func testCreditsWithoutPurchasesHaveNoShare() {
        XCTAssertNil(OpenRouterAdapter.Credits(json: ["total_credits": 0, "total_usage": 0])?.share)
        XCTAssertEqual(
            OpenRouterAdapter.Credits(json: ["total_credits": 10, "total_usage": 2])?.share,
            80
        )
    }

    func testAKeyLimitOfZeroIsNotADenominator() {
        let budget = OpenRouterAdapter.KeyBudget(json: ["limit": 0, "limit_remaining": 0, "usage": 0])
        XCTAssertNil(budget?.limitedShare)
        XCTAssertFalse(budget?.isUnlimited ?? true, "zero is a ceiling of zero, not the absence of one")
    }

    func testIntegerAndDoubleFieldsBothDecode() {
        XCTAssertEqual(
            OpenRouterAdapter.KeyBudget(json: ["limit": 8, "limit_remaining": 2.0, "usage": 6])?.limitedShare,
            25
        )
    }
}
