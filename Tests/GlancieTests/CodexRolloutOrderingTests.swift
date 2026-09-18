import XCTest
@testable import Glancie

/// Which rollout the Codex adapter believes is the newest reading.
///
/// The old scan walked date directories by name and returned the first readable
/// event it met, so a session resumed under yesterday's directory — the normal
/// result of `codex resume` — could never win against a session started today,
/// however much newer its turns were.
final class CodexRolloutOrderingTests: XCTestCase {

    // MARK: - Fixtures

    private func makeCodexHome() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-order-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    /// One `token_count` event as Codex writes it.
    private func event(timestamp: String, usedPercent: Double) -> [String: Any] {
        [
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "rate_limits": [
                    "primary": ["used_percent": usedPercent, "window_minutes": 300]
                ]
            ]
        ]
    }

    /// Writes a rollout at `relativePath`, stamping the file's own write time.
    @discardableResult
    private func writeRollout(
        in home: URL,
        at relativePath: String,
        events: [[String: Any]],
        modified: Date
    ) throws -> URL {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let lines = try events.map { event -> String in
            String(decoding: try JSONSerialization.data(withJSONObject: event), as: UTF8.self)
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }

    // MARK: - The reported case

    func testResumedOlderDayWins() throws {
        // Verbatim from the audit. The 9/5 directory holds the newer turn
        // because that session was resumed; the 9/6 directory was started
        // earlier in the day and has not been touched since.
        let home = try makeCodexHome()
        try writeRollout(
            in: home,
            at: "sessions/2026/09/05/rollout-resumed.jsonl",
            events: [event(timestamp: "2026-09-06T12:00:00Z", usedPercent: 90)],
            modified: Date(timeIntervalSince1970: 1_788_000_000)
        )
        try writeRollout(
            in: home,
            at: "sessions/2026/09/06/rollout-fresh.jsonl",
            events: [event(timestamp: "2026-09-06T10:00:00Z", usedPercent: 10)],
            modified: Date(timeIntervalSince1970: 1_787_990_000)
        )

        let limits = try XCTUnwrap(OpenAI_CodexAdapter.rateLimits(codexHome: home.path))
        XCTAssertEqual(limits.primary?.remaining, 10, "the 12:00 turn is the current reading")
    }

    func testTheNewerReadingWinsWhicheverDirectoryHoldsIt() throws {
        // The mirror image: today's directory holds the newer turn. The same
        // rule has to produce the opposite answer, or it is just a new bias.
        let home = try makeCodexHome()
        try writeRollout(
            in: home,
            at: "sessions/2026/09/05/rollout-resumed.jsonl",
            events: [event(timestamp: "2026-09-06T08:00:00Z", usedPercent: 90)],
            modified: Date(timeIntervalSince1970: 1_787_980_000)
        )
        try writeRollout(
            in: home,
            at: "sessions/2026/09/06/rollout-fresh.jsonl",
            events: [event(timestamp: "2026-09-06T13:00:00Z", usedPercent: 40)],
            modified: Date(timeIntervalSince1970: 1_788_000_000)
        )

        let limits = try XCTUnwrap(OpenAI_CodexAdapter.rateLimits(codexHome: home.path))
        XCTAssertEqual(limits.primary?.remaining, 60)
    }

    func testALegacyRootRolloutDoesNotOutrankANewerDatedOne() throws {
        // Older Codex builds wrote into `sessions/` directly, and those files
        // were consulted first unconditionally — so a rollout from a previous
        // major version could outrank this morning's session forever.
        let home = try makeCodexHome()
        try writeRollout(
            in: home,
            at: "sessions/rollout-legacy.jsonl",
            events: [event(timestamp: "2025-01-01T00:00:00Z", usedPercent: 5)],
            modified: Date(timeIntervalSince1970: 1_735_689_600)
        )
        try writeRollout(
            in: home,
            at: "sessions/2026/09/06/rollout-today.jsonl",
            events: [event(timestamp: "2026-09-06T09:00:00Z", usedPercent: 70)],
            modified: Date(timeIntervalSince1970: 1_788_000_000)
        )

        let limits = try XCTUnwrap(OpenAI_CodexAdapter.rateLimits(codexHome: home.path))
        XCTAssertEqual(limits.primary?.remaining, 30, "the dated rollout is the newer one")
    }

    func testALegacyRootRolloutStillWinsWhenItIsActuallyTheNewest() throws {
        let home = try makeCodexHome()
        try writeRollout(
            in: home,
            at: "sessions/rollout-legacy.jsonl",
            events: [event(timestamp: "2026-09-06T15:00:00Z", usedPercent: 5)],
            modified: Date(timeIntervalSince1970: 1_788_010_000)
        )
        try writeRollout(
            in: home,
            at: "sessions/2026/09/06/rollout-today.jsonl",
            events: [event(timestamp: "2026-09-06T09:00:00Z", usedPercent: 70)],
            modified: Date(timeIntervalSince1970: 1_788_000_000)
        )

        let limits = try XCTUnwrap(OpenAI_CodexAdapter.rateLimits(codexHome: home.path))
        XCTAssertEqual(limits.primary?.remaining, 95)
    }

    // MARK: - Ordering and bounds

    func testCandidatesAreOrderedByWriteTimeAcrossDirectories() throws {
        let home = try makeCodexHome()
        try writeRollout(
            in: home,
            at: "sessions/2026/09/01/rollout-oldest.jsonl",
            events: [event(timestamp: "2026-09-01T00:00:00Z", usedPercent: 1)],
            modified: Date(timeIntervalSince1970: 1_787_000_000)
        )
        try writeRollout(
            in: home,
            at: "sessions/2026/09/03/rollout-newest.jsonl",
            events: [event(timestamp: "2026-09-06T00:00:00Z", usedPercent: 2)],
            modified: Date(timeIntervalSince1970: 1_788_000_000)
        )
        try writeRollout(
            in: home,
            at: "sessions/2026/09/06/rollout-middle.jsonl",
            events: [event(timestamp: "2026-09-04T00:00:00Z", usedPercent: 3)],
            modified: Date(timeIntervalSince1970: 1_787_500_000)
        )

        let names = OpenAI_CodexAdapter.rolloutFiles(codexHome: home.path).map(\.lastPathComponent)
        XCTAssertEqual(names, ["rollout-newest.jsonl", "rollout-middle.jsonl", "rollout-oldest.jsonl"])
    }

    func testTheScanStopsOnceNothingOlderCouldBeNewer() throws {
        // An event cannot postdate the file holding it, so a reading at least as
        // new as the next candidate's write time settles the question. The
        // unreadable decoys below would all have to be opened without that rule.
        let home = try makeCodexHome()
        try writeRollout(
            in: home,
            at: "sessions/2026/09/06/rollout-current.jsonl",
            events: [event(timestamp: "2026-09-06T12:00:00Z", usedPercent: 25)],
            modified: Date(timeIntervalSince1970: 1_788_000_000)
        )
        for index in 0..<5 {
            try writeRollout(
                in: home,
                at: "sessions/2026/09/0\(index + 1)/rollout-old-\(index).jsonl",
                events: [event(timestamp: "2026-09-0\(index + 1)T00:00:00Z", usedPercent: 99)],
                modified: Date(timeIntervalSince1970: 1_787_000_000 + Double(index))
            )
        }

        let limits = try XCTUnwrap(OpenAI_CodexAdapter.rateLimits(codexHome: home.path))
        XCTAssertEqual(limits.primary?.remaining, 75)
    }

    func testAReadableOlderRolloutStillWinsOverAnUnreadableNewerOne() throws {
        // A session that ended before the API ever reported a limit writes an
        // all-null block. Skipping past it must still work.
        let home = try makeCodexHome()
        let emptyEvent: [String: Any] = [
            "timestamp": "2026-09-06T14:00:00Z",
            "payload": ["type": "token_count", "rate_limits": ["primary": NSNull(), "secondary": NSNull()]]
        ]
        try writeRollout(
            in: home,
            at: "sessions/2026/09/06/rollout-nulls.jsonl",
            events: [emptyEvent],
            modified: Date(timeIntervalSince1970: 1_788_010_000)
        )
        try writeRollout(
            in: home,
            at: "sessions/2026/09/06/rollout-real.jsonl",
            events: [event(timestamp: "2026-09-06T13:00:00Z", usedPercent: 60)],
            modified: Date(timeIntervalSince1970: 1_788_000_000)
        )

        let limits = try XCTUnwrap(OpenAI_CodexAdapter.rateLimits(codexHome: home.path))
        XCTAssertEqual(limits.primary?.remaining, 40)
    }

    func testTheLastEventInAResumedFileIsTheOneRead() throws {
        // Resuming appends, so the newest turn is at the end of an existing file.
        let home = try makeCodexHome()
        try writeRollout(
            in: home,
            at: "sessions/2026/09/05/rollout-long.jsonl",
            events: [
                event(timestamp: "2026-09-05T09:00:00Z", usedPercent: 10),
                event(timestamp: "2026-09-06T09:00:00Z", usedPercent: 55),
                event(timestamp: "2026-09-06T18:00:00Z", usedPercent: 80)
            ],
            modified: Date(timeIntervalSince1970: 1_788_000_000)
        )

        let limits = try XCTUnwrap(OpenAI_CodexAdapter.rateLimits(codexHome: home.path))
        XCTAssertEqual(limits.primary?.remaining, 20)
    }

    func testTheWalkIsBoundedRatherThanUnlimited() throws {
        // The bound is what keeps this off the whole sessions tree every 45
        // seconds; it has to exist, and it has to be well past useful staleness.
        XCTAssertGreaterThanOrEqual(OpenAI_CodexAdapter.dayDirectoryLookback, 7)
        XCTAssertLessThanOrEqual(OpenAI_CodexAdapter.dayDirectoryLookback, 90)

        let home = try makeCodexHome()
        for day in 1...9 {
            try writeRollout(
                in: home,
                at: "sessions/2026/09/0\(day)/rollout-\(day).jsonl",
                events: [event(timestamp: "2026-09-0\(day)T00:00:00Z", usedPercent: Double(day))],
                modified: Date(timeIntervalSince1970: 1_787_000_000 + Double(day))
            )
        }

        XCTAssertLessThanOrEqual(
            OpenAI_CodexAdapter.rolloutCandidates(codexHome: home.path).count, 12,
            "the candidate list stays bounded"
        )
    }

    func testAHomeWithoutRolloutsReadsNothing() throws {
        let home = try makeCodexHome()
        XCTAssertNil(OpenAI_CodexAdapter.rateLimits(codexHome: home.path))
        XCTAssertFalse(OpenAI_CodexAdapter.hasReadableUsage(codexHome: home.path))
    }
}
