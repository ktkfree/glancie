import XCTest
@testable import Glancie

/// What a reading means once the window it was taken in has ended.
///
/// A rate limit window rolling over is not the same thing as a reading going
/// stale. A stale reading is still the last thing known to have been true; a
/// reading from a window that has closed is known to be false — the quota
/// refilled at the reset, and the figure beside it describes a window that no
/// longer exists. It sat on screen for hours wearing the 임박 badge.
final class ElapsedQuotaWindowTests: XCTestCase {

    /// The wording asserted below is the Korean wording. Pin it, so the suite
    /// passes on an English Mac and never reads the tester's own preference.
    override func setUp() {
        super.setUp()
        Localization.renderLanguage(.korean)
    }


    private func limits(
        usedPercent: Double,
        windowMinutes: Int?,
        resetsAt: Date?,
        capturedAt: Date
    ) -> OpenAI_CodexAdapter.RateLimits {
        OpenAI_CodexAdapter.RateLimits(
            primary: OpenAI_CodexAdapter.RateWindow(
                remaining: 100 - usedPercent,
                windowMinutes: windowMinutes,
                resetsAt: resetsAt
            ),
            secondary: OpenAI_CodexAdapter.RateWindow(
                remaining: 54, windowMinutes: 10_080, resetsAt: capturedAt.addingTimeInterval(6 * 86_400)
            ),
            planType: "plus",
            creditBalance: nil,
            hasUnlimitedCredits: false,
            capturedAt: capturedAt,
            sessionStartedAt: capturedAt
        )
    }

    // MARK: - The window's own clock

