import Foundation
import MetricsCore
import Testing

@testable import PluginRuntime

/// Decodes `contracts/fixtures/plugin-manifest.json`.
///
/// `ContractTests` lists `plugin-manifest` as deliberately not decoded there,
/// "covered separately in PluginRuntime". For a long time there was no such
/// target, so the fixture was decoded by nothing and the one comment claiming
/// otherwise was the only thing holding the contract up. This is that cover.
///
/// It matters more here than for most shapes because this manifest is written
/// by an **agent**, not by us: the schema is the only thing standing between a
/// plausible-looking file and a metric that silently never runs.
struct PluginManifestContractTests {
    static var fixture: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // PluginRuntimeTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // Kit
            .deletingLastPathComponent()  // mac
            .deletingLastPathComponent()  // apps
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("contracts/fixtures/plugin-manifest.json")
    }

    @Test("the committed fixture decodes")
    func decodes() throws {
        let data = try Data(contentsOf: Self.fixture)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)

        #expect(manifest.id == "github-stars")
        #expect(manifest.unit == .count)
        #expect(manifest.entry == "metric.mjs")
        #expect(manifest.allowedHosts == ["api.github.com"])
        #expect(manifest.secrets.first?.key == "GITHUB_TOKEN")
        #expect(manifest.secrets.first?.required == true)
    }

    /// The floor exists so a manifest asking to run every second cannot.
    ///
    /// It is the app's answer, not the schema's: the schema's own minimum is
    /// 60, but nothing stops an older manifest or a hand-edited file carrying
    /// less, and the cost of honouring it is a rate-limited key and a flat
    /// battery.
    @Test("the refresh interval is floored at a minute")
    func refreshFloor() throws {
        let data = try Data(contentsOf: Self.fixture)
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        #expect(manifest.effectiveRefreshInterval == 900)

        let hasty = try JSONDecoder().decode(
            PluginManifest.self,
            from: Data(
                String(data: data, encoding: .utf8)!
                    .replacingOccurrences(
                        of: "\"refreshIntervalSeconds\": 900",
                        with: "\"refreshIntervalSeconds\": 1"
                    ).utf8))
        #expect(hasty.effectiveRefreshInterval == 60)
    }
}
