import Foundation

/// Claude Code adapter.
///
/// Claude Code keeps the answer to `/usage` in its own config file, under
/// `cachedUsageUtilization`, complete with the account UUID it belongs to and
/// the reset timestamps. Reading that is both faster and more trustworthy than
/// the alternatives: spawning `claude -p "/usage"` costs a process launch and a
/// regex over prose, and the OAuth usage endpoint it would otherwise call rate
/// limits hard enough that polling it is not viable.
///
/// The CLI probe is kept as a fallback for when the cache is missing or has gone
/// cold.
public final class ClaudeCodeAdapter: AIProviderAdapter, @unchecked Sendable {
    public let type: AIProviderType = .claudeCode

    private let detected = Locked(false)
    public var isDetected: Bool { detected.value }

    /// How old Claude Code's cache may be before it is worth paying for a live
    /// CLI probe.
    ///
    /// Tied to the threshold the display uses, because holding out longer than
    /// that means showing a reading the app has already decided is stale while
    /// declining to refresh it. Claude Code only rewrites the cache when it
    /// happens to talk to the usage API, which during a long session can be
    /// twenty minutes apart — long enough for the session figure to move by
    /// twenty points.
    static let cacheFreshnessWindow: TimeInterval = UsageSnapshot.stalenessThreshold

    /// `claude -p /usage` takes about five seconds on a warm install and more on
    /// a cold one. The old budget was under that, so the probe was killed every
    /// time and the fallback never actually produced a reading.
    private static let probeTimeout: TimeInterval = 20.0

    /// The floor between two probes of the same profile, enforced by
    /// `ProbeGate` and bypassable by nothing.
    ///
    /// Every probe launches a second `claude` that rewrites the same
    /// `~/.claude.json` the user's own session is writing and starts every MCP
    /// server that config names. At ten-second intervals — which is what the
    /// activity trigger asked for once `forceSync` was allowed to skip this —
    /// that contention is enough to hang the CLI outright.
    ///
    /// Five minutes is not a display policy. The file is re-read on every single
    /// refresh, so the figure on screen still moves the moment Claude Code
    /// writes a new one; this only paces the case where the app goes and asks.
    static let probeMinimumInterval: TimeInterval = 5 * 60

    /// Arguments every probe carries.
    ///
    /// `--strict-mcp-config` with no `--mcp-config` means "start no MCP servers
    /// at all". Without it each probe boots every server named in the user's
    /// global config — an OAuth-holding, socket-opening process per launch, for
    /// a question answered entirely locally.
    private static let probeArguments = ["--strict-mcp-config", "-p", "/usage"]

    /// How many probe transcripts to keep.
    ///
    /// `claude` files one per invocation and never prunes them; measured at 118
    /// sitting in the probe's own project directory.
    private static let probeTranscriptsKept = 5

    private let fileManager = FileManager.default
    private let homeDir = FileManager.default.homeDirectoryForCurrentUser

    /// Where the probe is run from.
    ///
    /// `claude` files a transcript under `~/.claude/projects/<slugified cwd>`
    /// for every invocation, `/usage` included. Run from Glancie's own working
    /// directory those writes land in a watched project and read back as the
    /// user working — a probe that triggers the activity that triggers the next
    /// probe. Given a directory of its own they are trivially recognisable, and
    /// the activity rule ignores them by name.
    static let probeWorkingDirectoryName = "Glancie-ClaudeProbe"

    private let cachedSnapshot = Locked<UsageSnapshot?>(nil)

    public init() {}

    public func checkAvailability() async -> Bool {
        let claudeDir = homeDir.appendingPathComponent(".claude")
        let binaryPath = homeDir.appendingPathComponent(".local/bin/claude")
        let found = fileManager.fileExists(atPath: claudeDir.path)
            || fileManager.isExecutableFile(atPath: binaryPath.path)
        detected.value = found
        return found
    }

