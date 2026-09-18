import Foundation
import SQLite3

/// Reads the claims out of an OAuth `id_token` without verifying its signature.
///
/// Verification would need the issuer's public keys over the network, and there
/// is nothing to defend against here: the token was written by the provider's
/// own CLI into the user's own home directory. Only the payload is decoded, and
/// the token string itself is never retained or logged.
public enum JWTClaims {
    public static func payload(of token: String) -> [String: Any]? {
        let segments = token.components(separatedBy: ".")
        guard segments.count >= 2 else { return nil }

        var base64 = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // base64url drops the padding that Foundation's decoder requires.
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }
}

/// Small helpers shared by every resolver.
public enum AccountFileReader {
    public static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    public static func json(atPath path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    /// `json(atPath:)`, reparsed only when the file has actually changed.
    ///
    /// `~/.claude.json` is a third of a megabyte on a machine with a hundred
    /// projects in it, and the activity triggers re-read it every few seconds
    /// now that they no longer launch a process instead. Comparing the
    /// modification date and size first turns almost all of those into a `stat`.
    public static func cachedJSON(atPath path: String) -> [String: Any]? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let modified = attributes?[.modificationDate] as? Date
        let size = attributes?[.size] as? Int

        if let hit = jsonCache.withValue({ $0[path] }),
           hit.modified == modified, hit.size == size {
            return hit.object
        }

        let object = json(atPath: path)
        jsonCache.withValue { $0[path] = (modified, size, object) }
        return object
    }

    private static let jsonCache =
        Locked<[String: (modified: Date?, size: Int?, object: [String: Any]?)]>([:])

    public static func directoryExists(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    /// Immediate children of `path` whose name starts with `prefix`, with the
    /// prefix stripped. Several desktop apps key their per-account storage this
    /// way (`conversations-v3-<uuid>`), so enumerating the suffixes enumerates
    /// the accounts that app has seen.
    public static func directorySuffixes(in path: String, prefix: String) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return names.compactMap { name in
            guard name.hasPrefix(prefix), name.count > prefix.count else { return nil }
            return String(name.dropFirst(prefix.count))
        }
    }

    /// Immediate children of `path` whose name is a UUID.
    ///
    /// Several desktop apps file their per-account state in a directory named
    /// after the account, so the UUID-shaped names *are* the accounts. The shape
    /// check matters: those trees also hold directories named after other things
    /// entirely, and a stray name would otherwise become a phantom account.
    public static func uuidDirectoryNames(in path: String) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        return names
            .filter { UUID(uuidString: $0) != nil }
            .filter { directoryExists((path as NSString).appendingPathComponent($0)) }
            .sorted()
    }

    /// Sibling home directories a provider's `*_CONFIG_DIR` convention creates,
    /// e.g. `~/.claude-work` alongside `~/.claude`. Returns absolute paths.
    ///
    /// A bare prefix match is too greedy: `~/.codexbar` belongs to an unrelated
    /// app, and treating it as a Codex profile would both look for credentials
    /// there and attribute its file writes to Codex. So a name qualifies only if
    /// it *is* the prefix or continues it with a separator.
    public static func siblingProfileDirectories(prefix: String) -> [String] {
        profileDirectories(in: home.path, prefix: prefix)
    }

    static func profileDirectories(in parentPath: String, prefix: String) -> [String] {
        let separators: Set<Character> = ["-", "_", "."]
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: parentPath) else { return [] }

        return names
            .filter { name in
                guard name.hasPrefix(prefix) else { return false }
                if name.count == prefix.count { return true }
                let next = name[name.index(name.startIndex, offsetBy: prefix.count)]
                return separators.contains(next)
            }
            .map { (parentPath as NSString).appendingPathComponent($0) }
            .filter { directoryExists($0) }
            .sorted()
    }
}

/// Reads another application's preferences domain.
///
/// Goes through `CFPreferences` first so the running app's unflushed changes are
/// visible, and falls back to parsing the plist directly — several AI desktop
/// apps store binary blobs that only the file-level reader tolerates.
public enum AccountPreferencesReader {
    public static func value(_ key: String, appID: String) -> Any? {
        if let value = CFPreferencesCopyAppValue(key as CFString, appID as CFString) {
            return value
        }
        return plistContents(appID: appID)?[key]
    }

    public static func string(_ key: String, appID: String) -> String? {
        value(key, appID: appID) as? String
    }

    public static func keys(appID: String) -> [String] {
        if let list = CFPreferencesCopyKeyList(
            appID as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? [String], !list.isEmpty {
            return list
        }
        return Array(plistContents(appID: appID)?.keys ?? [:].keys)
    }

    /// Keys shaped `<prefix><identifier>`, reduced to the distinct identifiers.
    public static func keySuffixes(appID: String, prefix: String) -> [String] {
        let matches = keys(appID: appID).compactMap { key -> String? in
            guard key.hasPrefix(prefix), key.count > prefix.count else { return nil }
            return String(key.dropFirst(prefix.count))
        }
        return Array(Set(matches)).sorted()
    }

    private static func plistContents(appID: String) -> [String: Any]? {
        let path = AccountFileReader.home
            .appendingPathComponent("Library/Preferences/\(appID).plist")
            .path
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any] else {
            return nil
        }
        return object
    }
}

/// Read-only key/value lookups against an Electron app's `state.vscdb`.
///
/// Opened through a `file:` URI with `immutable=1`: Cursor and friends keep the
/// database open with WAL journalling, and an ordinary read-write open would
/// either block on their lock or write a hot journal into their profile.
public enum AccountSQLiteReader {
    public static func itemTableValues(databasePath: String, keys: [String]) -> [String: String] {
        guard FileManager.default.fileExists(atPath: databasePath), !keys.isEmpty else { return [:] }

        var db: OpaquePointer?
        let encodedPath = databasePath
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? databasePath
        let uri = "file:\(encodedPath)?immutable=1"

        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return [:]
        }
        defer { sqlite3_close(db) }

        var results: [String: String] = [:]
        for key in keys {
            var statement: OpaquePointer?
            let sql = "SELECT value FROM ItemTable WHERE key = ? LIMIT 1"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(statement) }

            // SQLITE_TRANSIENT: sqlite must copy the bytes, since `key` is a
            // Swift temporary that may be gone before the step completes.
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, key, -1, transient)

            if sqlite3_step(statement) == SQLITE_ROW,
               let raw = sqlite3_column_text(statement, 0) {
                results[key] = String(cString: raw)
            }
        }
        return results
    }
}
