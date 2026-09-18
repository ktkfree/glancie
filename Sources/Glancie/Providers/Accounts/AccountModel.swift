import Foundation

/// Where an account's identity was found.
///
/// A source is a *place a provider runs from*, not a quota bucket. Quota belongs
/// to the account; the source only tells us whether something is running right
/// now and where to watch for that.
public enum AccountSourceKind: String, Codable, Equatable {
    case cli
    case desktopApp
    case ide
    case api

    public var badgeText: String {
        switch self {
        case .cli: return "CLI"
        case .desktopApp: return "App"
        case .ide: return "IDE"
        case .api: return "API"
        }
    }

    public var symbol: String {
        switch self {
        case .cli: return "terminal"
        case .desktopApp: return "macwindow"
        case .ide: return "chevron.left.forwardslash.chevron.right"
        case .api: return "key"
        }
    }
}

/// One place an account was read from, plus the path that proved it exists.
public struct AccountSource: Identifiable, Equatable, Codable {
    /// Stable dotted id, e.g. `claude.cli`, `claude.desktop`. Not unique on its
    /// own when a provider has several profile homes — `rootPath` separates those.
    public var id: String
    public var kind: AccountSourceKind
    public var displayName: String
    /// The directory or file that proved this source is present. Doubles as the
    /// key that maps a file-system event back to this account.
    public var rootPath: String?
    /// Bundle ids to look for among running applications.
    ///
    /// A GUI app announces itself to the workspace, so asking whether it is
    /// running beats inferring it from writes to a directory full of caches.
    /// CLI sources leave this empty and are detected through file activity.
    public var bundleIdentifiers: [String]

    public init(
        id: String,
        kind: AccountSourceKind,
        displayName: String,
        rootPath: String? = nil,
        bundleIdentifiers: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.rootPath = rootPath
        self.bundleIdentifiers = bundleIdentifiers
    }
}

/// A provider login discovered on this machine.
///
/// `id` is provider-scoped and must be stable across launches, because usage is
/// filed under it. Each resolver picks the most durable identifier its provider
/// exposes — an account UUID where one exists, the e-mail otherwise.
public struct AccountIdentity: Identifiable, Equatable, Codable {
    public var id: String
    public var provider: AIProviderType
    public var source: AccountSource
    public var email: String?
    public var displayName: String?
    public var organization: String?
    public var planName: String?

    /// Whether this machine can actually read this account's quota.
    ///
    /// Discovering an account and being able to read its usage are different
    /// facts. A `CLAUDE_CONFIG_DIR` profile carries its own usage cache, so it is
    /// readable; the Gemini desktop app leaves an account id in its preferences
    /// and nothing else, so that account is known but unreadable and can only
    /// ever show its last recorded figures.
    public var usageReadable: Bool

    public var lastSeenAt: Date

    public init(
        id: String,
        provider: AIProviderType,
        source: AccountSource,
        email: String? = nil,
        displayName: String? = nil,
        organization: String? = nil,
        planName: String? = nil,
        usageReadable: Bool = false,
        lastSeenAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.source = source
        self.email = email
        self.displayName = displayName
        self.organization = organization
        self.planName = planName
        self.usageReadable = usageReadable
        self.lastSeenAt = lastSeenAt
    }
}

/// One account after the per-source discoveries have been reconciled.
///
/// Identities that share an id collapse into a single account listing every
/// source it was seen in — the Claude CLI and Claude Desktop are one login in
/// two places. Two *different* ids stay two accounts, which is what surfaces a
/// CLI and a desktop app signed into different Google accounts.
public struct ResolvedAccount: Identifiable, Equatable {
    public var id: String
    public var provider: AIProviderType
    public var email: String?
    public var displayName: String?
    public var organization: String?
    public var planName: String?
    public var sources: [AccountSource]
    /// True when at least one source can read this account's quota.
    public var usageReadable: Bool
    public var lastSeenAt: Date

    public init(
        id: String,
        provider: AIProviderType,
        email: String? = nil,
        displayName: String? = nil,
        organization: String? = nil,
        planName: String? = nil,
        sources: [AccountSource] = [],
        usageReadable: Bool = false,
        lastSeenAt: Date = Date()
    ) {
        self.id = id
        self.provider = provider
        self.email = email
        self.displayName = displayName
        self.organization = organization
        self.planName = planName
        self.sources = sources
        self.usageReadable = usageReadable
        self.lastSeenAt = lastSeenAt
    }

    public var displayLabel: String {
        if let email, !email.isEmpty { return email }
        if let displayName, !displayName.isEmpty { return displayName }
        return String(id.prefix(12))
    }

    public var maskedLabel: String {
        guard let email, let atIndex = email.firstIndex(of: "@"), atIndex > email.startIndex else {
            return displayLabel
        }
        return "\(email[email.startIndex..<atIndex].prefix(1))***\(email[atIndex...])"
    }

    public func label(masked: Bool) -> String {
        masked ? maskedLabel : displayLabel
    }

    /// One badge per *kind*, not per source: the Gemini CLI and the Antigravity
    /// CLI are two sources of the same login, and "CLI · CLI · IDE" reads as a
    /// bug rather than as detail.
    public var sourceBadgeText: String {
        var seen = Set<AccountSourceKind>()
        return sources
            .map(\.kind)
            .filter { seen.insert($0).inserted }
            .map(\.badgeText)
            .joined(separator: " · ")
    }

    /// Directories whose file-system activity means *this account* is working.
    public var watchPaths: [String] {
        sources.compactMap(\.rootPath)
    }

    /// Folds one more discovery of the same account into this one.
    public mutating func absorb(_ identity: AccountIdentity) {
        email = email ?? identity.email
        displayName = displayName ?? identity.displayName
        organization = organization ?? identity.organization
        planName = planName ?? identity.planName
        usageReadable = usageReadable || identity.usageReadable
        lastSeenAt = max(lastSeenAt, identity.lastSeenAt)
        // Sources are keyed by id *and* path: two `claude.cli` profile homes are
        // two places to watch, not one.
        let alreadyKnown = sources.contains {
            $0.id == identity.source.id && $0.rootPath == identity.source.rootPath
        }
        if !alreadyKnown {
            sources.append(identity.source)
        }
    }

    public init(_ identity: AccountIdentity) {
        self.init(
            id: identity.id,
            provider: identity.provider,
            email: identity.email,
            displayName: identity.displayName,
            organization: identity.organization,
            planName: identity.planName,
            sources: [identity.source],
            usageReadable: identity.usageReadable,
            lastSeenAt: identity.lastSeenAt
        )
    }
}

/// Discovers the accounts one provider has on this machine.
///
/// Implementations are read-only and must never throw on a machine where the
/// provider is absent — an empty array is the correct answer there.
public protocol AccountResolver {
    var provider: AIProviderType { get }

    /// The source a single-snapshot adapter reads.
    ///
    /// Only a fallback: adapters that report one snapshot per account tag it
    /// themselves, and this is how the remaining provider-level adapters get
    /// attributed to the right login.
    var primarySourceID: String { get }

    /// Discovered accounts. Order is not significant — usage decides which
    /// account is current, and file-system activity decides which is running.
    func resolveAccounts() async -> [AccountIdentity]
}
