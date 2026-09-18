import XCTest
@testable import Glancie

/// The limits that keep the app from launching a CLI faster than the user can
/// work. Each of these encodes a measured failure, not a preference.
final class ProbePacingTests: XCTestCase {

    // MARK: - ProbeGate

    func testSecondProbeInsideTheFloorIsDeclined() async {
        let gate = ProbeGate()
        var runs = 0

        let first = await gate.withProbe(key: "k", minimumInterval: 60) { () -> String? in
            runs += 1
            return "first"
        }
        let second = await gate.withProbe(key: "k", minimumInterval: 60) { () -> String? in
            runs += 1
            return "second"
        }

        XCTAssertEqual(first, "first")
        XCTAssertNil(second, "the floor must hold for callers who ask again immediately")
        XCTAssertEqual(runs, 1)
    }

    func testFloorIsMeasuredFromTheStartNotTheEnd() async {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = Locked(start)
        let gate = ProbeGate(now: { clock.value })

        _ = await gate.withProbe(key: "k", minimumInterval: 40) { () -> String? in
            clock.withValue { $0 = start.addingTimeInterval(30) }
            return "slow"
        }
        // A probe that took most of its own floor to answer does not earn an
        // immediate retry — otherwise a hanging CLI is probed continuously.
        let immediate = await gate.withProbe(key: "k", minimumInterval: 40) { "again" }
        XCTAssertNil(immediate)

        clock.withValue { $0 = start.addingTimeInterval(40) }
        let atFloor = await gate.withProbe(key: "k", minimumInterval: 40) { "again" }
        XCTAssertEqual(atFloor, "again", "the floor is measured from the start, not completion")
    }

    func testDifferentKeysDoNotShareAFloor() async {
        let gate = ProbeGate()

        let a = await gate.withProbe(key: "claude:/a/.claude.json", minimumInterval: 60) { "a" }
        let b = await gate.withProbe(key: "claude:/b/.claude.json", minimumInterval: 60) { "b" }

        XCTAssertEqual(a, "a")
        XCTAssertEqual(b, "b", "one profile's probe must not silence another profile's")
    }

    func testOnlyOneProbeRunsAtATime() async {
        let gate = ProbeGate()
        let started = Locked(0)

        async let slow: String? = gate.withProbe(key: "a", minimumInterval: 0) { () -> String? in
            started.withValue { $0 += 1 }
            try? await Task.sleep(nanoseconds: 200_000_000)
            return "a"
        }
        // Long enough that the first probe is certainly in flight.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let contender = await gate.withProbe(key: "b", minimumInterval: 0) { () -> String? in
            started.withValue { $0 += 1 }
            return "b"
        }

        _ = await slow
        XCTAssertNil(contender, "a second concurrent probe must be declined, not queued")
        XCTAssertEqual(started.value, 1)
    }

    func testTheFloorReleasesOnceItHasElapsed() async {
        let clock = Locked(Date(timeIntervalSince1970: 1_000))
        let gate = ProbeGate(now: { clock.value })

        _ = await gate.withProbe(key: "k", minimumInterval: 10) { "first" }
        clock.withValue { $0 = $0.addingTimeInterval(11) }
        let second = await gate.withProbe(key: "k", minimumInterval: 10) { "second" }

        XCTAssertEqual(second, "second")
    }

    // MARK: - Probe arguments

    func testClaudeProbeFloorIsLongEnoughToBeHarmless() {
        // Ten seconds was the measured interval that hung the user's own CLI:
        // two to three `claude` processes alive at once, all rewriting the same
        // config file. Whatever this becomes, it must never return to that.
        XCTAssertGreaterThanOrEqual(ClaudeCodeAdapter.probeMinimumInterval, 60)
        XCTAssertGreaterThanOrEqual(AntigravityAdapter.probeMinimumInterval, 60)
    }

    // MARK: - Watched path boundaries

    func testWatchedRootDoesNotSwallowItsSiblings() {
        XCTAssertTrue(FSEventsWatcher.path("/Users/me/.claude/projects/a.jsonl", isWithin: "/Users/me/.claude"))
        XCTAssertTrue(FSEventsWatcher.path("/Users/me/.claude", isWithin: "/Users/me/.claude"))

        // The bug a bare `hasPrefix` had: a second profile and the config file
        // both read as "inside" the default profile's directory.
        XCTAssertFalse(FSEventsWatcher.path("/Users/me/.claude-work/projects/a.jsonl", isWithin: "/Users/me/.claude"))
        XCTAssertFalse(FSEventsWatcher.path("/Users/me/.claude.json", isWithin: "/Users/me/.claude"))
    }

    func testTrailingSlashOnTheRootIsTolerated() {
        XCTAssertTrue(FSEventsWatcher.path("/Users/me/.codex/sessions/x.jsonl", isWithin: "/Users/me/.codex/"))
        XCTAssertFalse(FSEventsWatcher.path("/Users/me/.codex-b/sessions/x.jsonl", isWithin: "/Users/me/.codex/"))
    }
}
