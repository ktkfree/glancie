import Foundation

/// Antigravity (AGY) Adapter supporting real-time CLI usage probe (`agy -p "/usage"`)
public final class AntigravityAdapter: AIProviderAdapter, @unchecked Sendable {
    public let type: AIProviderType = .antigravity

    private let detected = Locked(false)
    public var isDetected: Bool { detected.value }

    /// `agy -p "/usage"` takes about six seconds here: it boots the whole agy
    /// server and calls `retrieveUserQuotaSummary` over the network before it
    /// prints anything. The old eight-second budget left no headroom, and the
    /// kill on timeout cancelled the quota refresh mid-flight.
    private static let probeTimeout: TimeInterval = 20.0

    /// The floor between two probes, enforced by `ProbeGate`.
    ///
    /// Shorter than Claude's because there is no file to fall back on — this
    /// probe is the only reading that exists — but a floor all the same: a
    /// probe boots an entire agy server, and the measured cost of running one
    /// per refresh was 711 log files in a day.
    static let probeMinimumInterval: TimeInterval = 3 * 60

    private let logger = GlancieLog.provider
    private let fileManager = FileManager.default
    private let homeDir = FileManager.default.homeDirectoryForCurrentUser
    /// The last probe result and when it was taken.
    ///
    /// agy keeps its quota in the process that fetched it and writes none of it
    /// to disk, so unlike Claude and Codex there is no file to fall back on —
    /// this is the only cache there is, and it lives exactly as long as Glancie
    /// does.
    private let cachedSnapshot = Locked<UsageSnapshot?>(nil)

    public init() {}

    public func checkAvailability() async -> Bool {
        let agyDir = homeDir.appendingPathComponent(".gemini/antigravity-cli")
        let binaryPath = homeDir.appendingPathComponent(".local/bin/agy")
        let found = fileManager.fileExists(atPath: agyDir.path) ||
                    fileManager.isExecutableFile(atPath: binaryPath.path) ||
                    fileManager.fileExists(atPath: "/usr/local/bin/agy") ||
                    fileManager.fileExists(atPath: "/opt/homebrew/bin/agy")
        detected.value = found
        return found
    }

    public func fetchUsage(forceSync: Bool = false) async throws -> UsageSnapshot {
        // Strategy 1: the reading already in hand, while it still describes the
        // present. Probing is not free here — each one boots an agy server and
        // makes a network call — so the polling loop is answered from memory
        // and only a caller with a reason gets a live read.
        if !forceSync, let cached = cachedSnapshot.value, !cached.isStale {
            return cached
        }

        // Strategy 2: a live probe, if the gate allows one. `forceSync` gets it
        // past the memory cache above; it does not get it past the gate, which
        // is the only thing standing between an active session and one agy
        // server boot per refresh.
        let cliOutput = await ProbeGate.shared.withProbe(
            key: "agy:default",
            minimumInterval: Self.probeMinimumInterval
        ) { () -> String? in
            self.logger.debug("Running live CLI probe: agy -p /usage")
            return await CLIProcessRunner.run(
                command: "agy",
                arguments: ["-p", "/usage"],
                timeout: Self.probeTimeout
            )
        }

        if let cliOutput, !cliOutput.isEmpty {
            if let snapshot = parseAgyUsageOutput(cliOutput) {
                cachedSnapshot.value = snapshot
                logger.debug("Parsed agy snapshot: 5h=\(snapshot.hourlyRemainingPercentage, privacy: .public)%")
                return snapshot
            }
            logger.debug("agy output parsing returned nil")
        }

        // Strategy 3: a dated reading beats a fabricated one, however old it is.
        if let cached = cachedSnapshot.value {
            return cached
        }

        // Strategy 4: Fallback when CLI probe is unavailable
        return UsageSnapshot.simulatedFallback(for: .antigravity)
    }

