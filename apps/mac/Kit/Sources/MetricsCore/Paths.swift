import Foundation

/// Every path the app touches. Nothing else constructs one.
///
/// Scattered path literals are how a rename leaves one forgotten directory
/// behind, and how a test quietly writes into the real Application Support
/// folder.
public enum AppPaths {
    public static let bundleIdentifier = "com.notchmetrics.app"

    /// Computed rather than cached in a `static var`.
    ///
    /// A mutable static is shared global state, which strict concurrency
    /// rightly rejects — and the environment override below means it is not
    /// even constant within a process: the tests set it. Recomputing is two
    /// dictionary lookups and happens a handful of times per launch.
    public static var support: URL {
        if let override = ProcessInfo.processInfo.environment["NOTCH_SUPPORT_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchMetrics", isDirectory: true)
    }

    public static var caches: URL {
        if let override = ProcessInfo.processInfo.environment["NOTCH_CACHE_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    public static var settings: URL { support.appendingPathComponent("settings.json") }
    public static var layout: URL { support.appendingPathComponent("layout.json") }
    public static var session: URL { support.appendingPathComponent("session.json") }
    public static var pendingAuth: URL { support.appendingPathComponent("pending-auth.json") }

    /// Where the MCP server writes custom metrics and the app watches.
    public static var metrics: URL { support.appendingPathComponent("metrics", isDirectory: true) }
    public static var logs: URL { support.appendingPathComponent("logs", isDirectory: true) }
    public static var pluginLogs: URL { logs.appendingPathComponent("plugins", isDirectory: true) }

    public static var metricCache: URL { caches.appendingPathComponent("metrics", isDirectory: true) }
    public static var updates: URL { caches.appendingPathComponent("Updates", isDirectory: true) }

    public static func ensureDirectories() throws {
        for url in [support, metrics, logs, pluginLogs, metricCache, updates] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
