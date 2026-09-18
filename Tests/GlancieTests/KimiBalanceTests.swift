import XCTest
@testable import Glancie

/// How a Moonshot balance response becomes a reading.
///
/// `available_balance` is what the account can spend, and Moonshot documents it
/// as already covering cash and vouchers together. Adding `voucher_balance` on
/// top counted every coupon twice, and the "Cash Balance" row showed the
/// available total rather than the cash.
final class KimiBalanceTests: XCTestCase {

    private func adapter(_ body: String) throws -> KimiAdapter {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glancie-kimi-\(UUID().uuidString)")
        let key = root.appendingPathComponent(".config/moonshot/api_key")
        try FileManager.default.createDirectory(
            at: key.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("sk-test".utf8).write(to: key)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        return KimiAdapter(homeDirectory: root.path, transport: StubTransport.ok(body))
    }

    private func row(_ snapshot: UsageSnapshot, containing text: String) -> ModelQuotaItem? {
        snapshot.modelQuotas.first { $0.name.contains(text) }
    }

    // MARK: - The documented example

    func testTheOfficialExampleIsNotDoubleCounted() async throws {
        // available 49.58894 / voucher 46.58893 / cash 3.00001 was reported as a
        // ¥96.18 total with ¥49.59 of "cash".
        let body = #"{"data": {"available_balance": 49.58894, "voucher_balance": 46.58893, "cash_balance": 3.00001}}"#
        let snapshot = try await adapter(body).fetchUsage(forceSync: true)

        XCTAssertNil(snapshot.unavailableReason)
        XCTAssertEqual(row(snapshot, containing: "Total Balance")?.name, "Total Balance (¥49.59)")
        XCTAssertEqual(row(snapshot, containing: "Cash Balance")?.name, "Cash Balance (¥3.00)")
        XCTAssertEqual(row(snapshot, containing: "Vouchers")?.name, "Vouchers (¥46.59)")
    }

    func testTheHeadlineFigureFollowsTheAvailableBalance() async throws {
        let body = #"{"data": {"available_balance": 25.0, "voucher_balance": 20.0, "cash_balance": 5.0}}"#
        let snapshot = try await adapter(body).fetchUsage(forceSync: true)

        // 25 of the display scale's 50, not (25 + 20) of it.
        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 50.0, accuracy: 0.001)
    }

    // MARK: - Partial and edge responses

    func testAResponseWithoutVouchersOmitsTheRowRatherThanShowingZero() async throws {
        let body = #"{"data": {"available_balance": 12.0, "cash_balance": 12.0}}"#
        let snapshot = try await adapter(body).fetchUsage(forceSync: true)

        XCTAssertNil(row(snapshot, containing: "Vouchers"))
        XCTAssertEqual(row(snapshot, containing: "Total Balance")?.name, "Total Balance (¥12.00)")
    }

    func testAResponseWithoutCashOmitsThatRowToo() async throws {
        let body = #"{"data": {"available_balance": 12.0, "voucher_balance": 12.0}}"#
        let snapshot = try await adapter(body).fetchUsage(forceSync: true)

        XCTAssertNil(row(snapshot, containing: "Cash Balance"))
        XCTAssertNotNil(row(snapshot, containing: "Vouchers"))
    }

    func testNegativeCashIsShownAsOwedRatherThanClampedAway() async throws {
        // An account in arrears reports negative cash. The amount is real and is
        // displayed; only its share of the display scale floors at zero.
        let body = #"{"data": {"available_balance": 10.0, "voucher_balance": 15.0, "cash_balance": -5.0}}"#
        let snapshot = try await adapter(body).fetchUsage(forceSync: true)

        XCTAssertEqual(row(snapshot, containing: "Cash Balance")?.name, "Cash Balance (¥-5.00)")
        XCTAssertEqual(row(snapshot, containing: "Cash Balance")?.remainingPercentage, 0)
        XCTAssertEqual(row(snapshot, containing: "Total Balance")?.name, "Total Balance (¥10.00)")
    }

    func testAZeroBalanceIsAReadingRatherThanAMissingField() async throws {
        let body = #"{"data": {"available_balance": 0, "voucher_balance": 0, "cash_balance": 0}}"#
        let snapshot = try await adapter(body).fetchUsage(forceSync: true)

        XCTAssertNil(snapshot.unavailableReason, "an empty account is measured, not unknown")
        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 0)
        XCTAssertEqual(row(snapshot, containing: "Total Balance")?.name, "Total Balance (¥0.00)")
    }

    func testIntegerBalancesDecodeAsWellAsDecimals() async throws {
        let body = #"{"data": {"available_balance": 30, "voucher_balance": 10, "cash_balance": 20}}"#
        let snapshot = try await adapter(body).fetchUsage(forceSync: true)

        XCTAssertEqual(row(snapshot, containing: "Total Balance")?.name, "Total Balance (¥30.00)")
    }

    func testAResponseWithoutAnAvailableBalanceIsUnknown() async throws {
        // Without the field the API calls authoritative there is nothing to
        // report — least of all a total reconstructed from the parts.
        let body = #"{"data": {"voucher_balance": 46.58893, "cash_balance": 3.00001}}"#
        let snapshot = try await adapter(body).fetchUsage(forceSync: true)

        XCTAssertEqual(snapshot.unavailableReason, .malformedResponse)
        XCTAssertTrue(snapshot.modelQuotas.isEmpty)
    }

    func testAFailedReadProducesNoAmounts() async throws {
        for status in [401, 429, 500] {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("glancie-kimi-\(UUID().uuidString)")
            let key = root.appendingPathComponent(".config/moonshot/api_key")
            try FileManager.default.createDirectory(
                at: key.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("sk-test".utf8).write(to: key)
            addTeardownBlock { try? FileManager.default.removeItem(at: root) }

            let snapshot = try await KimiAdapter(
                homeDirectory: root.path,
                transport: StubTransport.status(status)
            ).fetchUsage(forceSync: true)

            XCTAssertTrue(snapshot.modelQuotas.isEmpty, "HTTP \(status) invented a balance")
            XCTAssertTrue(snapshot.isSimulated)
        }
    }
}
