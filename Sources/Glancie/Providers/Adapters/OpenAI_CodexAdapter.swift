import Foundation

/// Codex adapter.
///
/// Codex never writes a standalone usage file, but it does record the server's
/// own answer: every turn appends a `token_count` event to the session rollout,
/// and that event carries the `rate_limits` block the API returned — used
/// percentage, window length and reset time. Reading the newest one is a
/// measurement rather than an inference, and costs a single file read.
///
/// Nothing else on disk describes the quota. File sizes, log growth and session
/// counts all correlate with *activity*, not with the limit, so this adapter
/// reports nothing rather than a number shaped like a reading.
public final class OpenAI_CodexAdapter: AIProviderAdapter, @unchecked Sendable {
    public let type: AIProviderType = .openAICodex

    private let detected = Locked(false)
    public var isDetected: Bool { detected.value }

    /// Rollouts to look back through before giving up.
    ///
    /// A session that ended without ever reaching the API carries no rate limit,
    /// and so does one whose turns all failed, so the newest file is not always
    /// the newest reading. Beyond a handful the figures are too old to be worth
    /// showing anyway.
    private static let rolloutLookback = 12

    /// How much of a rollout's tail to search.
    ///
    /// `token_count` is emitted once per turn, so the newest one is always near
    /// the end; reading a long session in full would be paying to parse a
    /// transcript for one line.
    private static let rolloutTailBytes = 1 << 20

    /// How many day directories to look back through.
    ///
    /// Bounds the walk without letting directory order decide which reading
    /// wins. A rollout older than this holds a figure too stale to display.
    static let dayDirectoryLookback = 30

    private let fileManager = FileManager.default
    private let homeDir = FileManager.default.homeDirectoryForCurrentUser
    private let identityLedger: AccountIdentityLedger

    public init(identityLedger: AccountIdentityLedger = .shared) {
        self.identityLedger = identityLedger
    }

    public func checkAvailability() async -> Bool {
        // Only `~/.codex` (or an explicit `CODEX_HOME`) says Codex is installed.
        // Any other AI CLI on this machine is a different provider's business.
        let found = !CodexAccountResolver.profiles().isEmpty
            || fileManager.fileExists(atPath: homeDir.appendingPathComponent(".codex").path)
        detected.value = found
        return found
    }

    /// Account, plan and organisation, decoded from the `id_token` the CLI
    /// stores in `auth.json`. Costs one file read and no network.
    private func identity(
        profile: CodexAccountResolver.Profile?
    ) -> (accountID: String?, email: String?, planName: String?)? {
        guard let profile,
              let claims = CodexAccountResolver.identityClaims(atPath: profile.authPath) else { return nil }
        return (
            accountID: claims.accountID ?? claims.email,
            email: claims.email,
            planName: CodexAccountResolver.planName(fromPlanType: claims.planType)
        )
    }

    /// One snapshot per `CODEX_HOME`, each read from that profile's own rollouts.
    public func fetchUsagePerAccount(forceSync: Bool) async throws -> [UsageSnapshot] {
        let profiles = CodexAccountResolver.profiles()
        guard !profiles.isEmpty else { return [try await fetchUsage(forceSync: forceSync)] }
        return profiles.map { snapshot(for: $0) }
    }

    /// `forceSync` needs no special case here.
    ///
    /// Codex's rollout is written by the running CLI as each turn completes, so
    /// re-reading it *is* the live read — there is no probe to skip a cache for,
    /// and nothing is held between calls that could go stale.
    public func fetchUsage(forceSync: Bool = false) async throws -> UsageSnapshot {
        guard let profile = CodexAccountResolver.profiles().first else {
            return Self.unknownSnapshot(account: nil)
        }
        return snapshot(for: profile)
    }

    func snapshot(for profile: CodexAccountResolver.Profile, now: Date = Date()) -> UsageSnapshot {
        let account = identity(profile: profile)
        guard let reading = Self.rateLimits(codexHome: profile.homeDirectory, now: now) else {
            return Self.unknownSnapshot(account: account)
        }
        guard Self.isAttributable(
            reading,
            to: account?.accountID,
            profile: profile,
            ledger: identityLedger,
            now: now
        ) else {
            // A rollout written before this account signed in describes the
            // previous one's spending. Its own record stays filed under its own
            // id; what is missing here is a reading for whoever is signed in
            // now, and "missing" is the only honest thing to show.
            return Self.unknownSnapshot(account: account)
        }
        return Self.snapshot(from: reading, account: account, now: now)
    }

