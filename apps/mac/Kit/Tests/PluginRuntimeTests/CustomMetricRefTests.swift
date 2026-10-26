import Foundation
import MetricsCore
import Testing

@testable import PluginRuntime

/// Which app and which metric a `custom_metric` widget points at.
///
/// `NotchWidget.customMetricId` is one string and a persisted wire field, so
/// connectors pack two ids into it rather than growing the shape. The packing
/// has to be reversible and, more importantly, has to keep reading every
/// widget already on disk — all of which predate connectors entirely.
struct CustomMetricRefTests {
    @Test("a bare id is a single-metric plugin, which is what is already stored")
    func bareIdIsLegacy() {
        let ref = CustomMetricRef(packed: "zod-downloads")
        #expect(ref.isConnector == false)
        #expect(ref.appId == nil)
        #expect(ref.metricId == "zod-downloads")
        // Round-trips unchanged, so re-saving a layout cannot rewrite an id
        // the refresh loop then fails to find.
        #expect(ref.packed == "zod-downloads")
    }

    @Test("app and metric survive the round trip")
    func roundTrip() {
        let ref = CustomMetricRef(appId: "npm-stats", metricId: "zod_downloads")
        #expect(ref.packed == "npm-stats/zod_downloads")

        let parsed = CustomMetricRef(packed: ref.packed)
        #expect(parsed.isConnector)
        #expect(parsed.appId == "npm-stats")
        #expect(parsed.metricId == "zod_downloads")
    }

    @Test("a hyphenated app id is not mistaken for part of the metric")
    func hyphensSurvive() {
        // Connector ids allow hyphens and metric ids allow underscores, so the
        // split is on the first slash rather than on any other character.
        let parsed = CustomMetricRef(packed: "my-local-app/open_issues")
        #expect(parsed.appId == "my-local-app")
        #expect(parsed.metricId == "open_issues")
    }

    @Test("a malformed value resolves to something rather than crashing")
    func malformed() {
        // Reachable by hand-editing layout.json. None of these should be read
        // as a connector, because the app id would be empty and no run could
        // be addressed to it.
        for packed in ["/open_issues", "app/", "/", ""] {
            let ref = CustomMetricRef(packed: packed)
            #expect(ref.isConnector == false, "\(packed) should not parse as a connector")
        }
    }

    @Test("only the first slash splits")
    func firstSlashOnly() {
        let ref = CustomMetricRef(packed: "app/weird/metric")
        #expect(ref.appId == "app")
        // The remainder is kept whole. It will not match any declared metric
        // and the tile says so, which is better than silently addressing a
        // different one.
        #expect(ref.metricId == "weird/metric")
    }
}

/// A custom app's answer becoming the shape every tile draws.
struct ConnectorSeriesTests {
    static func descriptor(
        id: String = "open_issues", unit: MetricUnit = .count, currency: String? = nil,
        shape: ConnectorMetricShape = .scalar
    ) -> ConnectorMetricDescriptor {
        ConnectorMetricDescriptor(
            id: id, label: "Open issues", shortLabel: "Open", unit: unit, currency: currency,
            format: nil, shape: shape, methodology: "m", params: nil, freshnessSeconds: nil,
            linkTemplate: nil)
    }

    @Test("a connector series carries no integration, which is how it is told apart")
    func noIntegration() {
        let series = ConnectorMetricValue(value: 12)
            .series(descriptor: Self.descriptor(), window: .of(.month))
        // Nil is the signal: `adoptConnections` binds only widgets that have
        // one, and the "which account?" subtitle resolves from it.
        #expect(series.integrationId == nil)
        #expect(series.metric == "open_issues")
        #expect(series.value == 12)
    }

    @Test("a currency is dropped on a metric that is not money")
    func currencyOnlyWhereItMeans() {
        // A count carrying a currency renders as "$12 issues" if any formatter
        // trusts it.
        let series = ConnectorMetricValue(value: 12, currency: "usd")
            .series(descriptor: Self.descriptor(unit: .count), window: .of(.month))
        #expect(series.currency == nil)

        let money = ConnectorMetricValue(value: 1999, currency: "usd")
            .series(descriptor: Self.descriptor(unit: .currency), window: .of(.month))
        #expect(money.currency == "usd")
    }

