import Foundation
import os

/// The one place that decides whether a CLI probe may run.
///
/// A probe is not a read. `claude -p "/usage"` boots a second copy of the CLI,
/// which rewrites the same `~/.claude.json` the user's own session is writing
/// and starts every MCP server that config names; `agy -p "/usage"` boots a
/// whole agy server and calls Google. Two of those overlapping is enough to
/// hang the CLI this app exists to report on.
///
/// So the limits here are **hard**. Nothing bypasses them — not the refresh
/// button, not a detected turn, not `forceSync`. Declining is always safe:
/// every caller has a file cache to fall back on, and a reading that admits its
/// age beats a fresh one bought at the cost of the user's session.
///
/// What used to be here instead: a per-adapter backoff that `forceSync` was
/// allowed to skip. Since every trigger that matters sets `forceSync`, the
/// backoff was skipped every time — measured at six `claude` launches a minute,
/// two to three alive at once against a 20s timeout.
public actor ProbeGate {
    public static let shared = ProbeGate()

    /// How many probes may be in flight at once, across every provider.
    ///
    /// One. A probe is a process launch that contends for another program's
    /// config file; there is no version of this app that needs two at a time.
    private static let concurrencyLimit = 1

    private let logger = Logger(subsystem: "com.glancie", category: "ProbeGate")

    private var inFlight: Set<String> = []
    private var lastStarted: [String: Date] = [:]
    private let now: () -> Date

    public init() {
        self.now = { Date() }
    }

    init(now: @escaping () -> Date) {
        self.now = now
    }

    /// Runs `body` if the gate allows a probe for `key` right now, and returns
    /// nil without running it if not.
    ///
    /// - Parameter minimumInterval: the floor between two probes of the same
    ///   key, measured from when the last one *started* — a probe that hangs
    ///   until its timeout must not earn an immediate retry.
    public func withProbe<T>(
        key: String,
        minimumInterval: TimeInterval,
        _ body: () async -> T?
    ) async -> T? {
        guard admit(key, minimumInterval: minimumInterval) else { return nil }
        defer { release(key) }
        return await body()
    }

    /// Whether a probe may start, recording it as started if so.
    private func admit(_ key: String, minimumInterval: TimeInterval) -> Bool {
        let now = now()
        guard !inFlight.contains(key) else {
            logger.debug("Declined \(key, privacy: .public): already probing")
            return false
        }
        guard inFlight.count < Self.concurrencyLimit else {
            logger.debug("Declined \(key, privacy: .public): another probe holds the slot")
            return false
        }
        if let started = lastStarted[key] {
            let elapsed = now.timeIntervalSince(started)
            guard elapsed >= minimumInterval else {
                logger.debug(
                    "Declined \(key, privacy: .public): \(Int(minimumInterval - elapsed))s of floor left"
                )
                return false
            }
        }

        inFlight.insert(key)
        lastStarted[key] = now
        return true
    }

    private func release(_ key: String) {
        inFlight.remove(key)
    }

    /// When the next probe of this key would be allowed, for callers that want
    /// to say so on screen rather than silently serving a cached figure.
    public func nextAllowed(key: String, minimumInterval: TimeInterval) -> Date? {
        lastStarted[key].map { $0.addingTimeInterval(minimumInterval) }
    }
}
