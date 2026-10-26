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
        // covered separately in `PluginRuntimeTests`. That deferral was empty
        // for a while — the target did not exist, so "covered separately"
        // meant covered nowhere.
        let notDecodedHere: Set<String> = [
            "provider-manifest-list", "integration", "plugin-manifest", "connector-manifest",
        ]
        let decoded: Set<String> = [
            "metric-series", "metric-series-empty", "metric-series-no-currency",
            "metric-series-list", "metric-series-ci", "metric-error", "metric-batch",
            "widget-layout",
            "latest-json",
            "notification-feed", "notification-feed-empty", "notification-feed-truncated",
            "notification-settings",
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

    @Test("a CI list decodes one row per outcome the tile can draw")
    func ciSeries() throws {
        let result = try JSONDecoder().decode(
            MetricResult.self, from: Self.load("metric-series-ci"))
        let series = try #require(result.series)
        let items = try #require(series.items)
        #expect(items.map(\.state) == [.succeeded, .failed, .running, .neutral])
        // The provider's own word survives beside the state it was collapsed
        // to: the tooltip says what GitHub said.
        #expect(items.last?.status == "cancelled")
        // A row with an outcome and no money. Reading `amount` as 0 here would
        // put a currency figure on a build.
        #expect(items.allSatisfy { $0.amount == nil })
    }

    @Test("a state this build predates decodes as unknown, not as a failure")
    func unknownState() throws {
        // Inline rather than a committed fixture: a fixture carrying this
        // would not be a valid `MetricResult`, and the one thing the fixtures
        // have to be is the wire shape. What is being proved is the enum's
        // fallback — the reason an old app survives a server that learns a new
        // word — and a row's worth of JSON proves it exactly.
        let row = Data(
            """
            {"id":"1","t":"2026-10-05T11:42:00.000Z","label":"Cut 0.2.1","detail":null,
             "amount":null,"currency":null,"status":"something_github_added",
             "state":"nebulous"}
            """.utf8)
        let item = try JSONDecoder().decode(MetricListItem.self, from: row)
        #expect(item.state == .unknown)
        #expect(item.status == "something_github_added")
    }

    @Test("a payments row has no state, rather than a guessed one")
    func paymentsHaveNoState() throws {
        let result = try JSONDecoder().decode(
            MetricResult.self, from: Self.load("metric-series-list"))
        let series = try #require(result.series)
        let items = try #require(series.items)
        #expect(items.allSatisfy { $0.state == nil })
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

    @Test("the notification feed decodes, newest first by occurredAt")
    func notificationFeed() throws {
        let page = try JSONDecoder().decode(
            AlertFeedPage.self, from: Self.load("notification-feed"))

        #expect(page.items.count == 3)
        #expect(page.unread == 2)
        // Page one of two: `hasMore` is what tells the pane there is history
        // behind it, and `oldestSeq` is the cursor to ask with.
        #expect(page.hasMore)
        #expect(page.oldestSeq == 410)
        #expect(!page.truncated)
        #expect(page.connections.count == 1)

        let first = try #require(page.items.first)
        #expect(first.severity == .success)
        #expect(first.amount == 9_900)
        #expect(first.currency == "USD")
        #expect(first.occurred != nil)
        // The link is what a click opens, so it has to survive the decode as a
        // parseable https URL rather than just a string.
        #expect(first.link?.host == "dashboard.stripe.com")

        // A threshold row carries no money and nowhere to go.
        let threshold = try #require(page.items.first { $0.typeId == "metric_threshold_crossed" })
        #expect(threshold.amount == nil)
        #expect(threshold.currency == nil)
        #expect(threshold.link == nil)

        // Raised inside quiet hours: filed, never raised.
        let quiet = try #require(page.items.first { $0.read })
        #expect(!quiet.alert)
        // Its connection is gone, which the row is built to survive.
        #expect(quiet.integrationId == nil)
        #expect(quiet.provider == "stripe")
    }

    @Test("an empty page still carries its sidebar, and a null cursor")
    func notificationFeedEmpty() throws {
        let page = try JSONDecoder().decode(
            AlertFeedPage.self, from: Self.load("notification-feed-empty"))

        #expect(page.items.isEmpty)
        // The case that breaks a sidebar decoder: nothing to show, but a
        // connection that still has to be listed.
        #expect(page.connections.count == 1)
        #expect(!page.hasMore)
        // Null rather than zero. Treating it as zero re-requests the whole
        // archive on every poll, forever.
        #expect(page.oldestSeq == nil)
        #expect(page.pollAfterSeconds == 3600)
    }

    @Test("a truncated page sets both flags independently")
    func notificationFeedTruncated() throws {
        let page = try JSONDecoder().decode(
            AlertFeedPage.self, from: Self.load("notification-feed-truncated"))

        // Two different facts: there is more archive to walk, *and* the live
        // gap was too wide to banner row by row. Collapsing them into one flag
        // makes a long scroll go silent and a quiet catch-up look like the end
        // of the list.
        #expect(page.hasMore)
        #expect(page.truncated)
        #expect(page.unread == 183)
    }

    @Test("notification settings decode, and round-trip")
    func notificationSettings() throws {
        let data = try Self.load("notification-settings")
        let settings = try JSONDecoder().decode(AlertSettings.self, from: data)

        #expect(settings.revision == 3)
        #expect(settings.enabled)
        // Minutes from midnight, across midnight: 22:00 to 08:00.
        #expect(settings.quietFromMinute == 1_320)
        #expect(settings.quietToMinute == 480)
        #expect(settings.subscriptions.count == 2)

        // A disabled threshold must keep the bound the user typed — turning it
        // back on cannot lose the number.
        let threshold = try #require(settings.subscriptions.first { !$0.enabled })
        #expect(threshold.threshold?.metric == "mrr")
        #expect(threshold.threshold?.comparator == "below")
        #expect(threshold.threshold?.value == 1_000_000)
        #expect(threshold.params["account"] == "acct_1Nx")

        // The app PUTs this shape back, so the encode half matters as much as
        // the decode half — the same reason `MetricResult` is round-tripped.
        let again = try JSONDecoder().decode(
            AlertSettings.self, from: try JSONEncoder().encode(settings))
        #expect(again == settings)
    }

    @Test("an unknown severity falls back instead of failing the feed")
    func unknownSeverityFallsBack() throws {
        // The same bargain as `unknownEnumsFallBack` above, for the feed: a
        // severity the server invents must not blank every notification at once.
        let json = """
            {"id":"ntf_1","seq":1,"integrationId":null,"provider":"stripe",
             "connectionLabel":"Acme","typeId":"a_type_from_the_future",
             "severity":"apocalyptic","title":"Something","body":null,
             "amount":null,"currency":null,"url":null,
             "occurredAt":"2026-10-05T12:00:00.000Z",
             "createdAt":"2026-10-05T12:00:00.000Z","read":false,"alert":true}
            """
        let alert = try JSONDecoder().decode(NotchAlert.self, from: Data(json.utf8))
        #expect(alert.severity == .info)
        // And an unfamiliar type id stays a plain string rather than throwing.
        #expect(alert.typeId == "a_type_from_the_future")
    }

    @Test("a link the app cannot vouch for is not offered to the browser")
    func rejectsNonHttpsLink() throws {
        // The server host-checks against the provider's allowlist; this is the
        // other half, on the side that actually calls `NSWorkspace.open`.
        for hostile in ["file:///etc/passwd", "javascript:alert(1)", "not a url at all"] {
            let json = """
                {"id":"ntf_1","seq":1,"integrationId":null,"provider":"stripe",
                 "connectionLabel":"Acme","typeId":"payment_received",
                 "severity":"info","title":"x","body":null,"amount":null,
                 "currency":null,"url":"\(hostile)",
                 "occurredAt":"2026-10-05T12:00:00.000Z",
                 "createdAt":"2026-10-05T12:00:00.000Z","read":false,"alert":true}
                """
            let alert = try JSONDecoder().decode(NotchAlert.self, from: Data(json.utf8))
            #expect(alert.link == nil, "offered \(hostile) to the browser")
        }
    }
}