    func testAWindowStillOpenIsNotElapsed() {
        let now = Date(timeIntervalSince1970: 1_788_760_000)
        let snapshot = OpenAI_CodexAdapter.snapshot(
            from: limits(
                usedPercent: 96, windowMinutes: 300,
                resetsAt: now.addingTimeInterval(1_800), capturedAt: now
            ),
            account: nil,
            now: now
        )

        XCTAssertFalse(snapshot.isHourlyWindowElapsed(now: now))
        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 4)
        XCTAssertEqual(snapshot.hourlyResetCountdown, 1_800)
    }

    func testAWindowPastItsResetIsElapsed() {
        // The case from the screenshot: read at 10:11, window closed at 14:50,
        // looked at 16:42. The countdown had gone nil hours earlier and the
        // card simply stopped drawing it, while 4% and 임박 stayed put.
        let capturedAt = Date(timeIntervalSince1970: 1_788_743_504)
        let resetsAt = Date(timeIntervalSince1970: 1_788_760_226)
        let now = resetsAt.addingTimeInterval(6_700)

        let snapshot = OpenAI_CodexAdapter.snapshot(
            from: limits(
                usedPercent: 96, windowMinutes: 300, resetsAt: resetsAt, capturedAt: capturedAt
            ),
            account: nil,
            now: now
        )

        XCTAssertTrue(snapshot.isHourlyWindowElapsed(now: now))
        XCTAssertEqual(snapshot.hourlyResetAt, resetsAt, "the moment survives the countdown going nil")
        XCTAssertNil(snapshot.hourlyResetCountdown)
    }

    func testAWindowWithNoPublishedResetIsNeverElapsed() {
        // No reset time is not a reset that has passed. Treating the two alike
        // is what this whole distinction exists to stop.
        let now = Date(timeIntervalSince1970: 1_788_760_000)
        let snapshot = OpenAI_CodexAdapter.snapshot(
            from: limits(usedPercent: 96, windowMinutes: 300, resetsAt: nil, capturedAt: now),
            account: nil,
            now: now
        )

        XCTAssertNil(snapshot.hourlyResetAt)
        XCTAssertFalse(snapshot.isHourlyWindowElapsed(now: now))
        XCTAssertFalse(snapshot.isHourlyWindowElapsed(now: now.addingTimeInterval(86_400)))
    }

    func testTheWeeklyReadingSurvivesTheHourlyWindowClosing() {
        // The two windows close on their own schedules. The 5-hour one rolling
        // over says nothing about the week, and dropping the whole snapshot
        // would throw away a figure that is still true.
        let capturedAt = Date(timeIntervalSince1970: 1_788_743_504)
        let resetsAt = capturedAt.addingTimeInterval(3_600)
        let now = resetsAt.addingTimeInterval(60)

        let snapshot = OpenAI_CodexAdapter.snapshot(
            from: limits(
                usedPercent: 96, windowMinutes: 300, resetsAt: resetsAt, capturedAt: capturedAt
            ),
            account: nil,
            now: now
        )

        XCTAssertTrue(snapshot.isHourlyWindowElapsed(now: now))
        XCTAssertEqual(snapshot.weeklyRemainingPercentage, 54)
        XCTAssertNotNil(snapshot.weeklyResetCountdown)
        XCTAssertFalse(snapshot.isSimulated, "an elapsed window is not a missing provider")
    }

    func testTheWeeklyWindowClosesOnItsOwnClock() {
        // The week closing is as silent as the five hours closing was: the
        // countdown goes nil and the bar keeps its last percentage.
        let capturedAt = Date(timeIntervalSince1970: 1_788_743_504)
        let weeklyResetsAt = capturedAt.addingTimeInterval(6 * 86_400)
        let now = weeklyResetsAt.addingTimeInterval(120)

        let snapshot = OpenAI_CodexAdapter.snapshot(
            from: limits(
                usedPercent: 96, windowMinutes: 300,
                resetsAt: capturedAt.addingTimeInterval(7 * 86_400), capturedAt: capturedAt
            ),
            account: nil,
            now: now
        )

        XCTAssertEqual(snapshot.weeklyResetAt, weeklyResetsAt)
        XCTAssertTrue(snapshot.isWeeklyWindowElapsed(now: now))
        XCTAssertNil(snapshot.weeklyResetCountdown)
        XCTAssertFalse(
            snapshot.isHourlyWindowElapsed(now: now),
            "the hourly window outlasts the week here, and must not be dragged down with it"
        )
    }

    func testTheTwoWindowsElapseIndependently() {
        let capturedAt = Date(timeIntervalSince1970: 1_788_743_504)
        let now = capturedAt.addingTimeInterval(3_600)

        let snapshot = OpenAI_CodexAdapter.snapshot(
            from: limits(
                usedPercent: 96, windowMinutes: 300,
                resetsAt: capturedAt.addingTimeInterval(600), capturedAt: capturedAt
            ),
            account: nil,
            now: now
        )

        XCTAssertTrue(snapshot.isHourlyWindowElapsed(now: now))
        XCTAssertFalse(snapshot.isWeeklyWindowElapsed(now: now))
    }

    // MARK: - The rows below

    func testEachModelRowCarriesItsOwnWindowsReset() throws {
        // The rows repeat the same two windows the hero and the weekly bar
        // show. Without their own reset instant the hero could read 리셋됨
        // while the row for that very window still showed the old percentage.
        let capturedAt = Date(timeIntervalSince1970: 1_788_743_504)
        let hourlyResetsAt = capturedAt.addingTimeInterval(600)
        let now = capturedAt.addingTimeInterval(3_600)

        let snapshot = OpenAI_CodexAdapter.snapshot(
            from: limits(
                usedPercent: 96, windowMinutes: 300, resetsAt: hourlyResetsAt, capturedAt: capturedAt
            ),
            account: nil,
            now: now
        )

        let hourlyRow = try XCTUnwrap(snapshot.modelQuotas.first { $0.name == "5시간 한도" })
        let weeklyRow = try XCTUnwrap(snapshot.modelQuotas.first { $0.name == "1주 한도" })

        XCTAssertEqual(hourlyRow.resetAt, hourlyResetsAt)
        XCTAssertEqual(hourlyRow.isWindowElapsed(now: now), true)
        XCTAssertEqual(
            weeklyRow.isWindowElapsed(now: now), false,
            "the weekly row is not dragged down by the hourly one"
        )
        XCTAssertEqual(
            hourlyRow.isWindowElapsed(now: hourlyResetsAt.addingTimeInterval(-1)), false
        )
    }

    func testARowWithNoResetInstantIsNeverElapsed() {
        // Credits carry a balance and no window at all.
        let item = ModelQuotaItem(name: "크레딧", remainingPercentage: 100, quotaType: "Credits")
        XCTAssertNil(item.resetAt)
        XCTAssertFalse(item.isWindowElapsed(now: Date(timeIntervalSince1970: 4_000_000_000)))
    }

    // MARK: - Naming the window

    func testTheHeadlineIsNamedAfterTheWindowItWasReadFrom() {
        // The ring said "세션 쿼터" while the row underneath called the same
        // number "5시간 한도". Codex declares the window; the headline can use it.
        let now = Date(timeIntervalSince1970: 1_788_760_000)
        let snapshot = OpenAI_CodexAdapter.snapshot(
            from: limits(
                usedPercent: 96, windowMinutes: 300,
                resetsAt: now.addingTimeInterval(600), capturedAt: now
            ),
            account: nil,
            now: now
        )

        XCTAssertEqual(snapshot.hourlyQuotaName, "5시간 한도")
        XCTAssertEqual(snapshot.modelQuotas.first?.name, "5시간 한도", "and agrees with the row below")
    }

    func testAWindowCodexDoesNotDeclareLeavesTheHeadlineUnnamed() {
        let now = Date(timeIntervalSince1970: 1_788_760_000)
        let snapshot = OpenAI_CodexAdapter.snapshot(
            from: limits(
                usedPercent: 40, windowMinutes: nil,
                resetsAt: now.addingTimeInterval(600), capturedAt: now
            ),
            account: nil,
            now: now
        )

        XCTAssertNil(snapshot.hourlyQuotaName, "the display's own wording stays in place")
    }

    // MARK: - Round-tripping

    func testTheResetMomentSurvivesStorage() throws {
        // Snapshots are restored from disk between launches; a reset time that
        // did not survive would resurrect the alarm on every relaunch.
        let capturedAt = Date(timeIntervalSince1970: 1_788_743_504)
        let resetsAt = Date(timeIntervalSince1970: 1_788_760_226)
        let snapshot = OpenAI_CodexAdapter.snapshot(
            from: limits(
                usedPercent: 96, windowMinutes: 300, resetsAt: resetsAt, capturedAt: capturedAt
            ),
            account: nil,
            now: capturedAt
        )

        let restored = try JSONDecoder().decode(
            UsageSnapshot.self, from: try JSONEncoder().encode(snapshot)
        )
        XCTAssertEqual(restored.hourlyResetAt, resetsAt)
        XCTAssertTrue(restored.isHourlyWindowElapsed(now: resetsAt.addingTimeInterval(1)))
        XCTAssertEqual(restored.weeklyResetAt, snapshot.weeklyResetAt)
        XCTAssertEqual(
            restored.modelQuotas.map(\.resetAt), snapshot.modelQuotas.map(\.resetAt),
            "the rows' own windows survive too"
        )
    }

    func testASnapshotStoredBeforeThisFieldExistedDecodesAsNotElapsed() throws {
        // Absent is not "elapsed at the epoch": an old snapshot must not come
        // back with its figures withheld.
        let json = """
        {"provider":"codex","hourlyRemainingPercentage":42.0,"modelQuotas":[],
         "usedTokens":0,"totalTokens":100000,"lastUpdated":0,"capturedAt":0,
         "strategyUsed":"Local Cache/DB"}
        """
        let restored = try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))

        XCTAssertNil(restored.hourlyResetAt)
        XCTAssertNil(restored.weeklyResetAt)
        XCTAssertFalse(restored.isHourlyWindowElapsed())
        XCTAssertFalse(restored.isWeeklyWindowElapsed())
        XCTAssertEqual(restored.hourlyRemainingPercentage, 42)
    }
}
