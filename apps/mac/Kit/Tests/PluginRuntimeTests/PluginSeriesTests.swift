import Foundation
import MetricsCore
import Testing

@testable import PluginRuntime

/// A plugin's answer becoming the shape every tile draws.
///
/// The conversion is the whole reason a local metric can render at all, and
/// it is where the two definition sources have to agree: a number from a
/// plugin must be indistinguishable, to the renderer, from one off the Worker.
struct PluginSeriesTests {
    static let manifest = PluginManifest(
        schemaVersion: 1,
        id: "github-stars",
        name: "GitHub stars",
        shortLabel: "Stars",
        description: "Stargazers on a repository.",
        unit: .count,
        currency: nil,
        format: MetricFormat(),
        granularities: [.day],
        supportsSeries: false,
        refreshIntervalSeconds: 900,
        secrets: [],
        allowedHosts: ["api.github.com"],
        timeoutMs: 8000,
        entry: "metric.mjs",
        author: nil,
        createdAt: "2026-10-05T12:00:00.000Z",
        updatedAt: "2026-10-05T12:00:00.000Z"
    )

    static func value(
        _ v: Double, unit: MetricUnit? = nil, currency: String? = nil,
        series: [MetricPoint]? = nil, previousValue: Double? = nil, asOf: String? = nil
    ) -> PluginValue {
        PluginValue(
            value: v, unit: unit, currency: currency, series: series,
            previousValue: previousValue, asOf: asOf)
    }

    @Test("a plugin series carries no integration, which is how it is told apart")
    func noIntegration() {
        let series = Self.value(412).series(
            manifest: Self.manifest, window: .of(.month))

        // Nil is the signal, not an omission. `adoptConnections` binds only
        // widgets that have one, and the "which account?" subtitle resolves
        // from it — neither has anything to find for a local metric.
        #expect(series.integrationId == nil)
        #expect(series.metric == "github-stars")
        #expect(series.value == 412)
    }

    @Test("the manifest supplies what the run leaves out")
    func manifestDefaults() {
        let series = Self.value(412).series(manifest: Self.manifest, window: .of(.month))
        #expect(series.unit == .count)
        #expect(series.format == MetricFormat())

        // ...and the run wins where it says something, because the schema
        // lets it and silently keeping the manifest's would mislabel it.
        let overridden = Self.value(1999, unit: .currency, currency: "usd")
            .series(manifest: Self.manifest, window: .of(.month))
        #expect(overridden.unit == .currency)
        #expect(overridden.currency == "usd")
    }

    @Test("a currency is dropped on a metric that is not money")
    func currencyOnlyWhereItMeans() {
        // A count with a currency attached renders as "$412 stars" if any
        // formatter trusts it.
        let series = Self.value(412, unit: .count, currency: "usd")
            .series(manifest: Self.manifest, window: .of(.month))
        #expect(series.currency == nil)
    }

    @Test("no series means no points, not one invented at now")
    func noInventedLine() {
        let series = Self.value(412).series(manifest: Self.manifest, window: .of(.month))
        // A single reading drawn as a line is the flat line that looks like
        // data. The snapshot shapes on the server side make the same choice.
        #expect(series.points.isEmpty)
    }

    @Test("points pass through when the plugin reports them")
    func pointsPassThrough() {
        let points = [
            MetricPoint(t: "2026-10-01T00:00:00.000Z", v: 1),
            MetricPoint(t: "2026-10-02T00:00:00.000Z", v: 3),
        ]
        let series = Self.value(4, series: points)
            .series(manifest: Self.manifest, window: .of(.month))
        #expect(series.points.count == 2)
        #expect(series.points.last?.v == 3)
    }

    @Test("the delta is absolute always, percent only where it means something")
    func deltas() {
        let up = Self.value(110, previousValue: 100)
            .series(manifest: Self.manifest, window: .of(.month))
        #expect(up.delta?.absolute == 10)
        #expect(up.delta?.percent == 10)

        // Zero to five is an infinite increase, not a 100% one.
        let fromZero = Self.value(5, previousValue: 0)
            .series(manifest: Self.manifest, window: .of(.month))
        #expect(fromZero.delta?.absolute == 5)
        #expect(fromZero.delta?.percent == nil)

        // No previous window at all is no delta, which is different from a
        // delta of zero.
        let none = Self.value(5).series(manifest: Self.manifest, window: .of(.month))
        #expect(none.delta == nil)
    }

    @Test("a negative previous still gives a sensible percentage")
    func negativePrevious() {
        // -10 → -5 is an improvement of 5, i.e. +50% of the magnitude. Dividing
        // by the signed value would report -50% and draw a red arrow on a
        // number that got better.
        let series = Self.value(-5, previousValue: -10)
            .series(manifest: Self.manifest, window: .of(.month))
        #expect(series.delta?.absolute == 5)
        #expect(series.delta?.percent == 50)
    }

    @Test("generatedAt is the provider's asOf when there is one")
    func asOfWins() {
        let stamped = Self.value(412, asOf: "2026-10-01T00:00:00.000Z")
            .series(manifest: Self.manifest, window: .of(.month))
        // The age of the *number*, not of the run that fetched it — otherwise
        // a figure the provider computed yesterday reads as current.
        #expect(stamped.generatedAt == "2026-10-01T00:00:00.000Z")

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let unstamped = Self.value(412)
            .series(manifest: Self.manifest, window: .of(.month), generatedAt: now)
        #expect(unstamped.generatedAt == ISO8601.string(from: now))
    }

    @Test("a plugin has no list shape yet, and says so with nil")
    func itemsAreNilNotEmpty() {
        let series = Self.value(412).series(manifest: Self.manifest, window: .of(.month))
        // Nil, so a tile can tell "not a list" from "a list with nothing in
        // it" — the same distinction the Worker's `items` makes.
        #expect(series.items == nil)
    }
}

/// The window a local run is for.
///
/// This is the one place the Mac has to compute a window itself. Everywhere
/// else it sends a range and the Worker derives `from`/`to`, so if these two
/// disagree the same widget means different things depending on where its
/// number came from.
struct PluginWindowTests {
    @Test("each range maps to the bucket the server would have chosen")
    func granularities() {
        // Mirrors DEFAULT_GRANULARITY in packages/schemas, which the configure
        // pane also duplicates. Three copies now; this is the one that would
        // otherwise be unchecked.
        #expect(PluginWindow.of(.day).granularity == .hour)
        #expect(PluginWindow.of(.week).granularity == .day)
        #expect(PluginWindow.of(.month).granularity == .day)
        #expect(PluginWindow.of(.quarter).granularity == .week)
        #expect(PluginWindow.of(.year).granularity == .month)
    }

    @Test("each range is as long as RANGE_DURATION_MS says")
    func durations() {
        let day: TimeInterval = 24 * 60 * 60
        #expect(TimeRange.day.duration == day)
        #expect(TimeRange.week.duration == 7 * day)
        #expect(TimeRange.month.duration == 30 * day)
        #expect(TimeRange.quarter.duration == 90 * day)
        // 365 days, not twelve calendar months — as the table in
        // packages/schemas has it.
        #expect(TimeRange.year.duration == 365 * day)
    }

    @Test("the window ends now and starts a range earlier")
    func bounds() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let window = PluginWindow.of(.week, now: now)
        #expect(window.to == now)
        #expect(window.from == now.addingTimeInterval(-7 * 24 * 60 * 60))
        #expect(window.range == .week)
    }
}
