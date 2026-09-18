import Foundation

/// Remembers which account each local profile was signed into, and when that
/// last changed.
///
/// Some providers record usage in files that name no account at all — Codex's
/// session rollouts carry the quota the API reported and nothing about whose
/// quota it was. Reading the account from `auth.json` and the figures from the
/// newest rollout therefore *assembles* an attribution rather than observing
/// one: sign out of A and into B, and B's id gets stapled to A's spending.
///
/// The one piece of evidence available is the switch itself. This ledger
/// watches for it: whenever the account behind a profile changes from what was
/// recorded, the moment of the change is stored, and readings from before it
/// stop being attributable to whoever is signed in now.
///
/// It deliberately does not distrust anything it has not witnessed. A profile
/// seen for the first time carries no boundary at all, because "we have never
/// looked before" is not evidence that the account changed — and using the
/// credential file's timestamp instead would discard good readings every time
/// the CLI refreshed its token.
public final class AccountIdentityLedger {
    public static let shared = AccountIdentityLedger()

    /// What was signed into one profile, and since when.
    struct Record: Codable, Equatable {
        var accountID: String
        /// When this account was first seen here, if a change was witnessed.
        /// `nil` for a profile that has only ever held this one account.
        var switchedAt: Date?
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.glancie.account-identity")
    private var records: [String: Record]

    public init(fileURL: URL? = nil) {
        let resolved = fileURL ?? Self.defaultFileURL()
        self.fileURL = resolved
        self.records = Self.load(from: resolved)
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")

        let directory = base.appendingPathComponent("Glancie", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("account-identity.json")
    }

    private static func load(from url: URL) -> [String: Record] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Record].self, from: data)) ?? [:]
    }

    private static func key(provider: AIProviderType, profile: String) -> String {
        "\(provider.rawValue)|\(profile)"
    }

    /// Records who is signed in now and returns the earliest measurement time
    /// that may be attributed to them.
    ///
    /// - Parameters:
    ///   - profile: the local configuration the account was read from, so two
    ///     `CODEX_HOME`s are tracked separately.
    ///   - accountID: who is signed in right now.
    ///   - changedAt: when the credential was last written, used as the switch
    ///     time when a change is detected. Falls back to now.
    /// - Returns: `nil` when everything on disk may be attributed to this
    ///   account, or the instant before which nothing may be.
    @discardableResult
    public func attributionBoundary(
        provider: AIProviderType,
        profile: String,
        accountID: String,
        changedAt: Date? = nil,
        now: Date = Date()
    ) -> Date? {
        let key = Self.key(provider: provider, profile: profile)

        return queue.sync {
            if let existing = records[key], existing.accountID == accountID {
                return existing.switchedAt
            }

            // Either the first time this profile has been seen, or a switch.
            // Only the second one is evidence about the readings on disk.
            let isSwitch = records[key] != nil
            let switchedAt = isSwitch ? (changedAt ?? now) : nil
            records[key] = Record(accountID: accountID, switchedAt: switchedAt)
            persist()
            return switchedAt
        }
    }

    /// Whether a reading taken at `capturedAt` describes the account currently
    /// signed into this profile.
    public func isAttributable(
        capturedAt: Date,
        provider: AIProviderType,
        profile: String,
        accountID: String,
        changedAt: Date? = nil,
        now: Date = Date()
    ) -> Bool {
        guard let boundary = attributionBoundary(
            provider: provider,
            profile: profile,
            accountID: accountID,
            changedAt: changedAt,
            now: now
        ) else { return true }
        return capturedAt >= boundary
    }

    /// Forgets everything. For tests and for a full re-scan.
    public func reset() {
        queue.sync {
            records = [:]
            persist()
        }
    }

    /// Must be called on `queue`.
    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
