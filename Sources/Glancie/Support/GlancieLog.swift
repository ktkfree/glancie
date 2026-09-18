import Foundation
import os

/// Where the app's diagnostics go.
///
/// `print` was the previous answer. In the file-watching path that meant a line
/// per FSEvent — tens per second during a streaming turn, formatted on the
/// thread doing the filtering, written to a stdout that nobody reads once the
/// app is a bundle rather than a `swift run`.
///
/// `Logger` costs nothing when no one is listening, keeps the levels apart, and
/// can be read back with `log stream --predicate 'subsystem == "com.glancie"'`.
public enum GlancieLog {
    public static let subsystem = "com.glancie"

    /// Adapters, fetch strategies, probes.
    public static let provider = Logger(subsystem: subsystem, category: "provider")
    /// FSEvents, activity filtering, running-state.
    public static let watcher = Logger(subsystem: subsystem, category: "watcher")
    /// Account discovery and attribution.
    public static let accounts = Logger(subsystem: subsystem, category: "accounts")
}