    /// Whether this reading may be shown as the signed-in account's usage.
    ///
    /// A Codex rollout names no account — it carries the quota the API reported
    /// and nothing about whose quota it was. So the reading and the identity
    /// come from different files, and pairing them is an assumption: leave A's
    /// rollouts in place, sign in as B, and B's id gets stapled to A's spending
    /// without B having made a single request.
    ///
    /// The ledger supplies the missing evidence by watching for the switch
    /// itself. Before it has ever seen the profile there is no boundary and
    /// everything is attributable, which is right — never having looked is not
    /// evidence that anything changed.
    static func isAttributable(
        _ reading: RateLimits,
        to accountID: String?,
        profile: CodexAccountResolver.Profile,
        ledger: AccountIdentityLedger,
        now: Date = Date()
    ) -> Bool {
        // A rollout belongs to whoever was signed in when its session *started*.
        // A session that outlives a login switch keeps appending to the same
        // file, so its later writes are not the new account's work; without the
        // opening record there is no way to tell whose they are, and a guess
        // here relabels one account's usage as another's.
        guard let startedAt = reading.sessionStartedAt else { return false }
        guard let accountID, !accountID.isEmpty else { return true }
        return ledger.isAttributable(
            capturedAt: startedAt,
            provider: .openAICodex,
            profile: profile.homeDirectory,
            accountID: accountID,
            changedAt: credentialWrittenAt(profile: profile),
            now: now
        )
    }