    /// Every profile's usage, not just the default one.
    ///
    /// Each `CLAUDE_CONFIG_DIR` profile has its own `.claude.json` holding its
    /// own account *and* its own usage cache, so a second account's live quota
    /// costs one more file read — no process, no network.
    public func fetchUsagePerAccount(forceSync: Bool) async throws -> [UsageSnapshot] {
        var snapshots: [UsageSnapshot] = []
        for profile in ClaudeAccountResolver.profiles() {
            if let snapshot = await usage(for: profile, forceSync: forceSync) {
                snapshots.append(snapshot)
            }
        }

        // With no readable profile there is still the CLI probe to fall back on,
        // which only ever speaks for the default account.
        guard snapshots.isEmpty else { return snapshots }
        return [try await fetchUsage(forceSync: forceSync)]
    }

    /// One profile's usage: its config file, re-read every time, and a CLI probe
    /// only once that file has gone genuinely cold and the gate allows one.
    ///
    /// The cache going cold is not an edge case — Claude Code only rewrites it
    /// when it has a fresh answer in hand, so a machine that has been running
    /// sessions all day can still be carrying figures from two days ago.
    ///
    /// `forceSync` is deliberately not consulted here. It used to mean "skip the
    /// freshness window and skip the probe backoff", and since every trigger
    /// that matters sets it, the effect was a `claude` launch every ten seconds
    /// for as long as the user kept working. What those triggers actually want
    /// is the *current file*, and the file is re-read on every call whether they
    /// ask or not. Paying a process launch on top of that buys at most one
    /// refresh interval of freshness and costs the user's own session.
    private func usage(for profile: ClaudeAccountResolver.Profile, forceSync: Bool) async -> UsageSnapshot? {
        let config = AccountFileReader.cachedJSON(atPath: profile.configPath)
        let cached = config.flatMap(Self.snapshot(fromConfig:))

        if let cached, Date().timeIntervalSince(cached.capturedAt) < Self.cacheFreshnessWindow {
            return cached
        }

        if let probed = await probe(
            profile: profile,
            identity: config.map(Self.identity(fromConfig:))
        ) {
            return probed
        }

        return cached
    }

    /// Asks one profile's CLI for its usage report, if `ProbeGate` allows it.
    ///
    /// `CLAUDE_CONFIG_DIR` picks which profile `claude` reads, so an alternate
    /// account is measured against its own config rather than the default one's.
    private func probe(
        profile: ClaudeAccountResolver.Profile,
        identity: ConfigIdentity?
    ) async -> UsageSnapshot? {
        var environment: [String: String] = [:]
        // True for every profile whose config lives inside its own config dir,
        // which is every profile except the default `~/.claude.json`.
        let ownConfigDir = (profile.homeDirectory as NSString).appendingPathComponent(".claude.json")
        if profile.configPath == ownConfigDir {
            environment["CLAUDE_CONFIG_DIR"] = profile.homeDirectory
        }

        let output = await ProbeGate.shared.withProbe(
            key: "claude:\(profile.configPath)",
            minimumInterval: Self.probeMinimumInterval
        ) {
            await Self.runProbe(environment: environment)
        }

        guard let output, var snapshot = parseClaudeUsageOutput(output) else { return nil }

        if let identity {
            snapshot.accountID = identity.accountID
            snapshot.accountEmail = identity.email
            snapshot.planName = identity.planName
        }
        snapshot.sourceID = "claude.cli"
        return snapshot
    }

    /// The probe itself, minus the question of whether it is allowed to run.
    private static func runProbe(environment: [String: String]) async -> String? {
        defer { pruneProbeTranscripts() }
        return await CLIProcessRunner.run(
            command: "claude",
            arguments: probeArguments,
            timeout: probeTimeout,
            environment: environment,
            workingDirectory: probeWorkingDirectory()
        )
    }

