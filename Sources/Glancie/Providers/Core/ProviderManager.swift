import SwiftUI
import Combine
import AppKit

@MainActor
public final class ProviderManager: ObservableObject {
    public static let shared = ProviderManager()
    
    /// What the bar shows for each provider: the figures of whichever account is
    /// currently in play. Derived from `accountSnapshots`.
    @Published public var snapshots: [AIProviderType: UsageSnapshot] = [:]
    /// The real store — quota is a property of the account, so it is keyed by
    /// account, and a provider with two signed-in accounts holds two readings.
    @Published public var accountSnapshots: [AIProviderType: [String: UsageSnapshot]] = [:]
    /// Accounts whose files are being written right now (CLI activity).
    @Published public private(set) var runningAccounts: Set<RunningKey> = []
    /// Accounts whose desktop app or IDE is open right now.
    @Published public private(set) var runningAppAccounts: Set<RunningKey> = []
    @Published public var activeProviders: [AIProviderType] = []
    @Published public var detectedProviders: Set<AIProviderType> = []
    @Published public var activeInUseProviders: Set<AIProviderType> = []
    @Published public var selectedProvider: AIProviderType? = nil {
        didSet {
            if let provider = selectedProvider {
                Task {
                    await self.refreshProvider(provider, forceSync: true)
                }
            }
        }
    }
    @Published public var isRefreshing: Bool = false
    
    private var adapters: [AIProviderType: AIProviderAdapter] = [:]
    private var timer: AnyCancellable?
    private let scanner: ZeroConfigScanner
    private let fsEventsWatcher = FSEventsWatcher()
    private var inUseTasks: [AIProviderType: Task<Void, Never>] = [:]
    private let accountRegistry: AccountRegistry
    private let usageStore: AccountUsageStore
    private var appPresenceObservers: [NSObjectProtocol] = []
    
    /// Throttling safeguard to completely prevent 429 Rate Limit issues on CLI/API probes
    private var lastFetchTime: [AIProviderType: Date] = [:]
    private let minCooldownInterval: TimeInterval = 45.0

    private var lastOnDemandRefresh: [AIProviderType: Date] = [:]
    /// Triggers that arrived inside the floor and are waiting it out.
    private var pendingOnDemand: [AIProviderType: Task<Void, Never>] = [:]
    /// The fetch already running for a provider, if any. See `refreshProvider`.
    private var inFlightRefreshes: [AIProviderType: Task<Void, Never>] = [:]
    /// Accounts a fetch reported that the registry had not listed, so the
    /// catch-up rescan fires once per switch rather than once per refresh.
    private var pendingRescanAccounts: [AIProviderType: Set<String>] = [:]

    private let logger = GlancieLog.provider
    
    public convenience init() {
        self.init(adapters: ZeroConfigScanner().allAdapters, accountRegistry: .shared,
                  usageStore: .shared, startMonitoring: true)
    }

    /// Explicit dependencies keep account transitions and failed reads testable
    /// without starting real CLI processes or touching the user's preferences.
    init(adapters: [AIProviderAdapter], accountRegistry: AccountRegistry,
         usageStore: AccountUsageStore, startMonitoring: Bool = false) {
        self.scanner = ZeroConfigScanner(adapters: adapters)
        self.accountRegistry = accountRegistry
        self.usageStore = usageStore
        // Register all available adapters
        for adapter in scanner.allAdapters {
            self.adapters[adapter.type] = adapter
        }
        
        // Immediate synchronous activeProviders initialization
        if let saved = GlanciePreferences.shared.enabledProviders, !saved.isEmpty {
            self.activeProviders = saved
        } else {
            self.activeProviders = [.claudeCode, .openAICodex, .antigravity]
        }
        
        setupDefaultSnapshots()
        
        guard startMonitoring else { return }
        Task {
            await initializeScanner()
            startFSEventsWatching()
            startAppPresenceObservation()
            startPeriodicPolling()
        }
    }