    @Test("the descriptor's currency is used when the run omits one")
    func currencyFallsBackToDescriptor() {
        let series = ConnectorMetricValue(value: 1999)
            .series(
                descriptor: Self.descriptor(unit: .currency, currency: "eur"),
                window: .of(.month))
        #expect(series.currency == "eur")
    }

    @Test("the delta is absolute always, percent only where it means something")
    func deltas() {
        let up = ConnectorMetricValue(value: 110, previousValue: 100)
            .series(descriptor: Self.descriptor(), window: .of(.month))
        #expect(up.delta?.absolute == 10)
        #expect(up.delta?.percent == 10)

        // Zero to five is an infinite increase, not a 100% one.
        let fromZero = ConnectorMetricValue(value: 5, previousValue: 0)
            .series(descriptor: Self.descriptor(), window: .of(.month))
        #expect(fromZero.delta?.percent == nil)

        let none = ConnectorMetricValue(value: 5)
            .series(descriptor: Self.descriptor(), window: .of(.month))
        #expect(none.delta == nil)
    }

    @Test("list rows pass through, and nil stays nil")
    func items() {
        // Nil rather than empty, so a tile can tell "not a list" from "a list
        // with nothing in it" — the distinction the Worker's `items` makes.
        let scalar = ConnectorMetricValue(value: 1)
            .series(descriptor: Self.descriptor(), window: .of(.month))
        #expect(scalar.items == nil)

        let rows = [
            MetricListItem(
                id: "1", t: "2026-10-01T00:00:00.000Z", label: "Fix the notch", detail: nil,
                amount: nil, currency: nil, status: nil, state: nil)
        ]
        let list = ConnectorMetricValue(value: 1, items: rows)
            .series(descriptor: Self.descriptor(shape: .list(limit: 10)), window: .of(.month))
        #expect(list.items?.count == 1)
    }

    @Test("generatedAt is the connector's asOf when there is one")
    func asOfWins() {
        let stamped = ConnectorMetricValue(value: 12, asOf: "2026-10-01T00:00:00.000Z")
            .series(descriptor: Self.descriptor(), window: .of(.month))
        // The age of the *number*, not of the run that fetched it — otherwise
        // a figure computed yesterday reads as current.
        #expect(stamped.generatedAt == "2026-10-01T00:00:00.000Z")
    }
}

/// When each custom app is next allowed to run.
struct ConnectorSchedulerTests {
    static func app(
        id: String = "linear", every seconds: Int = 900, state: PluginState = .ready,
        digest: String = "aaa"
    ) -> LoadedConnector {
        let manifest = ConnectorManifest(
            schemaVersion: 1, id: id, name: id, description: "d", appId: "custom", author: nil,
            version: "1.0.0", icon: nil, authMode: .apiKey, auth: [], hostCredentials: nil,
            allowedHosts: ["api.linear.app"],
            metrics: [
                ConnectorMetricDescriptor(
                    id: "open_issues", label: "Open", shortLabel: "Open", unit: .count,
                    currency: nil, format: nil, shape: .scalar, methodology: "m", params: nil,
                    freshnessSeconds: nil, linkTemplate: nil)
            ],
            refreshIntervalSeconds: seconds, timeoutMs: 8000, entry: "connector.mjs",
            createdAt: "2026-10-05T12:00:00.000Z", updatedAt: "2026-10-05T12:00:00.000Z")
        return LoadedConnector(
            id: id, directory: URL(fileURLWithPath: "/tmp/\(id)"), manifest: manifest,
            state: state, contentHash: digest)
    }

    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("an app that has never run is due")
    func neverRun() async {
        let scheduler = ConnectorScheduler()
        #expect(await scheduler.isDue(Self.app(), now: Self.t0))
    }

    @Test("it is not due again until its own interval has passed")
    func honoursItsInterval() async {
        let scheduler = ConnectorScheduler()
        let app = Self.app(every: 900)
        await scheduler.recordRun(app, at: Self.t0)

        #expect(await scheduler.isDue(app, now: Self.t0.addingTimeInterval(899)) == false)
        #expect(await scheduler.isDue(app, now: Self.t0.addingTimeInterval(900)))
    }

    @Test("an app asking to run every second gets a minute")
    func floorIsApplied() async {
        let scheduler = ConnectorScheduler()
        let hasty = Self.app(every: 1)
        await scheduler.recordRun(hasty, at: Self.t0)

        #expect(await scheduler.isDue(hasty, now: Self.t0.addingTimeInterval(59)) == false)
        #expect(await scheduler.isDue(hasty, now: Self.t0.addingTimeInterval(60)))
    }

