import Foundation
import MetricsCore
import Testing

@testable import PluginRuntime

/// Which plugins run, and when.
struct PluginSchedulerTests {
    static func manifest(every seconds: Int) -> PluginManifest {
        PluginManifest(
            schemaVersion: 1, id: "stars", name: "Stars", shortLabel: "Stars",
            description: "d", unit: .count, currency: nil, format: MetricFormat(),
            granularities: [.day], supportsSeries: false,
            refreshIntervalSeconds: seconds, secrets: [], allowedHosts: ["api.github.com"],
            timeoutMs: 8000, entry: "metric.mjs", author: nil,
            createdAt: "2026-10-05T12:00:00.000Z", updatedAt: "2026-10-05T12:00:00.000Z")
    }

    static func plugin(
        id: String = "stars", every seconds: Int = 900,
        state: PluginState = .ready, digest: String = "aaa"
    ) -> LoadedPlugin {
        var m = manifest(every: seconds)
        if id != "stars" {
            m = PluginManifest(
                schemaVersion: 1, id: id, name: id, shortLabel: id, description: "d",
                unit: .count, currency: nil, format: MetricFormat(), granularities: [.day],
                supportsSeries: false, refreshIntervalSeconds: seconds, secrets: [],
                allowedHosts: ["api.github.com"], timeoutMs: 8000, entry: "metric.mjs",
                author: nil, createdAt: "2026-10-05T12:00:00.000Z",
                updatedAt: "2026-10-05T12:00:00.000Z")
        }
        return LoadedPlugin(
            id: id, directory: URL(fileURLWithPath: "/tmp/\(id)"), manifest: m,
            state: state, contentHash: digest)
    }

    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a plugin that has never run is due")
    func neverRun() async {
        let scheduler = PluginScheduler()
        #expect(await scheduler.due([Self.plugin()], now: Self.t0).count == 1)
    }

    @Test("it is not due again until its own interval has passed")
    func honoursItsInterval() async {
        let scheduler = PluginScheduler()
        let plugin = Self.plugin(every: 900)
        await scheduler.recordRun(plugin, at: Self.t0)

        #expect(await scheduler.due([plugin], now: Self.t0.addingTimeInterval(899)).isEmpty)
        #expect(await scheduler.due([plugin], now: Self.t0.addingTimeInterval(900)).count == 1)
    }

    @Test("a metric asking to run every second gets a minute")
    func floorIsApplied() async {
        // The manifest's own minimum is 60, but the floor is the app's answer
        // and not the schema's: a rate-limited key and a flat battery are the
        // cost of believing a hand-edited file.
        let scheduler = PluginScheduler()
        let hasty = Self.plugin(every: 1)
        await scheduler.recordRun(hasty, at: Self.t0)

        #expect(await scheduler.due([hasty], now: Self.t0.addingTimeInterval(59)).isEmpty)
        #expect(await scheduler.due([hasty], now: Self.t0.addingTimeInterval(60)).count == 1)
    }

    @Test("only an approved, unmodified plugin ever runs")
    func stateGate() async {
        let scheduler = PluginScheduler()
        let candidates = [
            Self.plugin(id: "ready", state: .ready),
            Self.plugin(id: "pending", state: .pendingApproval),
            Self.plugin(id: "modified", state: .modified),
            Self.plugin(id: "invalid", state: .invalid(reason: "broken")),
        ]
        let due = await scheduler.due(candidates, now: Self.t0)
        // Enforced here as well as in the registry: `PluginRunner` can be
        // called directly, so one gate is not enough.
        #expect(due.map(\.id) == ["ready"])
    }

    @Test("rewritten code does not wait out the old version's interval")
    func digestResetsTheClock() async {
        let scheduler = PluginScheduler()
        let before = Self.plugin(every: 900, digest: "aaa")
        await scheduler.recordRun(before, at: Self.t0)
        #expect(await scheduler.due([before], now: Self.t0.addingTimeInterval(10)).isEmpty)

        // Re-registered a moment later. Different bytes, so the recorded run
        // belongs to code that no longer exists.
        let after = Self.plugin(every: 900, digest: "bbb")
        #expect(await scheduler.due([after], now: Self.t0.addingTimeInterval(10)).count == 1)
    }

    @Test("a removed and re-added metric does not inherit its old timestamp")
    func retainForgets() async {
        let scheduler = PluginScheduler()
        let plugin = Self.plugin(every: 900)
        await scheduler.recordRun(plugin, at: Self.t0)
        #expect(await scheduler.due([plugin], now: Self.t0.addingTimeInterval(10)).isEmpty)

        await scheduler.retain(ids: [])
        #expect(await scheduler.due([plugin], now: Self.t0.addingTimeInterval(10)).count == 1)
    }

    @Test("order is preserved, so the notch refreshes left to right")
    func ordering() async {
        let scheduler = PluginScheduler()
        let plugins = [Self.plugin(id: "a"), Self.plugin(id: "b"), Self.plugin(id: "c")]
        #expect(await scheduler.due(plugins, now: Self.t0).map(\.id) == ["a", "b", "c"])
    }
}