    /// Tracks which provider apps are open.
    ///
    /// The workspace posts launches and terminations, so there is nothing to
    /// poll — a desktop app's presence is a fact the system already publishes.
    private func startAppPresenceObservation() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshRunningApps() }
            }
            appPresenceObservers.append(token)
        }
        refreshRunningApps()
    }
    
    /// Placeholder snapshots so the bar has geometry before the first fetch lands.
    ///
    /// These carry no account: an invented address would be indistinguishable
    /// from a real login once the detail screen starts showing who is signed in,
    /// and `.simulated` keeps the strategy badge honest about the numbers too.
    private func setupDefaultSnapshots() {
        for type in AIProviderType.allCases {
            snapshots[type] = UsageSnapshot.simulatedFallback(for: type)
        }
    }
    
    // MARK: - Account attribution

    /// Re-runs account discovery. Cheap and read-only, so the settings screen can
    /// offer it directly after the user signs in or switches profiles.
    public func rescanAccounts() async {
        await accountRegistry.refreshAccounts()
        fsEventsWatcher.updateAccountPaths(accountRegistry.activityPaths)
        refreshRunningApps()
    }

    public func accounts(for provider: AIProviderType) -> [ResolvedAccount] {
        accountRegistry.accounts(for: provider)
    }

    /// The live reading for one account, if this machine can read it.
    public func snapshot(for provider: AIProviderType, accountID: String) -> UsageSnapshot? {
        accountSnapshots[provider]?[accountID]
    }

    /// The best figures available for an account: the live reading, else the
    /// last one ever recorded, wound forward so no expired countdown is shown.
    public func bestKnownSnapshot(for provider: AIProviderType, accountID: String) -> UsageSnapshot? {
        snapshot(for: provider, accountID: accountID)
            ?? usageStore.snapshot(provider: provider, accountID: accountID)
    }

    /// The account whose figures the bar is showing for this provider.
    public func displayedAccount(for provider: AIProviderType) -> ResolvedAccount? {
        guard let accountID = snapshots[provider]?.accountID else { return nil }
        return accountRegistry.account(for: provider, id: accountID)
    }

    /// Fills in whatever an adapter could not determine for itself.
    ///
    /// An adapter that reports per account already knows which account each
    /// snapshot belongs to and keeps its own id. Only the provider-level
    /// adapters land here.
    private func attribute(_ snapshot: UsageSnapshot, for provider: AIProviderType) -> UsageSnapshot {
        // Codex without an identity is API-key or unknown mode. There is no
        // id_token behind those figures, so whichever account the registry
        // happens to list does not own them, and stamping its address on the
        // reading invents provenance the fetch never established.
        if provider == .openAICodex, snapshot.accountID == nil { return snapshot }
        return Self.attributed(
            snapshot,
            lookup: { [accountRegistry] id in accountRegistry.account(for: provider, id: id) },
            fallback: { [accountRegistry] in accountRegistry.attributionAccount(for: provider) },
            primarySourceID: accountRegistry.primarySourceID(for: provider)
        )
    }

    /// The attribution rule itself, with the registry passed in.
    ///
    /// A snapshot that names an account gets that account's details or none at
    /// all. Falling back to the provider's attribution account for an id the
    /// registry has not caught up with is how a freshly switched-to login was
    /// shown under the outgoing account's address and plan: the id was right,
    /// and every human-readable field beside it belonged to somebody else.
    static func attributed(
        _ snapshot: UsageSnapshot,
        lookup: (String) -> ResolvedAccount?,
        fallback: () -> ResolvedAccount?,
        primarySourceID: String?
    ) -> UsageSnapshot {
        var result = snapshot

        let account = result.accountID.map(lookup) ?? fallback()
        guard let account else { return result }

        if result.accountID == nil {
            result.accountID = account.id
        }
        if result.sourceID == nil {
            result.sourceID = account.sources.first { $0.id == primarySourceID }?.id
                ?? account.sources.first?.id
        }
        if result.accountEmail == nil {
            result.accountEmail = account.email
        }
        if result.planName == nil {
            result.planName = account.planName
        }
        return result
    }

    /// Files a fetch result under each account it describes and refreshes what
    /// the bar shows for that provider.
    /// Internal rather than private so account transitions can be driven
    /// directly in a test, without a real adapter or a timer.
    func apply(_ fetched: [UsageSnapshot], for provider: AIProviderType) {
        // Stamped here rather than in each adapter: the adapters have many
        // return points and only one of them needs to be forgotten for a
        // reading to outlive its key.
        let fingerprint = adapters[provider]?.credentialFingerprint
        let stamped = fetched.map { snapshot -> UsageSnapshot in
            var copy = snapshot
            copy.credentialFingerprint = fingerprint
            return copy
        }
        let merged = Self.merged(
            attributed: stamped.map { attribute($0, for: provider) },
            into: accountSnapshots[provider] ?? [:],
            knownAccountIDs: Set(accountRegistry.accounts(for: provider).map(\.id)),
            registryHasScanned: accountRegistry.lastScanDate != nil,
            storedSnapshot: { [usageStore] id in
                usageStore.snapshot(provider: provider, accountID: id)
            }
        )

        for snapshot in merged.recorded {
            usageStore.record(snapshot)
        }
        if let unattributed = merged.unattributed {
            snapshots[provider] = Self.preferringLastMeasurement(
                unattributed,
                over: snapshots[provider]
            )
        }

        accountSnapshots[provider] = merged.byAccount
        // Only a fetch that actually named accounts may pick the headline from
        // them. When it named none — a logout, or an adapter that can no longer
        // read anything — its own answer is the most current thing there is,
        // and rows left over from the last fetch must not speak over it.
        if !merged.reported.isEmpty,
           let representative = representativeSnapshot(for: provider, among: merged.byAccount) {
            snapshots[provider] = representative
        }
        noteUnregisteredAccounts(merged.reported, for: provider)
    }

    /// Folds one fetch's snapshots into what is already filed per account.
    ///
    /// Pure, and separated from the registry and the store for exactly that
    /// reason: every bug this had — a switched-to account being filtered away, a
    /// duplicate profile's older reading winning on array order — lived in these
    /// few lines and could not be reached by a test.
    static func merged(
        attributed: [UsageSnapshot],
        into existing: [String: UsageSnapshot],
        knownAccountIDs: Set<String>,
        registryHasScanned: Bool = true,
        storedSnapshot: (String) -> UsageSnapshot?
    ) -> (
        byAccount: [String: UsageSnapshot],
        reported: Set<String>,
        recorded: [UsageSnapshot],
        unattributed: UsageSnapshot?
    ) {
        var byAccount = existing
        var reported: Set<String> = []
        /// Accounts this fetch produced an actual measurement for.
        var measured: Set<String> = []
        var recorded: [UsageSnapshot] = []
        var unattributed: UsageSnapshot?

        for snapshot in attributed {
            guard let accountID = snapshot.accountID else {
                // Nothing to file it under; it can still drive the bar.
                unattributed = snapshot
                continue
            }

            let resolved = preferringLastMeasurement(
                snapshot,
                over: byAccount[accountID] ?? storedSnapshot(accountID)
            )
            // Two profiles can be signed into the same account, so this key can
            // be written more than once in a single fetch. Array order says
            // nothing about which reading is current; `capturedAt` does — the
            // same rule the persistent store already applies.
            //
            // Only among measurements, though. A blank is stamped at the moment
            // it is made, so comparing its `capturedAt` against a real reading's
            // always hands it the win, and one unreadable profile would erase
            // what the profile beside it had just measured for the same account.
            if resolved.unavailableReason == nil {
                let standing = byAccount[accountID]
                byAccount[accountID] = standing?.unavailableReason == nil
                    ? newer(resolved, than: standing)
                    : resolved
                measured.insert(accountID)
            } else if !measured.contains(accountID) {
                // A blank still replaces what was stored — that is how a logout
                // clears the figures — but never a reading from this same fetch.
                byAccount[accountID] = resolved
            }
            reported.insert(accountID)
            recorded.append(snapshot)
        }

        // An account that has since been removed must not linger with figures
        // that will silently age into a lie.
        //
        // What the registry knows is a scan old, and the adapters re-read their
        // profiles on every fetch, so a login switched between scans arrives
        // here as an id the registry has never heard of. Dropping it left the
        // outgoing account on screen and threw away the only current reading;
        // the accounts just reported are therefore known by definition.
        // Whether the registry has scanned is a fact it publishes, so ask it
        // rather than inferring it from an empty list. The two are not the same
        // thing: signing out of the last account also empties the list, and
        // treating that as "not scanned yet" left the departed account's
        // figures on screen with nothing left to remove them.
        if registryHasScanned {
            byAccount = byAccount.filter {
                knownAccountIDs.contains($0.key) || reported.contains($0.key)
            }
        }

        return (byAccount, reported, recorded, unattributed)
    }

    /// Keeps the last real reading on screen through a transient failure.
    ///
    /// A rejected key, a 429 or a dropped connection tells us nothing new about
    /// the quota — only that we could not ask. Replacing a measurement with a
    /// blank in that case loses information the user still wants; keeping it
    /// costs nothing, because the reading carries its own `capturedAt` and goes
    /// visibly stale on its own. Being signed out or having no measurable quota
    /// is different: those are statements about the account, so they replace.
    static func preferringLastMeasurement(
        _ incoming: UsageSnapshot,
        over previous: UsageSnapshot?
    ) -> UsageSnapshot {
        guard let reason = incoming.unavailableReason, reason.isTransient,
              let previous, previous.unavailableReason == nil else { return incoming }
        // A refusal only says "we could not ask" while it is the same key being
        // refused. Once the credential has changed, the reading behind it
        // belongs to the account that key named, and showing it under the new
        // one would attribute a stranger's balance. Unknown on either side is
        // not a mismatch: providers without a credential never fill this in.
        if let mine = incoming.credentialFingerprint,
           let theirs = previous.credentialFingerprint,
           mine != theirs {
            return incoming
        }
        return previous
    }

    /// The more recent of two readings for the same account.
    private static func newer(_ incoming: UsageSnapshot, than existing: UsageSnapshot?) -> UsageSnapshot {
        guard let existing else { return incoming }
        return incoming.capturedAt >= existing.capturedAt ? incoming : existing
    }

    /// What a thrown fetch leaves on screen.
    ///
    /// Adapters here answer a refused read with `.unavailable(reason:)`, but a
    /// CLI probe or a decode can still throw, and swallowing that left a
    /// reading minutes old looking freshly measured — `isStale` had nothing to
    /// go on. The measurement stays, because it is still the last thing
    /// actually measured, but it is marked so the card can say the refresh
    /// failed.
    ///
    /// Unless the account behind it is gone. Then it describes nobody, and the
    /// same rule that stops a changed key inheriting a balance applies here.
    private func applyFetchFailure(_ error: Error, for provider: AIProviderType) async {
        await accountRegistry.refreshAccounts()
        let live = Set(accountRegistry.accounts(for: provider).map(\.id))

        if let standing = snapshots[provider], let id = standing.accountID, !live.contains(id) {
            accountSnapshots[provider]?[id] = nil
            snapshots[provider] = .unavailable(
                for: provider,
                reason: .notConfigured,
                accountID: accountRegistry.attributionAccount(for: provider)?.id
            )
            return
        }

        guard var standing = snapshots[provider], standing.unavailableReason == nil else { return }
        standing.fetchError = (error as? LocalizedError)?.errorDescription
            ?? L10n.errorRefreshFailed.text
        snapshots[provider] = standing
    }

    /// Catches the registry up *before* a fetch's figures are filed.
    ///
    /// The adapters re-read their profiles on every fetch while the registry is
    /// only as fresh as its last scan, so a login switched in between arrives
    /// here as an id the registry has never listed. Filing first and rescanning
    /// after left the incoming account's rows unnamed and the outgoing
    /// account's figures on the bar until the rescan landed — a visible wrong
    /// state, for the sake of skipping a scan that costs nothing next to the
    /// fetch that just finished.
    private func discoverAccountsBeforeFiling(
        _ fetched: [UsageSnapshot],
        for provider: AIProviderType
    ) async {
        let known = Set(accountRegistry.accounts(for: provider).map(\.id))
        let reported = Set(fetched.compactMap(\.accountID))
        // Either direction is news. An id the registry has never listed is a
        // login it missed; nothing at all where it still lists accounts is the
        // shape of a logout, and without the rescan the departed account keeps
        // its row because the filter has only the stale list to check against.
        let appeared = !reported.subtracting(known).isEmpty
        let vanished = fetched.isEmpty && !known.isEmpty
        guard appeared || vanished else { return }
        await accountRegistry.refreshAccounts()
    }

    /// Catches the registry up when a fetch reports an account it has never
    /// listed, which is what a login switch between scans looks like from here.
    ///
    /// Rate-limited by `isScanning` and by only firing on genuinely new ids, so
    /// a provider that permanently reports an unresolvable account cannot turn
    /// every refresh into a rescan.
    private func noteUnregisteredAccounts(_ reported: Set<String>, for provider: AIProviderType) {
        let known = Set(accountRegistry.accounts(for: provider).map(\.id))
        let unregistered = reported.subtracting(known)
        guard !unregistered.isEmpty, unregistered != pendingRescanAccounts[provider] else { return }

        pendingRescanAccounts[provider] = unregistered
        logger.debug(
            "[\(provider.rawValue, privacy: .public)] fetch reported \(unregistered.count) unlisted account(s); rescanning"
        )
        Task { @MainActor in
            await self.accountRegistry.refreshAccounts()
            self.pendingRescanAccounts[provider] = nil
        }
    }

    /// Which account's figures the single bar segment should show.
    ///
    /// The account that is currently working wins — that is the quota the user
    /// is spending right now, and it is exactly what the running-source signal
    /// is for. Otherwise the most recently measured account.
    private func representativeSnapshot(
        for provider: AIProviderType,
        among byAccount: [String: UsageSnapshot]
    ) -> UsageSnapshot? {
        let running = byAccount.values.filter {
            $0.accountID.map { id in isAccountRunning(provider: provider, accountID: id) } ?? false
        }
        let candidates = running.isEmpty ? Array(byAccount.values) : running
        return candidates.max { $0.capturedAt < $1.capturedAt }
    }

    public func isProviderDetected(_ provider: AIProviderType) -> Bool {
        return detectedProviders.contains(provider) || (adapters[provider]?.isDetected ?? false)
    }

    // MARK: - Running state

    /// Identifies one account's activity, independent of its quota.
    public struct RunningKey: Hashable {
        public let provider: AIProviderType
        public let accountID: String

        public init(provider: AIProviderType, accountID: String) {
            self.provider = provider
            self.accountID = accountID
        }
    }

    public func isProviderInUse(_ provider: AIProviderType) -> Bool {
        return activeInUseProviders.contains(provider)
    }

    /// Whether this specific account is working right now.
    public func isAccountRunning(provider: AIProviderType, accountID: String) -> Bool {
        runningAccounts.contains(RunningKey(provider: provider, accountID: accountID))
            || runningAppAccounts.contains(RunningKey(provider: provider, accountID: accountID))
    }

    /// Whether any app signed into one of this provider's accounts is open.
    ///
    /// Separate from `isProviderInUse`, and deliberately so: a desktop app being
    /// open says the provider is *reachable*, not that it is generating. The two
    /// answers get two badges rather than one blurred one.
    public func isAppRunning(_ provider: AIProviderType) -> Bool {
        runningAppAccounts.contains { $0.provider == provider }
    }

    /// The apps this account is signed into that are open right now.
    public func runningApps(for account: ResolvedAccount) -> [AccountSource] {
        let open = Self.runningBundleIdentifiers()
        return account.sources.filter { source in
            source.bundleIdentifiers.contains { open.contains($0) }
        }
    }

    public func initializeScanner() async {
        // Accounts resolve before the first fetch so every snapshot that comes
        // back can be filed under the account it belongs to.
        await accountRegistry.refreshAccounts()

        let detected = await scanner.scanAvailableProviders()
        var detectedSet = Set<AIProviderType>()
        for adapter in detected {
            adapters[adapter.type] = adapter
            detectedSet.insert(adapter.type)
        }
        self.detectedProviders = detectedSet
        
        // If user hasn't customized yet, select only detected providers and persist
        if GlanciePreferences.shared.enabledProviders == nil || !GlanciePreferences.shared.hasCustomizedProviders {
            let detectedList = AIProviderType.allCases.filter { detectedSet.contains($0) }
            if !detectedList.isEmpty {
                self.activeProviders = detectedList
                GlanciePreferences.shared.enabledProviders = detectedList
            }
        }
        
        await refreshAll(forceSync: true)
    }
    
    /// Teaches the watcher about alternate profile directories.
    ///
    /// A second account lives in its own home (`~/.claude-work`, `~/.codex-b`),
    /// so without this the live-activity dot would stay dark for every account
    /// but the default one.
    private func registerAlternateProfilePaths() {
        let canonical: [AIProviderType: String] = [
            .claudeCode: AccountFileReader.home.appendingPathComponent(".claude").path,
            .openAICodex: AccountFileReader.home.appendingPathComponent(".codex").path
        ]
        let discovered: [AIProviderType: [String]] = [
            .claudeCode: AccountFileReader.siblingProfileDirectories(prefix: ".claude"),
            .openAICodex: AccountFileReader.siblingProfileDirectories(prefix: ".codex")
        ]

        for (provider, paths) in discovered {
            let extras = paths.filter { $0 != canonical[provider] }
            guard !extras.isEmpty else { continue }

            AIActivityRuleRegistry.shared.updateRule(for: provider) { rule in
                for path in extras where !rule.relativeRootPaths.contains(path) {
                    rule.relativeRootPaths.append(path)
                }
            }
            logger.info("[\(provider.rawValue, privacy: .public)] watching \(extras.count) alternate profile path(s)")
        }
    }

    /// FSEvents watcher marks real-time active in-use state (without fabricating usage numbers)
    private func startFSEventsWatching() {
        registerAlternateProfilePaths()

        fsEventsWatcher.updateAccountPaths(accountRegistry.activityPaths)

        fsEventsWatcher.startWatching { [weak self] signals in
            Task { @MainActor in
                guard let self = self else { return }
                for signal in signals where self.activeProviders.contains(signal.provider) {
                    self.markInUse(signal)
                }
            }
        }
    }
    
    /// Real-time streaming indicator: activates on FSEvent and settles 3 seconds
    /// after writes stop.
    ///
    /// Tracked per account, because that is what the signal actually means — a
    /// write under one profile home says nothing about the other account's
    /// session. The provider-level flag the bar uses is derived from it.
    private func markInUse(_ signal: ActivitySignal) {
        let provider = signal.provider

        if !activeInUseProviders.contains(provider) {
            logger.debug("[\(provider.rawValue, privacy: .public)] streaming active")
            _ = withAnimation(JellySprings.layout) {
                activeInUseProviders.insert(provider)
            }

            // Read now rather than at the end of the turn. A turn can stream for
            // minutes, and the settling refresh cannot fire until it stops — so
            // waiting for it means showing the quota from before the session
            // started for as long as the session runs.
            Task { @MainActor in
                await self.refreshOnDemand([provider], trigger: .activity)
            }
        }

        if let accountID = signal.accountID {
            let key = RunningKey(provider: provider, accountID: accountID)
            if !runningAccounts.contains(key) {
                _ = withAnimation(JellySprings.layout) { runningAccounts.insert(key) }
                // The account that is spending quota right now is the one the bar
                // should be showing.
                refreshRepresentative(for: provider)
            }
        }

        // Cancel any pending reset and set a lightweight 3-second settling timer
        inUseTasks[provider]?.cancel()
        inUseTasks[provider] = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds idle settling
                guard !Task.isCancelled else { return }

                logger.debug("[\(provider.rawValue, privacy: .public)] streaming settled")
                withAnimation(JellySprings.layout) {
                    self.activeInUseProviders.remove(provider)
                    self.runningAccounts = self.runningAccounts.filter { $0.provider != provider }
                }

                // A turn just ended, so the quota just moved. Waiting for the
                // next poll would show the figure from before it.
                //
                // Detached on purpose: this task is cancelled by the next write
                // event, and a busy session produces one every few seconds — a
                // probe started here would be killed before it could answer.
                Task { @MainActor in
                    await self.refreshOnDemand([provider], trigger: .activity)
                }
            } catch {
                // Cancelled cleanly by new incoming write event - no duplicate logs
            }
        }
    }

    /// Recomputes which account the bar segment speaks for.
    private func refreshRepresentative(for provider: AIProviderType) {
        guard let byAccount = accountSnapshots[provider],
              let representative = representativeSnapshot(for: provider, among: byAccount) else { return }
        snapshots[provider] = representative
    }

    /// Bundle ids of everything currently open.
    static func runningBundleIdentifiers() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    /// Refreshes which accounts have a desktop app or IDE open.
    ///
    /// A GUI app announces itself to the workspace, so this is a direct answer
    /// where file-watching an Electron container would only ever be an inference
    /// over cache churn.
    private func refreshRunningApps() {
        let open = Self.runningBundleIdentifiers()
        var found: Set<RunningKey> = []

        for provider in AIProviderType.allCases {
            for account in accountRegistry.accounts(for: provider) {
                let isOpen = account.sources.contains { source in
                    source.bundleIdentifiers.contains { open.contains($0) }
                }
                if isOpen {
                    found.insert(RunningKey(provider: provider, accountID: account.id))
                }
            }
        }

        guard found != runningAppAccounts else { return }
        withAnimation(JellySprings.layout) { runningAppAccounts = found }
    }

    /// Why a live read was asked for.
    ///
    /// The floor is a storm guard, not a schedule. A person cannot open the menu
    /// twice a second, and detected streaming has to reach a live read quickly
    /// or the figure on screen describes the session before this one — so both
    /// are short, and what actually bounds the cost is that each trigger fires
    /// once per burst rather than once per write.
    public enum RefreshTrigger {
        /// The menu was opened, or a provider was drilled into.
        case userAction
        /// Streaming was detected, or the turn that produced it finished.
        case activity

        var floor: TimeInterval {
            switch self {
            case .userAction: return 10
            case .activity: return 10
            }
        }
    }

    /// A live read prompted by something that happened rather than by the clock.
    ///
    /// A turn that just finished, the menu being opened, a provider being
    /// selected: each is evidence the cached figure is behind, which is exactly
    /// the case the periodic cooldown is wrong about. These read past every
    /// cache; the floor only stops repeated triggers from becoming a storm.
    public func refreshOnDemand(_ providers: [AIProviderType], trigger: RefreshTrigger) async {
        let now = Date()
        var due: [AIProviderType] = []

        for provider in providers where adapters[provider] != nil {
            guard let last = lastOnDemandRefresh[provider] else {
                due.append(provider)
                continue
            }
            let elapsed = now.timeIntervalSince(last)
            if elapsed >= trigger.floor {
                due.append(provider)
            } else {
                defer_(provider, by: trigger.floor - elapsed, trigger: trigger)
            }
        }
        guard !due.isEmpty else { return }

        for provider in due {
            lastOnDemandRefresh[provider] = now
            pendingOnDemand.removeValue(forKey: provider)?.cancel()
        }
        await withTaskGroup(of: Void.self) { group in
            for provider in due {
                group.addTask { await self.refreshProvider(provider, forceSync: true) }
            }
        }
    }

    /// Holds a trigger that arrived inside the floor until the floor is up.
    ///
    /// Dropping it instead would break the only guarantee that matters here: a
    /// detection is evidence the figure moved, and a dropped one leaves the
    /// screen waiting for the *next* burst, which may be a minute away. Deferred,
    /// the read always lands within one floor of the trigger.
    private func defer_(_ provider: AIProviderType, by delay: TimeInterval, trigger: RefreshTrigger) {
        guard pendingOnDemand[provider] == nil else { return }
        pendingOnDemand[provider] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.pendingOnDemand.removeValue(forKey: provider)
            await self.refreshOnDemand([provider], trigger: trigger)
        }
    }

    /// One provider's usage, at most one fetch at a time.
    ///
    /// The single-flight guard is not an optimisation. An adapter's fetch runs
    /// off this actor, so the 45-second sweep and an activity trigger arriving
    /// together used to put two calls inside the same adapter at once — two
    /// probes of the same CLI, and two threads writing the same caches. A caller
    /// that arrives mid-flight now waits for the answer already being fetched,
    /// which is the answer it was going to get anyway.
    public func refreshProvider(_ provider: AIProviderType, forceSync: Bool = false) async {
        if let existing = inFlightRefreshes[provider] {
            await existing.value
            return
        }

        guard let adapter = adapters[provider] else { return }

        // Cooldown check for non-forced events (e.g. high-frequency polling/FSEvents writes)
        if !forceSync {
            if let lastTime = lastFetchTime[provider],
               Date().timeIntervalSince(lastTime) < minCooldownInterval {
                let remaining = minCooldownInterval - Date().timeIntervalSince(lastTime)
                logger.debug(
                    "Cooldown for \(provider.rawValue, privacy: .public): \(Int(remaining))s left"
                )
                return
            }
        }

        logger.debug("Fetching usage for \(provider.rawValue, privacy: .public)")
        lastFetchTime[provider] = Date()

        let task = Task { @MainActor [weak self] in
            // Cleared here rather than after the `await` below, so a caller that
            // is cancelled mid-wait cannot retire an entry whose fetch is still
            // running and let a second one start beside it.
            defer { self?.inFlightRefreshes[provider] = nil }
            guard let self else { return }
            do {
                let fetched = try await adapter.fetchUsagePerAccount(forceSync: forceSync)
                await self.discoverAccountsBeforeFiling(fetched, for: provider)
                self.apply(fetched, for: provider)
                self.logger.debug(
                    "Updated \(fetched.count) snapshot(s) for \(provider.rawValue, privacy: .public)"
                )
            } catch {
                self.logger.error(
                    "Fetch failed for \(provider.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                await self.applyFetchFailure(error, for: provider)
            }
        }
        inFlightRefreshes[provider] = task
        await task.value
    }

    public func refreshAll(forceSync: Bool = false) async {
        isRefreshing = true
        defer { isRefreshing = false }

        // Routed through `refreshProvider` rather than reaching for the adapters
        // directly, so the cooldown and the single-flight guard hold for the
        // sweep as well. Duplicating the fetch here is how the sweep used to
        // overlap the on-demand path in the first place.
        await withTaskGroup(of: Void.self) { group in
            for provider in activeProviders {
                group.addTask { await self.refreshProvider(provider, forceSync: forceSync) }
            }
        }
    }
    
    public func toggleProvider(_ provider: AIProviderType) {
        withAnimation(JellySprings.layout) {
            if activeProviders.contains(provider) {
                if activeProviders.count > 1 {
                    activeProviders.removeAll { $0 == provider }
                }
            } else {
                activeProviders.append(provider)
                Task {
                    await refreshProvider(provider, forceSync: false)
                }
            }
            GlanciePreferences.shared.enabledProviders = activeProviders
        }
    }
    
    /// Background periodic sync every 45 seconds (respecting 45s rate-limit policy)
    private func startPeriodicPolling() {
        timer = Timer.publish(every: 45, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.refreshAll(forceSync: false)
                }
            }
    }
}
