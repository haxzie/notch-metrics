import Foundation
import MetricsCore

/// PostHog's metrics, read on this Mac.
///
/// Ported from `packages/integrations/src/providers/posthog/index.ts`. The
/// five differ only by a `Spec` — which table, which time column, which
/// aggregate, and whether a distinct count makes the window total something
/// other than the sum of its buckets — exactly as they do in the Worker.
///
/// The HogQL strings are the contract and are ported word for word. A
/// reworded query is a different number, and nobody notices until the tile
/// disagrees with PostHog's own dashboard.
extension PostHogProvider {
    /// How a metric is counted, and out of which table.
    struct Spec {
        /// `events` or `persons`.
        let table: String
        /// The time column bucketed and filtered on.
        let time: String
        /// The aggregate. `count()` sums; a `DISTINCT` does not — see `distinct`.
        let aggregate: String
        /// Extra `WHERE` terms, already safe to inline.
        let filter: String?
        /// Whether the window total differs from the sum of its buckets.
        ///
        /// A distinct count does: one person active on three days is three
        /// bars and one user. Those metrics pay for a second query rather
        /// than reporting a headline that is the sum of its own chart and
        /// wrong.
        let distinct: Bool

        init(table: String, time: String, aggregate: String, filter: String? = nil, distinct: Bool) {
            self.table = table
            self.time = time
            self.aggregate = aggregate
            self.filter = filter
            self.distinct = distinct
        }
    }

    /// The five metrics the Worker implements, by the id the catalogue serves.
    static let specs: [String: Spec] = [
        "active_users": Spec(
            table: "events", time: "timestamp",
            // A distinct count, so the window total is not the sum of its
            // buckets.
            aggregate: "count(DISTINCT person_id)", distinct: true),
        "new_users": Spec(
            table: "persons", time: "created_at", aggregate: "count()", distinct: false),
        "events": Spec(
            table: "events", time: "timestamp", aggregate: "count()", distinct: false),
        "pageviews": Spec(
            table: "events", time: "timestamp", aggregate: "count()",
            filter: "event = '$pageview'", distinct: false),
        "sessions": Spec(
            table: "events", time: "timestamp",
            aggregate: "count(DISTINCT properties.$session_id)",
            filter: "properties.$session_id IS NOT NULL", distinct: true),
    ]

    public func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let creds = try Self.credentials(credentials)
        guard let spec = Self.specs[window.metric] else {
            // Not a bug: the catalogue is the Worker's and lists metrics this
            // build has not been taught yet. The caller falls back to the API.
            throw ProviderFailure.unsupported("This build cannot read PostHog's \(window.metric) yet.")
        }

        let project = try await Self.resolveProject(creds, http: http)
        let rows = try await Self.buckets(
            creds, project: project, spec: spec, metric: window.metric, window: window, http: http)
        // The later half only. `span` widened the query backwards when a
        // delta was asked for, and the chart draws the requested window.
        let current = rows.filter { $0.at >= window.from }

        // Safe despite the query having bucketed already: `floorOf` only ever
        // floors to an hour or a day, so every row is a distinct, disjoint
        // bucket and summing them into a week or a month is the rollup rather
        // than a second count of the same events. Asking ClickHouse for the
        // weekly roll-up instead would mean the two-argument form of
        // `toStartOfWeek` and a timezone decision in a second place.
        let points = bucketSum(
            current.map { (at: $0.at, amount: $0.amount) },
            from: window.from, to: window.to,
            granularity: window.granularity, timeZone: window.timeZone)
        let series = window.wantSeries ? points : []

        if !spec.distinct {
            return MetricValue(
                value: current.reduce(0) { $0 + $1.amount },
                // Gated on the flag rather than on what came back: a row from
                // before the window would otherwise become a delta nobody
                // asked for, and an absent delta is nil rather than zero —
                // zero renders as "down 100%".
                previousValue: window.comparePrevious
                    ? rows.filter { $0.at < window.from }.reduce(0) { $0 + $1.amount }
                    : nil,
                points: series)
        }