    public func fetchUsage(forceSync: Bool = false) async throws -> UsageSnapshot {
        let profile = ClaudeAccountResolver.profiles().first
        let config = profile.flatMap { AccountFileReader.cachedJSON(atPath: $0.configPath) }
        let identity = config.map(Self.identity(fromConfig:))

        // Strategies 1 and 2: the profile's own cache while it is warm, then a
        // live CLI probe.
        if let profile, let snapshot = await usage(for: profile, forceSync: forceSync) {
            cachedSnapshot.value = snapshot
            return snapshot
        }

        // No profile at all, but the CLI may still be installed and signed in.
        // Gated exactly like every other probe — a machine with no readable
        // config is the one most likely to keep asking.
        if profile == nil {
            let output = await ProbeGate.shared.withProbe(
                key: "claude:default",
                minimumInterval: Self.probeMinimumInterval
            ) {
                await Self.runProbe(environment: [:])
            }
            if let output, var snapshot = parseClaudeUsageOutput(output) {
                snapshot.sourceID = "claude.cli"
                cachedSnapshot.value = snapshot
                return snapshot
            }
        }

        // Strategy 3: a dated reading beats a fabricated one.
        if let cached = cachedSnapshot.value { return cached }

        return Self.unknownSnapshot(identity: identity)
    }

    /// Deletes all but the newest few probe transcripts.
    ///
    /// `claude` files one per invocation and prunes none of them; they are pure
    /// exhaust — the same six-line `/usage` local command every time.
    static func pruneProbeTranscripts(keeping keep: Int = probeTranscriptsKept) {
        // Found by name rather than by reproducing the slug: how `claude`
        // flattens a path into a directory name is its business, and a rule
        // guessed here would silently stop matching the day it changes.
        let projects = AccountFileReader.home.appendingPathComponent(".claude/projects")
        guard let directories = try? FileManager.default.contentsOfDirectory(atPath: projects.path),
              let slug = directories.first(where: { $0.contains(probeWorkingDirectoryName) })
        else { return }
        let transcripts = projects.appendingPathComponent(slug)

        guard let names = try? FileManager.default.contentsOfDirectory(atPath: transcripts.path) else { return }
        let dated = names
            .filter { $0.hasSuffix(".jsonl") }
            .map { name -> (path: String, modified: Date) in
                let path = transcripts.appendingPathComponent(name).path
                let attributes = try? FileManager.default.attributesOfItem(atPath: path)
                return (path, (attributes?[.modificationDate] as? Date) ?? .distantPast)
            }
            .sorted { $0.modified > $1.modified }

        for stale in dated.dropFirst(max(0, keep)) {
            try? FileManager.default.removeItem(atPath: stale.path)
        }
    }

    /// The probe's own directory, created on first use. Nil if it cannot be
    /// made, which only means the probe runs where it would have anyway.
    static func probeWorkingDirectory() -> URL? {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? AccountFileReader.home.appendingPathComponent("Library/Application Support")
        let directory = base.appendingPathComponent(probeWorkingDirectoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            return nil
        }
    }

    // MARK: - Config parsing

    struct ConfigIdentity {
        var accountID: String?
        var email: String?
        var planName: String?
    }

    static func identity(fromConfig config: [String: Any]) -> ConfigIdentity {
        guard let account = config["oauthAccount"] as? [String: Any] else { return ConfigIdentity() }
        let rawPlan = account["organizationType"] as? String
        return ConfigIdentity(
            accountID: account["accountUuid"] as? String,
            email: account["emailAddress"] as? String,
            planName: rawPlan.map { raw in
                switch raw {
                case "claude_pro": return "Claude Pro"
                case "claude_max": return "Claude Max"
                case "claude_team": return "Claude Team"
                case "claude_enterprise": return "Claude Enterprise"
                default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
                }
            }
        )
    }

