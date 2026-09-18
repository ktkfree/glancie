import Foundation

/// Remembers the last usage reading seen for each account.
///
/// Only the account a provider is currently signed into has live figures — the
/// local caches every provider writes hold one account's numbers, not a history
/// per login. So when the signed-in account changes, the outgoing account's last
/// reading is kept here and shown as a dated reading rather than disappearing.
public final class AccountUsageStore {
    public static let shared = AccountUsageStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.glancie.account-usage", qos: .utility)
    private var cache: [String: UsageSnapshot]

    public init(fileURL: URL? = nil) {
        let resolved = fileURL ?? Self.defaultFileURL()
        self.fileURL = resolved
        self.cache = Self.load(from: resolved)
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")

        let directory = base.appendingPathComponent("Glancie", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("account-usage.json")
    }

    private static func key(provider: AIProviderType, accountID: String) -> String {
        "\(provider.rawValue)|\(accountID)"
    }

    private static func load(from url: URL) -> [String: UsageSnapshot] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: UsageSnapshot].self, from: data)) ?? [:]
    }

    /// The stored reading with its countdowns wound forward to now, or nil if
    /// this account has never been observed.
    public func snapshot(provider: AIProviderType, accountID: String) -> UsageSnapshot? {
        queue.sync { cache[Self.key(provider: provider, accountID: accountID)] }?
            .agedToNow()
    }

    public func record(_ snapshot: UsageSnapshot) {
        guard let accountID = snapshot.accountID, !accountID.isEmpty else { return }
        // Estimates and placeholders are fine to show live, labelled as such.
        // Filing them away is not: a month later they would resurface as
        // "3주 전 기준 79%", indistinguishable from a real measurement.
        guard snapshot.strategyUsed != .simulated, snapshot.fetchError == nil else { return }

        let key = Self.key(provider: snapshot.provider, accountID: accountID)

        queue.async { [weak self] in
            guard let self else { return }
            // A snapshot only ever moves forward in time, so a late-arriving
            // older reading must not overwrite a newer one.
            if let existing = self.cache[key], existing.capturedAt > snapshot.capturedAt { return }
            self.cache[key] = snapshot
            self.persist()
        }
    }

    /// Must be called on `queue`.
    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
