import Foundation

/// Finds the Cursor account from the editor's own key/value store.
///
/// Cursor caches the signed-in address, the team and the subscription tier in
/// `state.vscdb` beside its auth tokens, so the identity is available without
/// touching the tokens or the network.
public final class CursorAccountResolver: AccountResolver {
    public let provider: AIProviderType = .cursor
    public let primarySourceID: String = "cursor.ide"

    private static let emailKey = "cursorAuth/cachedEmail"
    private static let teamKey = "cursorAuth/cachedTeam"
    private static let membershipKey = "cursorAuth/stripeMembershipType"

    public init() {}

    public func resolveAccounts() async -> [AccountIdentity] {
        let root = AccountFileReader.home
            .appendingPathComponent("Library/Application Support/Cursor")
        guard AccountFileReader.directoryExists(root.path) else { return [] }

        let databasePath = root
            .appendingPathComponent("User/globalStorage/state.vscdb")
            .path

        let values = AccountSQLiteReader.itemTableValues(
            databasePath: databasePath,
            keys: [Self.emailKey, Self.teamKey, Self.membershipKey]
        )

        guard let email = values[Self.emailKey], !email.isEmpty else { return [] }

        return [
            AccountIdentity(
                id: email,
                provider: .cursor,
                source: AccountSource(
                    id: "cursor.ide",
                    kind: .ide,
                    displayName: "Cursor",
                    rootPath: root.path,
                    bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"]
                ),
                email: email,
                organization: Self.teamName(from: values[Self.teamKey]),
                planName: Self.planName(fromMembership: values[Self.membershipKey]),
                usageReadable: true
            )
        ]
    }

    private static func teamName(from raw: String?) -> String? {
        guard let raw, let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let name = object["name"] as? String
        return (name?.isEmpty == false) ? name : nil
    }

    private static func planName(fromMembership raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return "Cursor \(raw.replacingOccurrences(of: "_", with: " ").capitalized)"
    }
}