    /// Builds a snapshot from a parsed `.claude.json`.
    ///
    /// Returns nil when the cached figures belong to a different account than
    /// the one currently signed in — which happens right after an account switch,
    /// and is exactly the case where showing one account's address beside another
    /// account's percentages would be worse than showing nothing.
    static func snapshot(fromConfig config: [String: Any]) -> UsageSnapshot? {
        let identity = identity(fromConfig: config)

        guard let cached = config["cachedUsageUtilization"] as? [String: Any],
              let utilization = cached["utilization"] as? [String: Any] else { return nil }

        if let cachedAccount = cached["accountUuid"] as? String,
           let signedInAccount = identity.accountID,
           cachedAccount != signedInAccount {
            return nil
        }

        let capturedAt: Date
        if let fetchedAtMs = cached["fetchedAtMs"] as? Double {
            capturedAt = Date(timeIntervalSince1970: fetchedAtMs / 1000.0)
        } else {
            capturedAt = Date()
        }

        let session = window(utilization["five_hour"])
        let weekly = window(utilization["seven_day"])

        var quotas = (utilization["limits"] as? [[String: Any]] ?? []).compactMap(quotaItem(fromLimit:))
        if let extra = extraUsageItem(utilization["extra_usage"]) {
            quotas.append(extra)
        }
        if quotas.isEmpty {
            quotas = fallbackQuotas(session: session, weekly: weekly)
        }

        return UsageSnapshot(
            provider: .claudeCode,
            hourlyRemainingPercentage: session?.remaining ?? 100.0,
            hourlyResetCountdown: session?.countdown,
            weeklyRemainingPercentage: weekly?.remaining,
            weeklyResetCountdown: weekly?.countdown,
            modelQuotas: quotas,
            accountEmail: identity.email,
            planName: identity.planName,
            lastUpdated: capturedAt,
            strategyUsed: .localFileCache,
            accountID: identity.accountID,
            sourceID: "claude.cli",
            capturedAt: capturedAt
        )
    }

    // MARK: - Utilization decoding

    struct QuotaWindow {
        /// Percentage still available, i.e. `100 - utilization`.
        var remaining: Double
        var countdown: TimeInterval?
    }

    /// One `{ utilization, resets_at }` block. The payload reports percentage
    /// *used*; everything downstream of here is expressed as remaining.
    static func window(_ raw: Any?) -> QuotaWindow? {
        guard let object = raw as? [String: Any],
              let used = numeric(object["utilization"]) else { return nil }
        return QuotaWindow(
            remaining: max(0.0, min(100.0, 100.0 - used)),
            countdown: countdown(from: object["resets_at"])
        )
    }

    private static func quotaItem(fromLimit limit: [String: Any]) -> ModelQuotaItem? {
        guard let used = numeric(limit["percent"]) else { return nil }
        let kind = limit["kind"] as? String ?? "limit"
        let group = limit["group"] as? String ?? kind
        let severity = limit["severity"] as? String
        let isActive = (limit["is_active"] as? Bool) ?? false

        var notes: [String] = []
        switch severity {
        case "warning": notes.append(L10n.quotaNoteWarning.text)
        case "critical": notes.append(L10n.quotaNoteCritical.text)
        default: break
        }
        if isActive { notes.append(L10n.quotaNoteBindingLimit.text) }

        return ModelQuotaItem(
            name: displayName(forLimitKind: kind),
            remainingPercentage: max(0.0, min(100.0, 100.0 - used)),
            quotaType: quotaType(forGroup: group),
            resetCountdown: countdown(from: limit["resets_at"]),
            paceText: notes.isEmpty ? nil : notes.joined(separator: " · ")
        )
    }

    /// Extra usage is billed credit rather than a rate window, so it only earns
    /// a row once the user has actually turned it on.
    private static func extraUsageItem(_ raw: Any?) -> ModelQuotaItem? {
        guard let object = raw as? [String: Any],
              (object["is_enabled"] as? Bool) == true,
              let used = numeric(object["utilization"]) else { return nil }

        var pace: String?
        if let limit = numeric(object["monthly_limit"]), let credits = numeric(object["used_credits"]) {
            let currency = object["currency"] as? String ?? "USD"
            pace = "\(Int(credits)) / \(Int(limit)) \(currency)"
        }

        return ModelQuotaItem(
            name: L10n.claudeExtraCredits.text,
            remainingPercentage: max(0.0, min(100.0, 100.0 - used)),
            quotaType: "Monthly Credit",
            paceText: pace
        )
    }

