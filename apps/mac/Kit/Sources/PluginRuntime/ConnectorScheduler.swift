import Foundation
import MetricsCore

/// When each custom app is next allowed to run.
///
/// Per app rather than per metric, which is the difference from
/// `PluginScheduler`: a connector's `refreshIntervalSeconds` covers the whole
/// run, and asking per metric would let six tiles from one app each start
/// their own process on their own clock — the exact cost the format exists to
/// avoid.
public actor ConnectorScheduler {
    /// The floor the app applies regardless of what a manifest asks for.
    ///
    /// The schema's own minimum is 60, but the floor is the app's answer and
    /// not the schema's: nothing stops a hand-edited manifest carrying less,
    /// and the cost of believing it is a rate-limited key and a flat battery.
    public static let minimumInterval: TimeInterval = 60

    private struct Run {
        let at: Date
        /// The digest that ran. A rewritten app has not run at all, however
        /// recently its previous bytes did.
        let digest: String
    }

    private var runs: [String: Run] = [:]

    public init() {}

    public func isDue(_ app: LoadedConnector, now: Date = Date()) -> Bool {
        guard app.state == .ready, let manifest = app.manifest else { return false }
        guard let last = runs[app.id] else { return true }
        // Different bytes, so the recorded run belongs to code that no longer
        // exists and its interval should not be waited out.
        guard last.digest == app.contentHash else { return true }
        let interval = max(Self.minimumInterval, manifest.effectiveRefreshInterval)
        return now.timeIntervalSince(last.at) >= interval
    }

    public func recordRun(_ app: LoadedConnector, at: Date = Date()) {
        runs[app.id] = Run(at: at, digest: app.contentHash)
    }

    /// Forgets one app's last run, so the next refresh runs it immediately.
    ///
    /// For "Reload": the interval exists to stop polling, not to make an
    /// explicit request wait out a window the user did not ask for.
    public func invalidate(id: String) {
        runs.removeValue(forKey: id)
    }

    /// Forgets apps that are no longer installed.
    ///
    /// Without this, removing an app and adding it again under the same id
    /// would inherit the old timestamp and sit idle for an interval it never
    /// served.
    public func retain(ids: Set<String>) {
        runs = runs.filter { ids.contains($0.key) }
    }
}