    /// Parses TSV / table output from `agy -p "/usage"`:
    /// Gemini Models	Weekly Limit Remaining	72%	2026-09-03T13:36:55Z
    /// Gemini Models	Five Hour Limit Remaining	98%	2026-08-30T14:30:07Z
    /// Claude and GPT models	Weekly Limit Remaining	33%	2026-09-04T08:27:48Z
    /// Claude and GPT models	Five Hour Limit Remaining	0%	2026-08-30T14:55:34Z
    public func parseAgyUsageOutput(_ text: String) -> UsageSnapshot? {
        var gemini5hRemaining: Double? = nil
        var geminiWeeklyRemaining: Double? = nil
        var claude5hRemaining: Double? = nil
        var claudeWeeklyRemaining: Double? = nil
        
        var gemini5hReset: TimeInterval? = nil
        var geminiWeeklyReset: TimeInterval? = nil
        var claude5hReset: TimeInterval? = nil
        var claudeWeeklyReset: TimeInterval? = nil

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackIsoFormatter = ISO8601DateFormatter()

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            // Format can be tab-separated or multi-space separated
            let columns = trimmed.components(separatedBy: "\t").filter { !$0.isEmpty }
            
            var modelGroup = ""
            var limitType = ""
            var percentStr = ""
            var dateStr = ""
            
            if columns.count >= 3 {
                modelGroup = columns[0].trimmingCharacters(in: .whitespaces)
                limitType = columns[1].trimmingCharacters(in: .whitespaces)
                percentStr = columns[2].trimmingCharacters(in: .whitespaces)
                if columns.count >= 4 {
                    dateStr = columns[3].trimmingCharacters(in: .whitespaces)
                }
            } else {
                // Regex fallback
                let pattern = #"^(Gemini Models|Claude and GPT models)\s+(Weekly Limit Remaining|Five Hour Limit Remaining)\s+(\d+(?:\.\d+)?)%\s*(.*)$"#
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
                    if let r1 = Range(match.range(at: 1), in: trimmed),
                       let r2 = Range(match.range(at: 2), in: trimmed),
                       let r3 = Range(match.range(at: 3), in: trimmed) {
                        modelGroup = String(trimmed[r1])
                        limitType = String(trimmed[r2])
                        percentStr = String(trimmed[r3]) + "%"
                    }
                    if match.numberOfRanges >= 5, let r4 = Range(match.range(at: 4), in: trimmed) {
                        dateStr = String(trimmed[r4]).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            
            let percentVal = Double(percentStr.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
            
            var countdown: TimeInterval? = nil
            if !dateStr.isEmpty {
                let resetDate = isoFormatter.date(from: dateStr) ?? fallbackIsoFormatter.date(from: dateStr)
                if let resetDate = resetDate {
                    countdown = max(0, resetDate.timeIntervalSince(Date()))
                }
            }
            
            let lowerGroup = modelGroup.lowercased()
            let lowerLimit = limitType.lowercased()
            
            if lowerGroup.contains("gemini") {
                if lowerLimit.contains("five") || lowerLimit.contains("5 hour") || lowerLimit.contains("session") {
                    gemini5hRemaining = percentVal
                    gemini5hReset = countdown
                } else if lowerLimit.contains("week") {
                    geminiWeeklyRemaining = percentVal
                    geminiWeeklyReset = countdown
                }
            } else if lowerGroup.contains("claude") || lowerGroup.contains("gpt") {
                if lowerLimit.contains("five") || lowerLimit.contains("5 hour") || lowerLimit.contains("session") {
                    claude5hRemaining = percentVal
                    claude5hReset = countdown
                } else if lowerLimit.contains("week") {
                    claudeWeeklyRemaining = percentVal
                    claudeWeeklyReset = countdown
                }
            }
        }
        
        // Every observed pool, in the order the bar prefers to speak for.
        //
        // Which pools `agy` prints varies by plan and by what the account has
        // actually used, so a missing one is missing — not full. Defaulting the
        // representative to Gemini's 100% is how an account with its Claude/GPT
        // session at 0% showed a full bar; defaulting the weekly figure the same
        // way invented a second one beside it.
        let sessionPools: [(name: String, remaining: Double?, reset: TimeInterval?)] = [
            ("Gemini 5-hour", gemini5hRemaining, gemini5hReset),
            ("Claude/GPT 5-hour", claude5hRemaining, claude5hReset)
        ]
        let weeklyPools: [(name: String, remaining: Double?, reset: TimeInterval?)] = [
            ("Gemini weekly", geminiWeeklyRemaining, geminiWeeklyReset),
            ("Claude/GPT weekly", claudeWeeklyRemaining, claudeWeeklyReset)
        ]

        var modelQuotas: [ModelQuotaItem] = []
        for pool in sessionPools + weeklyPools {
            guard let remaining = pool.remaining else { continue }
            modelQuotas.append(
                ModelQuotaItem(
                    name: pool.name,
                    remainingPercentage: remaining,
                    quotaType: pool.name.hasSuffix("weekly") ? "Weekly Limit" : "5-Hour Session",
                    resetCountdown: pool.reset
                )
            )
        }

        // A session pool leads when one was reported, because that is the window
        // the user is spending right now; a weekly pool stands in when it is all
        // there is. Nothing at all means nothing to show — including the
        // Claude/GPT-weekly-only output the old guard rejected outright.
        let session = sessionPools.first { $0.remaining != nil }
        let weekly = weeklyPools.first { $0.remaining != nil }
        guard let headline = session ?? weekly else { return nil }

        return UsageSnapshot(
            provider: .antigravity,
            hourlyRemainingPercentage: headline.remaining ?? 0,
            hourlyResetCountdown: headline.reset,
            weeklyRemainingPercentage: headline.name == weekly?.name ? nil : weekly?.remaining,
            weeklyResetCountdown: headline.name == weekly?.name ? nil : weekly?.reset,
            modelQuotas: modelQuotas,
            lastUpdated: Date(),
            strategyUsed: .cliStatusProbe,
            hourlyQuotaName: headline.name
        )
    }
}