        // A second query rather than a headline that is the sum of its own
        // chart and wrong: one person active on three days is three bars and
        // one user.
        let totals = try await Self.windowTotals(
            creds, project: project, spec: spec, metric: window.metric, window: window, http: http)
        return MetricValue(
            value: totals.current, previousValue: totals.previous, points: series)
    }

    // MARK: - Queries

    /// One row per bucket, as a date and a count.
    static func buckets(
        _ creds: Credentials, project: String, spec: Spec, metric: String,
        window: MetricWindow, http: ProviderHTTP
    ) async throws -> [(at: Date, amount: Double)] {
        let span = span(window)
        let floor = floorOf(window.granularity)
        let rows = try await hogql(
            creds, project: project,
            query: "SELECT toUnixTimestamp(\(floor)(\(spec.time))) AS bucket, "
                + "\(spec.aggregate) AS value "
                + "FROM \(spec.table) WHERE \(range(spec, from: span.start, to: span.end)) "
                + "GROUP BY bucket ORDER BY bucket",
            name: "\(metric).series", http: http)

        // A row short of its two columns is dropped rather than read with an
        // index that is not there.
        return rows.filter { $0.count >= 2 }.map { row in
            (at: Date(timeIntervalSince1970: row[0].number), amount: row[1].number)
        }
    }

    /// Both windows' de-duplicated totals, in one query.
    ///
    /// Grouping on the comparison itself rather than asking twice: the rows
    /// are already being scanned, and a second round trip would bill the read
    /// budget for the same bytes again.
    static func windowTotals(
        _ creds: Credentials, project: String, spec: Spec, metric: String,
        window: MetricWindow, http: ProviderHTTP
    ) async throws -> (current: Double, previous: Double?) {
        let span = span(window)
        let rows = try await hogql(
            creds, project: project,
            query: "SELECT \(spec.time) >= toDateTime(\(seconds(window.from))) AS is_current, "
                + "\(spec.aggregate) AS value FROM \(spec.table) "
                + "WHERE \(range(spec, from: span.start, to: span.end)) GROUP BY is_current",
            name: "\(metric).total", http: http)

        var current: Double = 0
        var previous: Double = 0
        for row in rows where row.count >= 2 {
            if row[0].isTrue { current = row[1].number } else { previous = row[1].number }
        }
        // nil rather than the zero the earlier half really is: a tile that
        // did not ask for a delta must not be shown one.
        return (current: current, previous: window.comparePrevious ? previous : nil)
    }

    // MARK: - Query fragments

    /// `toStartOfHour` for an hour, `toStartOfDay` for everything else.
    ///
    /// Weeks and months are rolled up from days in `bucketSum` rather than
    /// asked of ClickHouse, which keeps this to the one-argument form of each
    /// function and puts every timezone decision in one place.
    static func floorOf(_ granularity: Granularity) -> String {
        granularity == .hour ? "toStartOfHour" : "toStartOfDay"
    }

    /// Epoch seconds. `toDateTime(<int>)` is the one date literal with no
    /// timezone in it, so the query cannot be read in the server's.
    static func seconds(_ date: Date) -> Int {
        Int(date.timeIntervalSince1970.rounded(.down))
    }

    /// The window a query covers: the requested one, widened to include the
    /// compare window so both come back in a single call.
    static func span(_ window: MetricWindow) -> (start: Date, end: Date) {
        let length = window.to.timeIntervalSince(window.from)
        return (
            start: window.comparePrevious ? window.from.addingTimeInterval(-length) : window.from,
            end: window.to
        )
    }

    /// Half-open on purpose: `<` on the upper bound, so a bucket boundary
    /// cannot be counted by both this window and the next one.
    static func range(_ spec: Spec, from: Date, to: Date) -> String {
        var terms = [
            "\(spec.time) >= toDateTime(\(seconds(from)))",
            "\(spec.time) < toDateTime(\(seconds(to)))",
        ]
        if let filter = spec.filter { terms.append(filter) }
        return terms.joined(separator: " AND ")
    }
}
