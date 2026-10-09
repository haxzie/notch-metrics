import Foundation
import Testing

@testable import MetricsCore

/// Decodes every committed `contracts/fixtures/*.json`.
///
/// These are the same files the Worker's own suite round-trips, emitted by
/// `pnpm contracts` from the zod schemas. The Swift models are hand-written,
/// and this is what makes that safe: a renamed or retyped field fails here, by
/// name, in CI — rather than at a user's launch, as a decode error that blanks
/// every widget at once.
struct ContractTests {
    /// Walks up from this file to the repository root.
    static var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ContractTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // Kit
            .deletingLastPathComponent()  // mac
            .deletingLastPathComponent()  // apps
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("contracts/fixtures", isDirectory: true)
    }

    static func load(_ name: String) throws -> Data {
        try Data(contentsOf: fixtures.appendingPathComponent("\(name).json"))
    }

    @Test("every fixture file has a decoder on this side")
    func allFixturesAreCovered() throws {
        let files = try FileManager.default
            .contentsOfDirectory(atPath: Self.fixtures.path)
            .filter { $0.hasSuffix(".json") }
            .map { $0.replacingOccurrences(of: ".json", with: "") }
            .sorted()

        #expect(!files.isEmpty, "no fixtures found — run `pnpm contracts`")

        // Fixtures the Swift app deliberately does not decode: it never reads
        // a provider manifest list off disk, and the plugin manifest is
        // covered separately in PluginRuntime.
        let notDecodedHere: Set<String> = ["provider-manifest-list", "integration", "plugin-manifest"]
        let decoded: Set<String> = [
            "metric-series", "metric-series-empty", "metric-series-no-currency",
            "metric-series-list", "metric-error", "metric-batch", "widget-layout",
            "latest-json",
        ]

        let uncovered = Set(files).subtracting(decoded).subtracting(notDecodedHere)
        #expect(
            uncovered.isEmpty,
            "new fixtures with no Swift decoder: \(uncovered.sorted().joined(separator: ", "))")
    }

    @Test("a currency series decodes with its delta and points")
    func metricSeries() throws {
        let result = try JSONDecoder().decode(MetricResult.self, from: Self.load("metric-series"))
        let series = try #require(result.series)

        #expect(series.unit == .currency)
        #expect(series.currency == "USD")
        // Minor units, never a fractional amount.
        #expect(series.value == 1_284_500)
        #expect(series.points.count == 3)
        #expect(series.delta?.percent == 7.94)
        #expect(series.stale == false)
        #expect(series.points.first?.date != nil)
    }

    @Test("an empty, stale series decodes")
    func emptySeries() throws {
        let result = try JSONDecoder().decode(
            MetricResult.self, from: Self.load("metric-series-empty"))
        let series = try #require(result.series)
        #expect(series.points.isEmpty)
        #expect(series.delta == nil)
        #expect(series.stale)
    }

    @Test("a count series with a null currency decodes")
    func nullCurrency() throws {
        let result = try JSONDecoder().decode(
            MetricResult.self, from: Self.load("metric-series-no-currency"))
        let series = try #require(result.series)
        #expect(series.currency == nil)
        #expect(series.unit == .count)
        #expect(series.format == nil)
    }

    @Test("a list series decodes its rows, including one with no amount")
    func listSeries() throws {
        let result = try JSONDecoder().decode(
            MetricResult.self, from: Self.load("metric-series-list"))
        let series = try #require(result.series)
        let items = try #require(series.items)
        #expect(items.count == 3)
        #expect(items.first?.label == "Ada Lovelace")
        #expect(items.first?.amount == 9_900)
        #expect(items.first?.date != nil)
        #expect(items.last?.amount == nil)
        #expect(items.last?.currency == nil)
    }

    @Test("a number series has no rows, rather than an empty list")
    func numberHasNoItems() throws {
        let result = try JSONDecoder().decode(MetricResult.self, from: Self.load("metric-series"))
        #expect(try #require(result.series).items == nil)
    }

    @Test("an error carried inside a 200 decodes as a failure")
    func metricError() throws {
        let result = try JSONDecoder().decode(MetricResult.self, from: Self.load("metric-error"))
        guard case .failure(let failure) = result else {
            Issue.record("expected a failure")
            return
        }
        #expect(failure.code == .rateLimited)
        #expect(failure.retryAfterSeconds == 30)
    }

    @Test("a batch with one success and one failure decodes both")
    func batch() throws {
        let batch = try JSONDecoder().decode(
            MetricBatchResponse.self, from: Self.load("metric-batch"))
        #expect(batch.results.count == 2)
        #expect(batch.results[0].series != nil)
        #expect(batch.results[1].series == nil)
    }

    @Test("a grid layout decodes, and every widget names its app")
    func layout() throws {
        let layout = try JSONDecoder().decode(NotchLayout.self, from: Self.load("widget-layout"))
        #expect(layout.revision == 7)
        #expect(layout.rows == 2)
        #expect(layout.widgets.count == 2)
        #expect(layout.widgets[0].kind == .providerMetric)
        #expect(layout.widgets[0].size == .square)
        #expect(layout.widgets[0].appId == "stripe")
        #expect(layout.widgets[1].kind == .customMetric)
        #expect(layout.widgets[1].customMetricId == "github-stars")
        #expect(layout.widgets[1].appId == "github")

        // A widget's own arguments. A renamed key here fails by name in CI
        // rather than as a tile that silently asks about nothing.
        #expect(layout.widgets[0].params["repository"] == "haxzie/notch-metrics")
        // Absent in the second, which is the shape of every widget written
        // before per-widget parameters existed.
        #expect(layout.widgets[1].params.isEmpty)
    }


    @Test("an unknown enum value falls back instead of failing the whole decode")
    func unknownEnumsFallBack() throws {
        // This is the property that makes "add a provider without shipping the
        // app" actually safe. A strict enum would make one unfamiliar value
        // fail the decode of the entire response, so a Worker that started
        // sending a new unit or error code would break every installed copy at
        // once — including for the widgets that had nothing to do with it.
        let json = """
            {"ok":false,"integrationId":"int_1","metric":"arr",
             "code":"a_code_from_the_future","message":"hi","retryAfterSeconds":null}
            """
        let result = try JSONDecoder().decode(MetricResult.self, from: Data(json.utf8))
        guard case .failure(let failure) = result else {
            Issue.record("expected a failure")
            return
        }
        #expect(failure.code == .unknown)
    }

    @Test("re-encoding a fixture produces the same values")
    func roundTrip() throws {
        let original = try JSONDecoder().decode(MetricResult.self, from: Self.load("metric-series"))
        let reEncoded = try JSONEncoder().encode(original)
        let again = try JSONDecoder().decode(MetricResult.self, from: reEncoded)
        // Catches the half a decoder test alone misses: the app sending the
        // Worker a shape it will reject.
        #expect(original == again)
    }
}
