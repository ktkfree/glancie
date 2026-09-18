import XCTest
@testable import Glancie

/// How one fetch's snapshots are folded into what is filed per account.
///
/// The registry is refreshed on launch and on an explicit rescan, while the
/// adapters re-read their profiles on every fetch. The two therefore disagree
/// for as long as it takes to notice a login switch, and the merge is where that
/// disagreement used to be resolved the wrong way round.
@MainActor
final class AccountAggregationTests: XCTestCase {

    // MARK: - Fixtures

    private func snapshot(
        account: String,
        percentage: Double,
        capturedAt: Date,
        email: String? = nil,
        plan: String? = nil
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claudeCode,
            hourlyRemainingPercentage: percentage,
            accountEmail: email,
            planName: plan,
            strategyUsed: .localFileCache,
            accountID: account,
            capturedAt: capturedAt
        )
    }

    private func merge(
        _ fetched: [UsageSnapshot],
        into existing: [String: UsageSnapshot] = [:],
        known: Set<String> = [],
        scanned: Bool = true,
        stored: [String: UsageSnapshot] = [:]
    ) -> (byAccount: [String: UsageSnapshot], reported: Set<String>, recorded: [UsageSnapshot], unattributed: UsageSnapshot?) {
        ProviderManager.merged(
            attributed: fetched,
            into: existing,
            knownAccountIDs: known,
            registryHasScanned: scanned,
            storedSnapshot: { stored[$0] }
        )
    }

    private let t0 = Date(timeIntervalSince1970: 1000)
    private let t1 = Date(timeIntervalSince1970: 2000)

    // MARK: - The switch

    func testASwitchedToAccountIsNotFilteredAwayByTheStaleRegistry() {
        // The reported case: the registry still lists only A, the adapter now
        // reports B, and the `known` filter deleted B on the way out — leaving
        // A's figures on screen as though nothing had happened.
        let existing = ["acct-A": snapshot(account: "acct-A", percentage: 80, capturedAt: t0)]
        let result = merge(
            [snapshot(account: "acct-B", percentage: 20, capturedAt: t1)],
            into: existing,
            known: ["acct-A"]
        )

        XCTAssertEqual(result.byAccount["acct-B"]?.hourlyRemainingPercentage, 20)
        XCTAssertEqual(result.reported, ["acct-B"])
    }

    func testAnAccountThatIsGoneAndUnreportedIsStillDropped() {
        // The filter still has a job: a removed login must not linger with
        // figures that quietly age into a lie.
        let existing = [
            "acct-A": snapshot(account: "acct-A", percentage: 80, capturedAt: t0),
            "acct-gone": snapshot(account: "acct-gone", percentage: 55, capturedAt: t0)
        ]
        let result = merge(
            [snapshot(account: "acct-A", percentage: 70, capturedAt: t1)],
            into: existing,
            known: ["acct-A"]
        )

        XCTAssertNil(result.byAccount["acct-gone"])
        XCTAssertEqual(result.byAccount.count, 1)
    }

    func testAnUnscannedRegistryDropsNothing() {
        // Before the first scan lands there is nothing to filter against, and
        // filtering against an empty set would erase every reading.
        let result = merge(
            [snapshot(account: "acct-A", percentage: 70, capturedAt: t1)],
            into: ["acct-B": snapshot(account: "acct-B", percentage: 10, capturedAt: t0)],
            known: [],
            scanned: false
        )

        XCTAssertEqual(result.byAccount.count, 2)
    }

    func testAScannedRegistryWithNoAccountsLeftDropsEverything() {
        // Emptiness used to stand in for "has not scanned yet", so signing out
        // of the last account read as "nothing to filter against" and left the
        // departed account's figures on screen with nothing able to remove them.
        let result = merge(
            [],
            into: ["acct-B": snapshot(account: "acct-B", percentage: 10, capturedAt: t0)],
            known: [],
            scanned: true
        )

        XCTAssertTrue(result.byAccount.isEmpty)
    }

    // MARK: - Duplicate profiles for one account

    func testTheNewestReadingWinsForOneAccountReportedTwice() {
        // Two profiles signed into the same account produce two snapshots in one
        // fetch. Array order used to decide, so the fresher 20% lost to the
        // stale 80% whenever the adapter happened to list them that way.
        let result = merge([
            snapshot(account: "acct-A", percentage: 20, capturedAt: t1),
            snapshot(account: "acct-A", percentage: 80, capturedAt: t0)
        ])

        XCTAssertEqual(result.byAccount["acct-A"]?.hourlyRemainingPercentage, 20)
    }

    func testTheNewestReadingWinsInTheOtherOrderToo() {
        let result = merge([
            snapshot(account: "acct-A", percentage: 80, capturedAt: t0),
            snapshot(account: "acct-A", percentage: 20, capturedAt: t1)
        ])

        XCTAssertEqual(result.byAccount["acct-A"]?.hourlyRemainingPercentage, 20)
    }

    func testAnOlderFetchDoesNotOverwriteANewerLiveReading() {
        // Same rule the persistent store applies, now applied in memory too:
        // a late-arriving older reading moves nothing backwards.
        let existing = ["acct-A": snapshot(account: "acct-A", percentage: 20, capturedAt: t1)]
        let result = merge(
            [snapshot(account: "acct-A", percentage: 80, capturedAt: t0)],
            into: existing
        )

        XCTAssertEqual(result.byAccount["acct-A"]?.hourlyRemainingPercentage, 20)
    }

    func testANewProfileForANewAccountIsAddedBesideTheExistingOne() {
        let existing = ["acct-A": snapshot(account: "acct-A", percentage: 80, capturedAt: t0)]
        let result = merge(
            [
                snapshot(account: "acct-A", percentage: 70, capturedAt: t1),
                snapshot(account: "acct-B", percentage: 30, capturedAt: t1)
            ],
            into: existing,
            known: ["acct-A", "acct-B"]
        )

        XCTAssertEqual(result.byAccount["acct-A"]?.hourlyRemainingPercentage, 70)
        XCTAssertEqual(result.byAccount["acct-B"]?.hourlyRemainingPercentage, 30)
    }

    // MARK: - Failures inside the merge

    func testATransientFailureFallsBackToTheStoredReading() {
        let stored = ["acct-A": snapshot(account: "acct-A", percentage: 42, capturedAt: t0)]
        var failed = UsageSnapshot.unavailable(for: .claudeCode, reason: .networkFailure)
        failed.accountID = "acct-A"

        let result = merge([failed], stored: stored)

        XCTAssertEqual(result.byAccount["acct-A"]?.hourlyRemainingPercentage, 42)
        XCTAssertEqual(result.byAccount["acct-A"]?.capturedAt, t0, "and it keeps its own age")
    }

    func testASnapshotWithoutAnAccountDrivesTheBarWithoutBeingFiled() {
        let orphan = UsageSnapshot(
            provider: .claudeCode,
            hourlyRemainingPercentage: 55,
            strategyUsed: .localFileCache
        )
        let result = merge([orphan])

        XCTAssertTrue(result.byAccount.isEmpty)
        XCTAssertEqual(result.unattributed?.hourlyRemainingPercentage, 55)
    }

    func testOnlyRealReadingsAreHandedToTheStore() {
        var failed = UsageSnapshot.unavailable(for: .claudeCode, reason: .rateLimited)
        failed.accountID = "acct-A"
        let good = snapshot(account: "acct-B", percentage: 60, capturedAt: t1)

        let result = merge([failed, good])

        XCTAssertEqual(result.recorded.count, 2, "the store applies its own simulated filter")
        XCTAssertEqual(result.reported, ["acct-A", "acct-B"])
    }

    // MARK: - Attribution

    private func account(_ id: String, email: String, plan: String) -> ResolvedAccount {
        ResolvedAccount(
            id: id,
            provider: .claudeCode,
            email: email,
            planName: plan,
            sources: [AccountSource(id: "claude.cli", kind: .cli, displayName: "Claude CLI")]
        )
    }

    func testAnUnknownAccountIDIsNotDressedInThePreviousAccountsIdentity() {
        // The id was right and every readable field beside it belonged to
        // somebody else — the worst possible combination, because the screen
        // named one person while showing another's numbers.
        let outgoing = account("acct-A", email: "a@example.com", plan: "Max")
        let attributed = ProviderManager.attributed(
            snapshot(account: "acct-B", percentage: 20, capturedAt: t1),
            lookup: { _ in nil },
            fallback: { outgoing },
            primarySourceID: "claude.cli"
        )

        XCTAssertEqual(attributed.accountID, "acct-B")
        XCTAssertNil(attributed.accountEmail)
        XCTAssertNil(attributed.planName)
    }

    func testAKnownAccountIDStillGetsItsOwnDetails() {
        let known = account("acct-B", email: "b@example.com", plan: "Pro")
        let attributed = ProviderManager.attributed(
            snapshot(account: "acct-B", percentage: 20, capturedAt: t1),
            lookup: { $0 == "acct-B" ? known : nil },
            fallback: { nil },
            primarySourceID: "claude.cli"
        )

        XCTAssertEqual(attributed.accountEmail, "b@example.com")
        XCTAssertEqual(attributed.planName, "Pro")
        XCTAssertEqual(attributed.sourceID, "claude.cli")
    }

    func testASnapshotWithNoAccountStillUsesTheProviderLevelFallback() {
        // Adapters that report one snapshot for the whole provider rely on this;
        // only an id the adapter *did* supply blocks the fallback.
        let fallback = account("acct-A", email: "a@example.com", plan: "Max")
        let attributed = ProviderManager.attributed(
            UsageSnapshot(provider: .claudeCode, hourlyRemainingPercentage: 50),
            lookup: { _ in nil },
            fallback: { fallback },
            primarySourceID: "claude.cli"
        )

        XCTAssertEqual(attributed.accountID, "acct-A")
        XCTAssertEqual(attributed.accountEmail, "a@example.com")
    }

    func testAnAdapterSuppliedEmailIsNotOverwritten() {
        let known = account("acct-B", email: "registry@example.com", plan: "Pro")
        let attributed = ProviderManager.attributed(
            snapshot(account: "acct-B", percentage: 20, capturedAt: t1, email: "adapter@example.com"),
            lookup: { _ in known },
            fallback: { nil },
            primarySourceID: "claude.cli"
        )

        XCTAssertEqual(attributed.accountEmail, "adapter@example.com")
    }
}
