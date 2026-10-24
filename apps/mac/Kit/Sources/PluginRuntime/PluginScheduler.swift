import Foundation

/// Decides which plugins are due to run.
///
/// Plugins keep their own cadence — `refreshIntervalSeconds`, floored at a
/// minute — rather than riding the metric poll, because the two answer
/// different questions. The Worker batch is one request for every provider
/// tile at once; a plugin is a process per metric against somebody's own API,
/// and a metric that asked for fifteen minutes should get fifteen minutes.
///
/// `effectiveRefreshInterval` has existed since the manifest did and has never
/// had a caller. This is it.
///
/// An actor because the refresh runs off the main actor and the record of what
/// ran when is shared mutable state — the exact thing that would otherwise be
/// a data race the compiler rejects.
public actor PluginScheduler {
    /// Keyed by id, valued by *what* ran and when. The digest is part of the
    /// value because a rewritten plugin is a different plugin: honouring the
    /// old timestamp would leave new code waiting out the previous version's
    /// interval before it ever ran.
    private var lastRun: [String: (digest: String, at: Date)] = [:]

    public init() {}

    /// Those that should run now, in the order given.
    ///
    /// Only `.ready` ones are ever returned. A plugin pending approval — or
    /// one whose bytes changed after approval — must not run, and this is the
    /// second place that is enforced rather than the only one: `PluginRunner`
    /// is reachable directly, so the gate belongs at both ends.
    public func due(_ plugins: [LoadedPlugin], now: Date = Date()) -> [LoadedPlugin] {
        plugins.filter { plugin in
            guard plugin.state == .ready, let manifest = plugin.manifest else { return false }
            guard let last = lastRun[plugin.id] else { return true }
            // Different bytes, so the clock starts again.
            guard last.digest == plugin.contentHash else { return true }
            return now.timeIntervalSince(last.at) >= manifest.effectiveRefreshInterval
        }
    }

    public func recordRun(_ plugin: LoadedPlugin, at: Date = Date()) {
        lastRun[plugin.id] = (digest: plugin.contentHash, at: at)
    }

    /// Forgets everything about plugins no longer present, so a removed and
    /// re-added metric does not inherit a timestamp from its previous life.
    public func retain(ids: Set<String>) {
        lastRun = lastRun.filter { ids.contains($0.key) }
    }
}
