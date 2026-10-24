import Foundation
import MetricsCore
import Testing

@testable import PluginRuntime

/// Spawns the real runner, with the real Node, against a real plugin.
///
/// Everything else here is a unit test against a double. This is the only
/// thing that proves the three halves meet: that `NodeLocator` finds an
/// interpreter on this machine, that the esbuild bundle runs under it, and
/// that the one line it prints decodes into `PluginValue`.
///
/// It was also the gap that let the whole feature sit broken. `PluginRunner`
/// had no callers and no tests, so "the runner works" was asserted by its own
/// doc comment and nothing else.
///
/// Skipped rather than failed when the bundle has not been built: `pnpm
/// runner` is not part of `swift test`, and a red suite on a clean checkout
/// teaches people to ignore red suites.
struct PluginRunnerIntegrationTests {
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // PluginRuntimeTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // Kit
            .deletingLastPathComponent()  // mac
            .deletingLastPathComponent()  // apps
            .deletingLastPathComponent()  // repository root
    }

    static var script: URL {
        repoRoot.appendingPathComponent("packages/metric-runtime/dist/runner.mjs")
    }

    static var fixtures: URL {
        repoRoot.appendingPathComponent("packages/metric-runtime/test/plugins")
    }

    static var built: Bool { FileManager.default.fileExists(atPath: script.path) }

    static func runner() throws -> PluginRunner {
        try PluginRunner(secrets: InMemorySecretStore(), script: script)
    }

    static func plugin(_ name: String) throws -> LoadedPlugin {
        let dir = fixtures.appendingPathComponent(name)
        let data = try Data(contentsOf: dir.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        return LoadedPlugin(
            id: manifest.id, directory: dir, manifest: manifest,
            state: .ready, contentHash: "test")
    }

    @Test("a Node exists on this machine for the runner to use")
    func nodeIsFound() throws {
        // If this fails, every other test here is meaningless — and so is the
        // feature on this machine. The failure message lists what was tried,
        // because that is what a user would need to see too.
        let searched = NodeLocator.candidates()
        let found = searched.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        #expect(
            found != nil,
            "no Node in any of: \(searched.map(\.path).joined(separator: ", "))")
    }

    @Test("the bundled runner answers with a real number", .enabled(if: built))
    func runsAPlugin() async throws {
        let value = try await Self.runner().run(try Self.plugin("ok"))
        #expect(value.value == 42)
        #expect(value.unit == .count)
    }

    @Test("a plugin result becomes a tile-shaped series", .enabled(if: built))
    func convertsToSeries() async throws {
        let plugin = try Self.plugin("ok")
        let value = try await Self.runner().run(plugin)
        let series = value.series(manifest: try #require(plugin.manifest), window: .of(.month))

        // The whole point of the conversion: what comes back is the same shape
        // a Stripe tile draws, so one renderer serves both.
        #expect(series.value == 42)
        #expect(series.integrationId == nil)
        #expect(series.range == .month)
    }

    @Test("a blocked host is refused, and the secret does not leak", .enabled(if: built))
    func policyHolds() async throws {
        let secrets = InMemorySecretStore()
        try secrets.set("supersecret-do-not-leak", for: .plugin("exfiltrates", "GITHUB_TOKEN"))
        let runner = try PluginRunner(secrets: secrets, script: Self.script)

        let error = await #expect(throws: PluginRunnerError.self) {
            try await runner.run(try Self.plugin("exfiltrates"))
        }

        guard case .failed(let code, let message) = error else {
            Issue.record("expected a policy failure, got \(String(describing: error))")
            return
        }
        #expect(code == .policy)
        #expect(message.contains("evil.example.com"))
        // The reason this is asserted rather than assumed: a runner that
        // reported the request it was refused would defeat the refusal.
        #expect(!message.contains("supersecret"))
    }

    @Test("a plugin that ignores the clock is killed", .enabled(if: built))
    func timeoutIsEnforced() async throws {
        // The fixture sleeps five seconds against a one-second timeout and
        // never observes the abort signal — the case the out-of-process
        // watchdog exists for.
        let error = await #expect(throws: PluginRunnerError.self) {
            try await Self.runner().run(try Self.plugin("slow"))
        }
        #expect(error == .timedOut)
    }
}