    private static func fallbackQuotas(session: QuotaWindow?, weekly: QuotaWindow?) -> [ModelQuotaItem] {
        var items: [ModelQuotaItem] = []
        if let session {
            items.append(
                ModelQuotaItem(
                    name: L10n.claudeSession5h.text,
                    remainingPercentage: session.remaining,
                    quotaType: "5-Hour Session",
                    resetCountdown: session.countdown
                )
            )
        }
        if let weekly {
            items.append(
                ModelQuotaItem(
                    name: L10n.claudeWeeklyAllModels.text,
                    remainingPercentage: weekly.remaining,
                    quotaType: "Weekly Limit",
                    resetCountdown: weekly.countdown
                )
            )
        }
        return items
    }

    private static func displayName(forLimitKind kind: String) -> String {
        switch kind {
        case "session": return L10n.claudeSession5h.text
        case "weekly_all": return L10n.claudeWeeklyAllModels.text
        case "weekly_opus": return L10n.claudeWeeklyModel("Opus").text
        case "weekly_sonnet": return L10n.claudeWeeklyModel("Sonnet").text
        default:
            return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private static func quotaType(forGroup group: String) -> String {
        switch group {
        case "session": return "5-Hour Session"
        case "weekly": return "Weekly Limit"
        default: return group.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// JSON numbers arrive as `Int` or `Double` depending on how they were
    /// written, and a percentage of `0` must stay a value rather than become nil.
    private static func numeric(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        return nil
    }

    static func countdown(from raw: Any?, now: Date = Date()) -> TimeInterval? {
        guard let text = raw as? String, let date = parseTimestamp(text) else { return nil }
        let interval = date.timeIntervalSince(now)
        return interval > 0 ? interval : nil
    }

    /// `2026-08-31T18:49:59.848396+00:00`.
    ///
    /// The fractional seconds are stripped rather than parsed: the payload
    /// carries six digits, and `ISO8601DateFormatter` only tolerates three.
    static func parseTimestamp(_ text: String) -> Date? {
        let trimmed = text.replacingOccurrences(
            of: #"\.\d+"#,
            with: "",
            options: .regularExpression
        )

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: trimmed) { return date }

        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        return formatter.date(from: trimmed)
    }

    /// Shown when nothing could be read at all. Deliberately reports full quota
    /// with `.simulated`, so the strategy badge admits the figure is a placeholder.
    private static func unknownSnapshot(identity: ConfigIdentity?) -> UsageSnapshot {
        UsageSnapshot(
            provider: .claudeCode,
            hourlyRemainingPercentage: 0.0,
            hourlyResetCountdown: nil,
            weeklyRemainingPercentage: nil,
            weeklyResetCountdown: nil,
            modelQuotas: [],
            accountEmail: identity?.email,
            planName: identity?.planName,
            strategyUsed: .simulated,
            accountID: identity?.accountID,
            sourceID: "claude.cli"
        )
    }

    // MARK: - CLI output parsing (fallback)

    /// Parses output like:
    /// "Current session: 2% used · resets Aug 30 at 4:19am (Asia/Seoul)"
    /// "Current week (all models): 87% used · resets Sep 1 at 1:59pm (Asia/Seoul)"
    /// "Current week (Opus): 12% used · resets Sep 1 at 1:59pm (Asia/Seoul)"
    ///
    /// Returns nil unless the session line was actually found. Anything else —
    /// an error, a truncated read, a login prompt — has no percentage in it, and
    /// a defaulted one would reach the bar indistinguishable from a measurement.
    /// - Parameter now: what the reset phrases are measured against. The report
    ///   dates them without a year, so the answer depends on when it is read —
    ///   which makes it something a test has to be able to pin.
    public func parseClaudeUsageOutput(_ text: String, now: Date = Date()) -> UsageSnapshot? {
        guard let session = Self.usageLine(
            in: text,
            pattern: #"Current session:\s*(\d+)%\s*used([^\n]*)"#,
            now: now
        ) else {
            return nil
        }
        let weekly = Self.usageLine(
            in: text,
            pattern: #"Current week\s*\(all models\):\s*(\d+)%\s*used([^\n]*)"#,
            now: now
        )

        var models: [ModelQuotaItem] = [
            ModelQuotaItem(
                name: L10n.claudeSession5h.text,
                remainingPercentage: session.remaining,
                quotaType: "5-Hour Session",
                resetCountdown: session.countdown
            )
        ]
        if let weekly {
            models.append(
                ModelQuotaItem(
                    name: L10n.claudeWeeklyAllModels.text,
                    remainingPercentage: weekly.remaining,
                    quotaType: "Weekly Limit",
                    resetCountdown: weekly.countdown
                )
            )
        }
        // Per-model weekly pools only appear on the plans that have them.
        for (label, name) in [("Opus", L10n.claudeWeeklyModel("Opus").text), ("Sonnet", L10n.claudeWeeklyModel("Sonnet").text)] {
            guard let window = Self.usageLine(
                in: text,
                pattern: #"Current week\s*\(\#(label)\):\s*(\d+)%\s*used([^\n]*)"#,
                now: now
            ) else { continue }
            models.append(
                ModelQuotaItem(
                    name: name,
                    remainingPercentage: window.remaining,
                    quotaType: "Weekly Limit",
                    resetCountdown: window.countdown
                )
            )
        }

        return UsageSnapshot(
            provider: .claudeCode,
            hourlyRemainingPercentage: session.remaining,
            hourlyResetCountdown: session.countdown,
            weeklyRemainingPercentage: weekly?.remaining,
            weeklyResetCountdown: weekly?.countdown,
            modelQuotas: models,
            lastUpdated: Date(),
            strategyUsed: .cliStatusProbe
        )
    }

    /// One `"...: N% used · resets <when>"` line.
    static func usageLine(in text: String, pattern: String, now: Date = Date()) -> QuotaWindow? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let percentRange = Range(match.range(at: 1), in: text),
              let used = Double(text[percentRange]) else { return nil }

        var countdown: TimeInterval?
        if match.numberOfRanges > 2, let tailRange = Range(match.range(at: 2), in: text) {
            countdown = resetCountdown(fromPhrase: String(text[tailRange]), now: now)
        }

        return QuotaWindow(remaining: max(0.0, min(100.0, 100.0 - used)), countdown: countdown)
    }

    /// `"· resets Sep 2 at 11:19pm (Asia/Seoul)"` as seconds from now.
    ///
    /// The phrase carries no year, so the nearest reading wins: a reset that
    /// lands more than a day in the past belongs to next year, which is only
    /// ever the turn from December into January.
    static func resetCountdown(fromPhrase phrase: String, now: Date = Date()) -> TimeInterval? {
        let pattern = #"resets\s+([A-Za-z]{3})\s+(\d{1,2})\s+at\s+(\d{1,2}):(\d{2})\s*([ap]m)(?:\s*\(([^)]+)\))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: phrase, range: NSRange(phrase.startIndex..., in: phrase)) else {
            return nil
        }

        func group(_ index: Int) -> String? {
            guard index < match.numberOfRanges,
                  let range = Range(match.range(at: index), in: phrase) else { return nil }
            return String(phrase[range])
        }

        guard let monthName = group(1), let month = Self.monthNumbers[monthName.lowercased()],
              let day = group(2).flatMap(Int.init),
              var hour = group(3).flatMap(Int.init),
              let minute = group(4).flatMap(Int.init),
              let meridiem = group(5)?.lowercased() else { return nil }

        if meridiem == "pm" && hour != 12 { hour += 12 }
        if meridiem == "am" && hour == 12 { hour = 0 }

        var calendar = Calendar(identifier: .gregorian)
        // The report prints the reset in a named zone; without it the figure
        // would be off by the difference between that zone and this machine's.
        calendar.timeZone = group(6).flatMap(TimeZone.init(identifier:)) ?? .current

        var components = DateComponents()
        components.year = calendar.component(.year, from: now)
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute

        guard var reset = calendar.date(from: components) else { return nil }
        if reset.timeIntervalSince(now) < -86400 {
            components.year = (components.year ?? 0) + 1
            guard let nextYear = calendar.date(from: components) else { return nil }
            reset = nextYear
        }

        let interval = reset.timeIntervalSince(now)
        return interval > 0 ? interval : nil
    }

    private static let monthNumbers: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12
    ]
}
