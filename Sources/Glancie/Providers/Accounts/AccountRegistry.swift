import SwiftUI

/// Knows which accounts each provider has on this machine.
///
/// Two facts are kept apart on purpose. *Which account* a set of figures belongs
/// to is decided by the account id on the snapshot — quota is bound to the
/// account, never to the CLI or app it was read through. *Whether something is
/// running* is decided by file-system activity under a source's directory, and
/// lives in `ProviderManager`, not here.
@MainActor
public final class AccountRegistry: ObservableObject {
    public static let shared = AccountRegistry()

    @Published public private(set) var accountsByProvider: [AIProviderType: [ResolvedAccount]] = [:]
    @Published public private(set) var lastScanDate: Date?
    @Published public private(set) var isScanning: Bool = false

    private let resolvers: [AccountResolver]
    /// Which source a single-snapshot adapter reads, declared by its resolver.
    private let primarySourceIDs: [AIProviderType: String]

    public init(resolvers: [AccountResolver] = [
        ClaudeAccountResolver(),
        CodexAccountResolver(),
        GeminiAccountResolver(),
        CursorAccountResolver()
    ]) {
        self.resolvers = resolvers
        self.primarySourceIDs = resolvers.reduce(into: [:]) { map, resolver in
            map[resolver.provider] = resolver.primarySourceID
        }
    }

    // MARK: - Queries

    public func accounts(for provider: AIProviderType) -> [ResolvedAccount] {
        accountsByProvider[provider] ?? []
    }

    public func account(for provider: AIProviderType, id: String) -> ResolvedAccount? {
        accounts(for: provider).first { $0.id == id }
    }

    /// Accounts whose quota this machine can actually read.
    public func readableAccounts(for provider: AIProviderType) -> [ResolvedAccount] {
        accounts(for: provider).filter(\.usageReadable)
    }

    public func primarySourceID(for provider: AIProviderType) -> String? {
        primarySourceIDs[provider]
    }

    /// Which account a provider-level snapshot belongs to.
    ///
    /// Only needed for adapters that still report one snapshot for the whole
    /// provider. An adapter that reports per account tags its own snapshots and
    /// never consults this.
    public func attributionAccount(for provider: AIProviderType) -> ResolvedAccount? {
        let readable = readableAccounts(for: provider)
        if let primary = primarySourceIDs[provider],
           let onPrimary = readable.first(where: { $0.sources.contains { $0.id == primary } }) {
            return onPrimary
        }
        return readable.first ?? accounts(for: provider).first
    }

    public var allSources: [AccountSource] {
        var seen = Set<String>()
        return accountsByProvider.values
            .flatMap { $0 }
            .flatMap(\.sources)
            .filter { seen.insert("\($0.id)|\($0.rootPath ?? "")").inserted }
            .sorted { $0.id < $1.id }
    }

    /// Directories to watch, each tied to the account that works out of it.
    ///
    /// This is the whole role of a source: a write under `~/.claude-work` means
    /// *that* account is busy, which the provider-level path list could never
    /// distinguish.
    public var activityPaths: [(path: String, provider: AIProviderType, accountID: String)] {
        accountsByProvider.values.flatMap { accounts in
            accounts.flatMap { account in
                account.watchPaths.map { (path: $0, provider: account.provider, accountID: account.id) }
            }
        }
    }

    // MARK: - Scanning

    func hasResolver(for provider: AIProviderType) -> Bool {
        resolvers.contains { $0.provider == provider }
    }

    public func refreshAccounts(for provider: AIProviderType? = nil) async {
        guard GlanciePreferences.shared.accountScanEnabled else {
            accountsByProvider = [:]
            lastScanDate = Date()
            return
        }

        isScanning = true
        defer { isScanning = false }

        // Resolvers only read files, but a slow disk shouldn't stall the menu,
        // so they run concurrently and off the main actor.
        var discovered: [AIProviderType: [AccountIdentity]] = [:]

        await withTaskGroup(of: [AccountIdentity].self) { group in
            for resolver in resolvers where provider == nil || resolver.provider == provider {
                group.addTask { await resolver.resolveAccounts() }
            }
            for await identities in group {
                for identity in identities {
                    discovered[identity.provider, default: []].append(identity)
                }
            }
        }

        var reconciled: [AIProviderType: [ResolvedAccount]] = [:]
        for (provider, identities) in discovered {
            reconciled[provider] = Self.reconcile(identities)
        }

        if let provider {
            self.accountsByProvider[provider] = reconciled[provider] ?? []
        } else {
            self.accountsByProvider = reconciled
        }
        self.lastScanDate = Date()
        logDiscovery(reconciled)
    }

    /// Collapses identities that share an id, readable accounts first so the
    /// detail screen leads with the ones that have live figures.
    nonisolated static func reconcile(_ identities: [AccountIdentity]) -> [ResolvedAccount] {
        var order: [String] = []
        var merged: [String: ResolvedAccount] = [:]

        for identity in identities {
            if merged[identity.id] != nil {
                merged[identity.id]?.absorb(identity)
            } else {
                merged[identity.id] = ResolvedAccount(identity)
                order.append(identity.id)
            }
        }

        let accounts: [ResolvedAccount] = order.compactMap { merged[$0] }
        return accounts.sorted { lhs, rhs in
            if lhs.usageReadable != rhs.usageReadable { return lhs.usageReadable }
            return lhs.displayLabel < rhs.displayLabel
        }
    }

    private func logDiscovery(_ accounts: [AIProviderType: [ResolvedAccount]]) {
        for provider in AIProviderType.allCases {
            guard let list = accounts[provider], !list.isEmpty else { continue }
            // Addresses are masked in logs regardless of the display preference:
            // console output outlives the window it came from.
            let summary = list
                .map { "\($0.maskedLabel)[\($0.sourceBadgeText)]\($0.usageReadable ? "" : " (unreadable)")" }
                .joined(separator: ", ")
            GlancieLog.accounts.debug("[\(provider.rawValue, privacy: .public)] \(summary, privacy: .private)")
        }
    }
}
