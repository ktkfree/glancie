import XCTest
@testable import Glancie

/// Adapters that have no way to read a real quota must say so.
///
/// Every case here used to return a plausible percentage assembled from
/// something that is not a measurement — a count of log folders, a plan name, a
/// settings file, a list of callable models. On the bar those are
/// indistinguishable from a reading, which is the whole problem: a number that
/// moves for unrelated reasons is worse than no number at all.
final class UnmeasuredQuotaTests: XCTestCase {

    // MARK: - Helpers

    private func makeTemporaryHome() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glancie-unmeasured-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func write(_ contents: String, to path: URL) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: path)
    }

    /// The invariant every one of these snapshots has to hold: no percentage,
    /// no countdown, no per-model rows that a reader could mistake for quota.
    private func assertNoFabricatedFigures(
        _ snapshot: UsageSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(snapshot.isSimulated, "must not present as a measurement", file: file, line: line)
        XCTAssertNotNil(snapshot.unavailableReason, "must say why there is no figure", file: file, line: line)
        XCTAssertEqual(snapshot.hourlyRemainingPercentage, 0.0, file: file, line: line)
        XCTAssertNil(snapshot.weeklyRemainingPercentage, file: file, line: line)
        XCTAssertNil(snapshot.hourlyResetCountdown, file: file, line: line)
        XCTAssertNil(snapshot.weeklyResetCountdown, file: file, line: line)
        XCTAssertTrue(snapshot.modelQuotas.isEmpty, file: file, line: line)
        XCTAssertEqual(snapshot.usedTokens, 0, file: file, line: line)
    }

    // MARK: - Cursor

    func testCursorLogFolderCountIsNotUsage() async throws {
        // The old adapter mapped folder count to a percentage: 0 folders read as
        // 100% left, 34 read as 5%. Neither figure came from Cursor, so the same
        // answer — none — has to come back from all three.
        for folderCount in [0, 10, 34] {
            let home = try makeTemporaryHome()
            let logs = home.appendingPathComponent("Library/Application Support/Cursor/logs")
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            for index in 0..<folderCount {
                try FileManager.default.createDirectory(
                    at: logs.appendingPathComponent("window\(index)"),
                    withIntermediateDirectories: true
                )
            }

            let snapshot = try await CursorAdapter(homeDirectory: home.path).fetchUsage()
            assertNoFabricatedFigures(snapshot)
            XCTAssertEqual(
                snapshot.unavailableReason, .notMeasured,
                "installed Cursor with \(folderCount) log folder(s) is detected but unmeasured"
            )
        }
    }

    func testCursorWithoutAnInstallReportsNotConfigured() async throws {
        let home = try makeTemporaryHome()
        let snapshot = try await CursorAdapter(homeDirectory: home.path).fetchUsage()
        assertNoFabricatedFigures(snapshot)
        XCTAssertEqual(snapshot.unavailableReason, .notConfigured)
    }

    func testCursorDetectionIsIndependentOfTheQuotaAnswer() async throws {
        let home = try makeTemporaryHome()
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Application Support/Cursor"),
            withIntermediateDirectories: true
        )
        let adapter = CursorAdapter(homeDirectory: home.path)
        let detected = await adapter.checkAvailability()

        let snapshot = try await adapter.fetchUsage()

        XCTAssertTrue(detected, "an installed editor is still detected")
        XCTAssertTrue(snapshot.isSimulated, "being installed is not a quota")
    }

    // MARK: - Windsurf

    func testWindsurfPlanNameIsMetadataNotQuota() async throws {
        let home = try makeTemporaryHome()
        try write(#"{"user": {"plan": "teams"}}"#, to: home.appendingPathComponent(".codeium/config.json"))

        let snapshot = try await WindsurfAdapter(homeDirectory: home.path).fetchUsage(forceSync: false)
        assertNoFabricatedFigures(snapshot)
        XCTAssertEqual(snapshot.planName, "Windsurf Teams", "the plan is still worth showing")
        XCTAssertEqual(snapshot.unavailableReason, .notMeasured)
    }

    func testWindsurfPlanChangeDoesNotMoveAnyPercentage() async throws {
        var snapshots: [UsageSnapshot] = []
        for plan in ["free", "pro", "teams"] {
            let home = try makeTemporaryHome()
            try write(
                "{\"user\": {\"plan\": \"\(plan)\"}}",
                to: home.appendingPathComponent(".codeium/config.json")
            )
            snapshots.append(try await WindsurfAdapter(homeDirectory: home.path).fetchUsage(forceSync: false))
        }

        XCTAssertEqual(Set(snapshots.map(\.planName)).count, 3, "the plan varies")
        XCTAssertEqual(
            Set(snapshots.map(\.hourlyRemainingPercentage)), [0.0],
            "…and the quota stays absent, because the plan never measured it"
        )
    }

    func testWindsurfWithoutConfigReportsNotConfigured() async throws {
        let home = try makeTemporaryHome()
        let snapshot = try await WindsurfAdapter(homeDirectory: home.path).fetchUsage(forceSync: false)
        assertNoFabricatedFigures(snapshot)
        XCTAssertNil(snapshot.planName)
        // `/Applications/Windsurf.app` may exist on the machine running this, so
        // only the absence of figures is asserted unconditionally.
        XCTAssertTrue([.notConfigured, .notMeasured].contains(snapshot.unavailableReason))
    }

    // MARK: - Zed

    func testSettingsOnlyZedIsNotMeasuredQuota() async throws {
        // Verbatim from the audit: an empty settings object used to yield 97%.
        let home = try makeTemporaryHome()
        try write("{}", to: home.appendingPathComponent(".config/zed/settings.json"))

        let snapshot = try await ZedAdapter(homeDirectory: home.path).fetchUsage(forceSync: false)
        assertNoFabricatedFigures(snapshot)
        XCTAssertNil(snapshot.planName, "an empty settings file names no model")
    }

    func testZedModelNameTravelsAsMetadata() async throws {
        let home = try makeTemporaryHome()
        try write(
            #"{"assistant": {"default_model": {"model": "claude-sonnet-4"}}}"#,
            to: home.appendingPathComponent(".config/zed/settings.json")
        )

        let snapshot = try await ZedAdapter(homeDirectory: home.path).fetchUsage(forceSync: false)
        assertNoFabricatedFigures(snapshot)
        XCTAssertEqual(snapshot.planName, "Zed AI · claude-sonnet-4")
    }

    // MARK: - Mistral

    func testMistralReportsNotConfiguredWithoutAKey() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MISTRAL_API_KEY"]?.isEmpty ?? true,
            "a real key in the environment would be detected"
        )
        let home = try makeTemporaryHome()
        let snapshot = try await MistralAdapter(homeDirectory: home.path).fetchUsage(forceSync: false)
        assertNoFabricatedFigures(snapshot)
        XCTAssertEqual(snapshot.unavailableReason, .notConfigured)
    }

    func testMistralKeyDoesNotProduceAPercentage() async throws {
        let home = try makeTemporaryHome()
        try write("sk-test-key", to: home.appendingPathComponent(".config/mistral/api_key"))

        let snapshot = try await MistralAdapter(homeDirectory: home.path).fetchUsage(forceSync: false)
        assertNoFabricatedFigures(snapshot)
        XCTAssertEqual(snapshot.unavailableReason, .notMeasured, "a usable key is not a quota reading")
    }

    // MARK: - The shared representation

    func testAnExhaustedQuotaIsRepresentableAndDistinctFromNoData() {
        // 0% left is a real, sayable measurement; the old Cursor path floored it
        // at 5% so a spent account never looked spent.
        let spent = UsageSnapshot(
            provider: .cursor,
            hourlyRemainingPercentage: 0.0,
            strategyUsed: .localFileCache
        )
        let unknown = UsageSnapshot.unavailable(for: .cursor, reason: .notMeasured)

        XCTAssertEqual(spent.hourlyRemainingPercentage, unknown.hourlyRemainingPercentage)
        XCTAssertFalse(spent.isSimulated, "an exhausted quota is a measurement")
        XCTAssertTrue(unknown.isSimulated)
        XCTAssertNil(spent.unavailableReason)
        XCTAssertNotNil(unknown.unavailableReason)
    }

    func testUnavailableSnapshotSurvivesACodableRoundTrip() throws {
        let original = UsageSnapshot.unavailable(
            for: .windsurf,
            reason: .notMeasured,
            planName: "Windsurf Pro"
        )
        let decoded = try JSONDecoder().decode(
            UsageSnapshot.self,
            from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.unavailableReason, .notMeasured)
    }

    func testSnapshotsStoredBeforeTheReasonExistedStillDecode() throws {
        // Persisted snapshots predate `unavailableReason`; a missing key must
        // decode rather than throw away the whole store.
        let legacy = """
        {
          "provider": "claude",
          "hourlyRemainingPercentage": 42,
          "modelQuotas": [],
          "usedTokens": 0,
          "totalTokens": 100000,
          "lastUpdated": 760000000,
          "capturedAt": 760000000,
          "strategyUsed": "CLI Probe"
        }
        """
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.unavailableReason)
        XCTAssertEqual(decoded.hourlyRemainingPercentage, 42)
    }

    func testEveryUnavailableReasonHasADisplayLabel() {
        for reason in [UsageUnavailableReason.notConfigured, .notMeasured] {
            XCTAssertFalse(
                UsageSnapshot.unavailable(for: .zed, reason: reason).unavailableText.isEmpty
            )
        }
    }

    func testTheNoticeDoesNotSendUnmeasuredProvidersToCheckTheirLogin() {
        // The detail card used to show one hardcoded line for every empty
        // snapshot: check your login. Cursor, Zed, Windsurf and Mistral have no
        // login that would ever produce a figure, so that line sent the user off
        // to fix something that was never broken — while the same card's footer
        // already said "사용량 측정 미지원". The two have to agree.
        let waiting = UsageUnavailableReason.notConfigured.notice
        let unmeasured = UsageUnavailableReason.notMeasured.notice

        XCTAssertTrue(waiting.isFault, "a missing sign-in is something the user can act on")
        XCTAssertFalse(unmeasured.isFault, "a provider that publishes no quota is not a fault")
        XCTAssertNotEqual(waiting.header, unmeasured.header)
        XCTAssertNotEqual(waiting.title, unmeasured.title)
        XCTAssertNotEqual(waiting.detail, unmeasured.detail)
    }

    func testEveryUnavailableReasonHasCompleteNoticeCopy() {
        for reason in [UsageUnavailableReason.notConfigured, .notMeasured] {
            let notice = reason.notice
            XCTAssertFalse(notice.header.isEmpty, "\(reason) header")
            XCTAssertFalse(notice.title.isEmpty, "\(reason) title")
            XCTAssertFalse(notice.detail.isEmpty, "\(reason) detail")
        }
    }

    func testInstalledButUnmeasuredProvidersGetTheNonFaultNotice() async throws {
        // The four adapters this MR emptied out must all land on the calm
        // notice, not the alarm one, once their app or key is present.
        let home = try makeTemporaryHome()
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent("Library/Application Support/Cursor"),
            withIntermediateDirectories: true
        )
        try write(#"{"user": {"plan": "pro"}}"#, to: home.appendingPathComponent(".codeium/config.json"))
        try write("sk-test-key", to: home.appendingPathComponent(".config/mistral/api_key"))

        let adapters: [AIProviderAdapter] = [
            CursorAdapter(homeDirectory: home.path),
            WindsurfAdapter(homeDirectory: home.path),
            MistralAdapter(homeDirectory: home.path)
        ]
        for adapter in adapters {
            let snapshot = try await adapter.fetchUsage(forceSync: false)
            let reason = try XCTUnwrap(snapshot.unavailableReason, "\(adapter.type)")
            XCTAssertEqual(reason, .notMeasured, "\(adapter.type)")
            XCTAssertFalse(reason.notice.isFault, "\(adapter.type) is detected, not broken")
        }
    }
}