    @Test("only an approved, unmodified app ever runs")
    func stateGate() async {
        let scheduler = ConnectorScheduler()
        // Enforced here as well as in the refresh loop, because `ConnectorRunner`
        // can be called directly and one gate is not enough.
        #expect(await scheduler.isDue(Self.app(state: .pendingApproval), now: Self.t0) == false)
        #expect(await scheduler.isDue(Self.app(state: .modified), now: Self.t0) == false)
        #expect(
            await scheduler.isDue(Self.app(state: .invalid(reason: "x")), now: Self.t0) == false)
        #expect(await scheduler.isDue(Self.app(state: .ready), now: Self.t0))
    }

    @Test("rewritten code does not wait out the old version's interval")
    func digestResetsTheClock() async {
        let scheduler = ConnectorScheduler()
        let before = Self.app(digest: "aaa")
        await scheduler.recordRun(before, at: Self.t0)
        #expect(await scheduler.isDue(before, now: Self.t0.addingTimeInterval(10)) == false)

        let after = Self.app(digest: "bbb")
        #expect(await scheduler.isDue(after, now: Self.t0.addingTimeInterval(10)))
    }

    @Test("a removed and re-added app does not inherit its old timestamp")
    func retainForgets() async {
        let scheduler = ConnectorScheduler()
        let app = Self.app()
        await scheduler.recordRun(app, at: Self.t0)
        #expect(await scheduler.isDue(app, now: Self.t0.addingTimeInterval(10)) == false)

        await scheduler.retain(ids: [])
        #expect(await scheduler.isDue(app, now: Self.t0.addingTimeInterval(10)))
    }
}

/// Answers finding their way back to the right tile.
struct ConnectorOutcomeRoutingTests {
    static func decode(_ json: String) throws -> [ConnectorMetricOutcome] {
        try JSONDecoder().decode(ConnectorRunResult.self, from: Data(json.utf8)).outcomes
    }

    @Test("two answers for one metric are told apart by the request id")
    func sameMetricDifferentWidgets() throws {
        // The bug this pins: both tiles are the same app and the same metric,
        // differing only in params — one npm package each. Keyed by
        // `outcome.metric` the second answer overwrote the first and both
        // tiles drew one package's number and one package's chart.
        let outcomes = try Self.decode(
            """
            {"ok":true,"durationMs":1,"outcomes":[
              {"ok":true,"id":"w_AAA","metric":"downloads","result":{"value":1533}},
              {"ok":true,"id":"w_BBB","metric":"downloads","result":{"value":3820061}}
            ]}
            """)

        var byWidget: [String: ConnectorMetricOutcome] = [:]
        for outcome in outcomes { byWidget[outcome.id] = outcome }
        #expect(byWidget.count == 2)

        guard case let .success(_, _, first) = try #require(byWidget["w_AAA"]),
            case let .success(_, _, second) = try #require(byWidget["w_BBB"])
        else {
            Issue.record("expected both to succeed")
            return
        }
        #expect(first.value == 1533)
        #expect(second.value == 3_820_061)
    }

    @Test("a failed answer still names its widget")
    func failureCarriesTheId() throws {
        // Without an id a failure cannot be delivered either, and the tile
        // that asked would sit on a spinner while a different one showed the
        // error.
        let outcomes = try Self.decode(
            """
            {"ok":false,"durationMs":1,"outcomes":[
              {"ok":false,"id":"w_AAA","metric":"downloads","code":"runtime","message":"boom"}
            ]}
            """)
        #expect(outcomes.first?.id == "w_AAA")
    }

    @Test("an outcome from a runner with no id falls back to the metric")
    func olderRunnerStillRoutes() throws {
        // The app ships its own runner, so this is the development case of a
        // stale `NOTCH_RUNNER_PATH`. One widget per metric still routes; two
        // would collide, which is no worse than that runner could manage.
        let outcomes = try Self.decode(
            """
            {"ok":true,"durationMs":1,"outcomes":[
              {"ok":true,"metric":"downloads","result":{"value":7}}
            ]}
            """)
        #expect(outcomes.first?.id == "downloads")
    }
}
