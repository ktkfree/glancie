import Foundation

/// Cursor Adapter.
///
/// Cursor keeps its quota server-side and exposes nothing to the local
/// container that this app can read, so detection is all this adapter can
/// honestly report: the presence of `~/Library/Application Support/Cursor`
/// says the editor is installed, not how many fast requests are left.
public final class CursorAdapter: AIProviderAdapter, @unchecked Sendable {
    public let type: AIProviderType = .cursor

    private let detected = Locked(false)
    public var isDetected: Bool { detected.value }

    private let fileManager = FileManager.default
    private let homeDirectory: URL

    public init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = URL(fileURLWithPath: homeDirectory)
    }

    private var cursorSupportDirectory: URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Cursor")
    }

    public func checkAvailability() async -> Bool {
        let found = fileManager.fileExists(atPath: cursorSupportDirectory.path)
        detected.value = found
        return found
    }

    /// No reading, ever — by design.
    ///
    /// This used to count the folders under `logs/` and call it usage: fifteen
    /// requests per folder against an assumed quota of five hundred, floored at
    /// 5% so a spent account still looked like it had room. None of those three
    /// numbers came from Cursor. A log directory is a log directory; converting
    /// its cardinality into a percentage produced a figure that moved for
    /// reasons unrelated to spending and read as a measurement on the bar.
    public func fetchUsage(forceSync: Bool = false) async throws -> UsageSnapshot {
        let installed = fileManager.fileExists(atPath: cursorSupportDirectory.path)
        detected.value = installed
        return .unavailable(
            for: .cursor,
            reason: installed ? .notMeasured : .notConfigured
        )
    }
}