    /// When this profile's credential was last written — the best available
    /// stand-in for when the account behind it changed.
    private static func credentialWrittenAt(profile: CodexAccountResolver.Profile) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: profile.authPath))?[.modificationDate] as? Date
    }

    /// Whether this profile's quota can actually be read right now.
    ///
    /// A brand-new `CODEX_HOME` has an `auth.json` and no rollouts yet, so the
    /// account is known while its usage is not.
    public static func hasReadableUsage(codexHome: String) -> Bool {
        rateLimits(codexHome: codexHome) != nil
    }

    // MARK: - Rate limit decoding

    /// One `{ used_percent, window_minutes, resets_at }` block.
    struct RateWindow: Equatable {
        /// Percentage still available, i.e. `100 - used_percent`.
        var remaining: Double
        var windowMinutes: Int?
        var resetsAt: Date?

        func countdown(now: Date = Date()) -> TimeInterval? {
            guard let resetsAt else { return nil }
            let interval = resetsAt.timeIntervalSince(now)
            return interval > 0 ? interval : nil
        }
    }

    /// The `rate_limits` payload of one `token_count` event.
    struct RateLimits: Equatable {
        var primary: RateWindow?
        var secondary: RateWindow?
        var planType: String?
        var creditBalance: Double?
        var hasUnlimitedCredits: Bool
        /// When the event that carried these figures was written.
        var capturedAt: Date
        /// When the session that produced them began, from the rollout's
        /// `session_meta`. `nil` where the rollout does not say — which is not
        /// the same as "just now", and is why a reading without it is withheld
        /// rather than guessed at.
        var sessionStartedAt: Date?
    }

    /// The newest rate limit Codex has recorded under this `CODEX_HOME`.
    ///
    /// "Newest" is decided by the measurement's own timestamp, not by which file
    /// it happened to be written into. Resuming yesterday's session appends
    /// today's turns to yesterday's date directory, so the first readable
    /// rollout in directory order is regularly *not* the latest reading — this
    /// used to return it anyway, and a fresh session started today would pin the
    /// bar to whatever quota it had recorded hours earlier.
    ///
    /// The scan is still bounded. Candidates are visited newest-modified first,
    /// and an event cannot postdate the file that holds it, so once the best
    /// reading so far is at least as new as the next candidate's modification
    /// time nothing further back can beat it. In the ordinary case — the newest
    /// file holding the newest turn — that is one file read.
    static func rateLimits(codexHome: String, now: Date = Date()) -> RateLimits? {
        var best: RateLimits?

        for candidate in rolloutCandidates(codexHome: codexHome).prefix(rolloutLookback) {
            if let best, best.capturedAt >= candidate.modified { break }
            guard let found = rateLimits(inRolloutAt: candidate.url, now: now) else { continue }
            if best == nil || found.capturedAt > best!.capturedAt {
                best = found
            }
        }
        return best
    }

    /// Session rollouts under `<CODEX_HOME>/sessions`, most recently written
    /// first, regardless of which date directory they live in.
    ///
    /// Codex files rollouts as `sessions/YYYY/MM/DD/rollout-*.jsonl`, and those
    /// names are zero-padded, so descending lexicographic order is descending
    /// order of session *start*. It is not descending order of session activity:
    /// a resumed session keeps its original path and goes on being written. The
    /// walk therefore uses the directory names only to bound how far back to
    /// look, and orders what it finds by modification time.
    ///
    /// The bound matters. Recursing the whole tree and stat-ing every file is
    /// thousands of syscalls every 45 seconds on a machine with months of
    /// sessions; `dayDirectoryLookback` caps it at the newest few weeks, which
    /// is well past the age at which a reading is worth showing at all.
    static func rolloutCandidates(
        codexHome: String,
        limit: Int = rolloutLookback
    ) -> [(url: URL, modified: Date)] {
        let root = URL(fileURLWithPath: codexHome).appendingPathComponent("sessions")

        // Older Codex builds wrote rollouts straight into `sessions`. They are
        // candidates like any other rather than automatically the freshest —
        // preferring them unconditionally is how a years-old rollout could
        // outrank today's.
        var found = rollouts(directlyIn: root)

        var daysVisited = 0
        outer: for year in descendingSubdirectories(of: root) {
            for month in descendingSubdirectories(of: year) {
                for day in descendingSubdirectories(of: month) {
                    found.append(contentsOf: rollouts(directlyIn: day))
                    daysVisited += 1
                    if daysVisited >= dayDirectoryLookback { break outer }
                }
            }
        }

        return Array(found.sorted { $0.modified > $1.modified }.prefix(limit))
    }

    /// Session rollouts, most recently written first.
    static func rolloutFiles(codexHome: String, limit: Int = rolloutLookback) -> [URL] {
        rolloutCandidates(codexHome: codexHome, limit: limit).map(\.url)
    }

    /// Immediate subdirectories, newest-named first.
    private static func descendingSubdirectories(of directory: URL) -> [URL] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names
            .filter { !$0.hasPrefix(".") }
            .sorted(by: >)
            .map { directory.appendingPathComponent($0, isDirectory: true) }
            .filter { AccountFileReader.directoryExists($0.path) }
    }

    /// The rollouts sitting directly in one directory, with their write times.
    ///
    /// A day holds a handful of files, so stat-ing them is bounded — unlike
    /// stat-ing every rollout ever written.
    private static func rollouts(directlyIn directory: URL) -> [(url: URL, modified: Date)] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names
            .filter { $0.hasPrefix("rollout-") && $0.hasSuffix(".jsonl") }
            .map { name -> (url: URL, modified: Date) in
                let url = directory.appendingPathComponent(name)
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return (url, modified)
            }
    }

    /// The last usable `rate_limits` in one rollout's tail.
    ///
    /// A rollout carries a `rate_limits` block on every turn, but the block is
    /// all-nil until the API has actually reported a limit — a fresh session on
    /// an unmetered plan writes nothing but nulls. Those are skipped rather than
    /// read as "no usage".
    static func rateLimits(inRolloutAt url: URL, now: Date = Date()) -> RateLimits? {
        guard let text = tail(of: url, bytes: rolloutTailBytes) else { return nil }
        let startedAt = sessionStart(inRolloutAt: url)

        for line in text.split(separator: "\n").reversed() {
            guard line.contains("rate_limits") else { continue }
            guard let data = line.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let limits = rateLimits(fromEvent: event, now: now, sessionStartedAt: startedAt)
            else { continue }
            return limits
        }
        return nil
    }

    /// When the session began, from the `session_meta` Codex writes first.
    ///
    /// Read from the head rather than the tail: a session that has been running
    /// for hours has pushed its opening line far out of the window the rate
    /// limit is read from, and that opening line is the only record of who was
    /// signed in when the work started.
    ///
    /// Read a line at a time rather than a fixed prefix. `session_meta` carries
    /// the session's full `base_instructions`, so the line is tens of kilobytes
    /// and growing — 22KB on Codex 0.153, 47KB on 0.148. A fixed-size read cuts
    /// it mid-JSON, the parse fails, and the reading is withheld as
    /// unattributable: every rollout on disk stops counting at once, which is
    /// exactly what a fixed 8KB prefix did here.
    static func sessionStart(inRolloutAt url: URL) -> Date? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var pending = Data()
        var consumed = 0

        while consumed < rolloutHeadBytes {
            guard let chunk = try? handle.read(upToCount: rolloutHeadChunkBytes),
                  !chunk.isEmpty else { break }
            consumed += chunk.count
            pending.append(chunk)

            while let newline = pending.firstIndex(of: 0x0A) {
                let line = Data(pending[pending.startIndex..<newline])
                pending = Data(pending[pending.index(after: newline)...])
                if let started = sessionStart(inLine: line) { return started }
            }
        }
        // A rollout whose only line has not been terminated yet: the session is
        // still being written, and its opening record is complete regardless.
        return sessionStart(inLine: pending)
    }

    /// The session's opening timestamp, if this line is the `session_meta`.
    private static func sessionStart(inLine line: Data) -> Date? {
        guard !line.isEmpty,
              let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              (event["type"] as? String) == "session_meta"
        else { return nil }
        return timestamp(event["timestamp"])
    }

    /// How far into a rollout to look for `session_meta`.
    ///
    /// It is the first line Codex writes, so this only ever bounds the damage
    /// done by a file that does not carry one at all.
    private static let rolloutHeadBytes = 1 << 20

    /// Read granularity while looking for the end of that line. Large enough to
    /// take the ordinary `session_meta` in one read, small enough that a rollout
    /// without one is not paid for a megabyte at a time.
    private static let rolloutHeadChunkBytes = 64 * 1024

    /// `{ "timestamp": ..., "payload": { "type": "token_count", "rate_limits": {...} } }`,
    /// with older Codex builds writing the payload at the top level.
    static func rateLimits(
        fromEvent event: [String: Any],
        now: Date = Date(),
        sessionStartedAt: Date? = nil
    ) -> RateLimits? {
        let payload = event["payload"] as? [String: Any] ?? event
        guard let raw = payload["rate_limits"] as? [String: Any] else { return nil }

        let primary = window(raw["primary"])
        let secondary = window(raw["secondary"])
        let credits = raw["credits"] as? [String: Any] ?? [:]
        let balance = numeric(credits["balance"])
        let unlimited = (credits["unlimited"] as? Bool) ?? false

        // A block whose every window is null describes nothing; reporting it as
        // full quota would invent the very reading this adapter refuses to make.
        guard primary != nil || secondary != nil || unlimited || balance != nil else { return nil }

        return RateLimits(
            primary: primary,
            secondary: secondary,
            planType: raw["plan_type"] as? String,
            creditBalance: balance,
            hasUnlimitedCredits: unlimited,
            capturedAt: timestamp(event["timestamp"]) ?? now,
            sessionStartedAt: sessionStartedAt
        )
    }

    private static func window(_ raw: Any?) -> RateWindow? {
        guard let object = raw as? [String: Any],
              let used = numeric(object["used_percent"]) else { return nil }

        var resetsAt: Date?
        if let epoch = numeric(object["resets_at"]) {
            resetsAt = Date(timeIntervalSince1970: epoch)
        } else if let text = object["resets_at"] as? String {
            resetsAt = timestamp(text)
        } else if let seconds = numeric(object["resets_in_seconds"]) {
            resetsAt = Date().addingTimeInterval(seconds)
        }

        return RateWindow(
            remaining: max(0.0, min(100.0, 100.0 - used)),
            windowMinutes: numeric(object["window_minutes"]).map { Int($0) },
            resetsAt: resetsAt
        )
    }

    // MARK: - Snapshot assembly

    static func snapshot(
        from limits: RateLimits,
        account: (accountID: String?, email: String?, planName: String?)?,
        now: Date = Date()
    ) -> UsageSnapshot {
        var quotas: [ModelQuotaItem] = []
        if let primary = limits.primary {
            quotas.append(quotaItem(primary, fallbackName: L10n.codexPrimaryLimit.text, now: now))
        }
        if let secondary = limits.secondary {
            quotas.append(quotaItem(secondary, fallbackName: L10n.codexSecondaryLimit.text, now: now))
        }
        if let credit = creditItem(limits) {
            quotas.append(credit)
        }

        return UsageSnapshot(
            provider: .openAICodex,
            hourlyRemainingPercentage: limits.primary?.remaining ?? 100.0,
            hourlyResetCountdown: limits.primary?.countdown(now: now),
            weeklyRemainingPercentage: limits.secondary?.remaining,
            weeklyResetCountdown: limits.secondary?.countdown(now: now),
            modelQuotas: quotas,
            accountEmail: account?.email,
            // The rollout records the plan the request was billed against, which
            // is fresher than the plan baked into a token issued weeks ago.
            planName: CodexAccountResolver.planName(fromPlanType: limits.planType) ?? account?.planName,
            lastUpdated: limits.capturedAt,
            strategyUsed: .localFileCache,
            accountID: account?.accountID,
            sourceID: "codex.cli",
            capturedAt: limits.capturedAt,
            // The ring was captioned "세션 쿼터" while the row below it said
            // "5시간 한도" for the same number. Codex declares the window, so
            // there is no reason for the headline to be the vaguer of the two.
            hourlyQuotaName: limits.primary?.windowMinutes.map(windowLabel(minutes:)),
            hourlyResetAt: limits.primary?.resetsAt,
            weeklyResetAt: limits.secondary?.resetsAt
        )
    }

    private static func quotaItem(
        _ window: RateWindow,
        fallbackName: String,
        now: Date
    ) -> ModelQuotaItem {
        let label = window.windowMinutes.map(windowLabel(minutes:))
        return ModelQuotaItem(
            name: label ?? fallbackName,
            remainingPercentage: window.remaining,
            quotaType: label ?? fallbackName,
            resetCountdown: window.countdown(now: now),
            resetAt: window.resetsAt
        )
    }

    /// Codex declares its windows in minutes and changes them by plan — the free
    /// tier is metered over 30 days where a paid one is metered over 5 hours — so
    /// the label is derived rather than assumed.
    static func windowLabel(minutes: Int) -> String {
        if minutes % 1440 == 0, minutes >= 1440 {
            let days = minutes / 1440
            return days % 7 == 0 ? L10n.codexWindowWeeks(days / 7).text : L10n.codexWindowDays(days).text
        }
        if minutes % 60 == 0, minutes >= 60 { return L10n.codexWindowHours(minutes / 60).text }
        return L10n.codexWindowMinutes(minutes).text
    }

    private static func creditItem(_ limits: RateLimits) -> ModelQuotaItem? {
        if limits.hasUnlimitedCredits {
            return ModelQuotaItem(
                name: L10n.codexCredits.text,
                remainingPercentage: 100.0,
                quotaType: "Credits",
                paceText: L10n.unlimited.text
            )
        }
        // A balance is an amount, not a proportion: there is no ceiling to
        // measure it against, so it earns a row only as text.
        guard let balance = limits.creditBalance else { return nil }
        return ModelQuotaItem(
            name: L10n.codexCredits.text,
            remainingPercentage: balance > 0 ? 100.0 : 0.0,
            quotaType: "Credits",
            paceText: L10n.codexBalance(Int(balance)).text
        )
    }

    /// Shown when no rollout carries a rate limit yet. Reports full quota with
    /// `.simulated`, so the strategy badge admits the figure is a placeholder
    /// rather than a reading.
    private static func unknownSnapshot(
        account: (accountID: String?, email: String?, planName: String?)?
    ) -> UsageSnapshot {
        UsageSnapshot(
            provider: .openAICodex,
            hourlyRemainingPercentage: 0.0,
            hourlyResetCountdown: nil,
            weeklyRemainingPercentage: nil,
            weeklyResetCountdown: nil,
            modelQuotas: [],
            accountEmail: account?.email,
            planName: account?.planName,
            strategyUsed: .simulated,
            accountID: account?.accountID,
            sourceID: "codex.cli"
        )
    }

    // MARK: - Reading

    /// The last `bytes` of a file, decoded as UTF-8 with the leading partial
    /// line dropped.
    private static func tail(of url: URL, bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()).map(Int.init) ?? 0
        let offset = max(0, size - bytes)
        try? handle.seek(toOffset: UInt64(offset))
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        // A seek into the middle of the file lands mid-line; that fragment is
        // not parseable JSON and would only ever be discarded.
        guard offset > 0, let newline = text.firstIndex(of: "\n") else { return text }
        return String(text[text.index(after: newline)...])
    }

    /// JSON numbers arrive as `Int` or `Double` depending on how they were
    /// written, and a percentage of `0` must stay a value rather than become nil.
    private static func numeric(_ raw: Any?) -> Double? {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        return nil
    }

    /// `2026-08-31T07:33:29.922Z`.
    private static func timestamp(_ raw: Any?) -> Date? {
        guard let text = raw as? String else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
