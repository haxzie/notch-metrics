import Foundation
import MetricsCore

/// Plausible's metrics, read on this Mac.
///
/// Ported from `packages/integrations/src/providers/plausible/index.ts`, and
/// the arithmetic is deliberately the same arithmetic: a widget must not
/// change its number because the fetch moved off the Worker.
///
/// All four metrics ask Plausible the same two or three questions and differ
/// only in what it calls the metric and whether the number needs dividing, so
/// there is one function here and four rows in a table — the same shape the
/// Worker's `statsMetric` settled on after two side tables had to agree with
/// each other and silently did not.
extension PlausibleProvider {
    /// One Plausible metric, which is four metrics minus a name and a scale.
    struct StatsMetric: Sendable {
        /// What Plausible calls it. It says "visits" where everything else
        /// here says sessions.
        let apiMetric: String
        /// Plausible reports `bounce_rate` as a percentage and the catalogue
        /// declares a ratio, which is a fraction.
        let scale: @Sendable (Double) -> Double
    }

    static let statsMetrics: [String: StatsMetric] = [
        "visitors": StatsMetric(apiMetric: "visitors", scale: { $0 }),
        "pageviews": StatsMetric(apiMetric: "pageviews", scale: { $0 }),
        "bounce_rate": StatsMetric(apiMetric: "bounce_rate", scale: { $0 / 100 }),
        // Plausible says "visits"; every other connector here says sessions.
        "sessions": StatsMetric(apiMetric: "visits", scale: { $0 }),
    ]

    public func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let creds = try Self.credentials(credentials)
        guard let metric = Self.statsMetrics[window.metric] else {
            // Not a bug: the catalogue is the Worker's and lists metrics this
            // build has not been taught. The caller falls back to the API.
            throw ProviderFailure.unsupported(
                "This build cannot read Plausible's \(window.metric) yet.")
        }

        // Asked for separately rather than summed off the chart, for both of
        // the metrics where those differ: a visitor active on three days is
        // one unique visitor, and a bounce rate is a ratio, not an addend.
        // Plausible also warns that `visitors` and `visits` may come from
        // different tables depending on the query, so its own aggregate is the
        // figure that matches its own dashboard.
        let value = try await total(
            metric, credentials: creds, from: window.from, to: window.to, http: http)

        // Two requests rather than one. Plausible v2 can compare a range
        // against the one before it, but only against its own idea of the
        // previous period for a *shorthand* range — and these ranges are
        // explicit instants from the widget, so there is nothing for it to
        // derive. The Worker asks twice for the same reason.
        //
        // Nil rather than zero when the tile wants no delta: zero would
        // render as a 100% rise from nothing.
        var previousValue: Double?
        if window.comparePrevious {
            let span = window.to.timeIntervalSince(window.from)
            previousValue = try await total(
                metric, credentials: creds, from: window.from.addingTimeInterval(-span),
                to: window.from, http: http)
        }

        // One row per bucket, bucketed by Plausible itself at the granularity
        // asked for — so a week is weighted by its own sessions rather than
        // being the mean of seven daily rates, which is what rolling days up
        // here would produce. `bucketSum` is then only gap-filling: it sees
        // one row per bucket, so nothing is added to anything, and every
        // bucket Plausible omitted is emitted as a zero rather than being a
        // gap a chart draws a line straight over.
        var points: [MetricPoint] = []
        if window.wantSeries {
            let rows = try await query(
                metric.apiMetric, credentials: creds, from: window.from, to: window.to,
                dimension: "time:\(window.granularity.rawValue)", http: http)
            points = bucketSum(
                try rows.map { row in
                    (
                        at: try Self.instant(
                            ofBucketLabel: row.dimensions?.first ?? "", timeZone: window.timeZone),
                        amount: metric.scale(Self.number(row.metrics?.first ?? nil))
                    )
                },
                from: window.from, to: window.to,
                granularity: window.granularity, timeZone: window.timeZone)
        }

        return MetricValue(
            value: value, previousValue: previousValue, points: points, currency: nil)
    }

    // MARK: - The Stats API

    /// The single figure for a window, from a query with no time dimension.
    private func total(
        _ metric: StatsMetric, credentials: Credentials, from: Date, to: Date, http: ProviderHTTP
    ) async throws -> Double {
        let rows = try await query(
            metric.apiMetric, credentials: credentials, from: from, to: to, dimension: nil,
            http: http)
        return metric.scale(Self.number(rows.first?.metrics?.first ?? nil))
    }

    /// One Stats API query.
    ///
    /// `date_range` is a pair of instants rather than one of Plausible's
    /// shorthands ("7d", "month"): the window comes from the widget, and the
    /// shorthands are relative to Plausible's own idea of today.
    ///
    /// Instants rather than `YYYY-MM-DD` for the same reason the Worker sends
    /// them. A day pair is rounded to whole days in the site's zone, which
    /// turns an hourly widget's "the last 24 hours" into two whole calendar
    /// days and roughly doubles its number.
    private func query(
        _ apiMetric: String, credentials: Credentials, from: Date, to: Date, dimension: String?,
        http: ProviderHTTP
    ) async throws -> [QueryResult.Row] {
        let body = try JSONEncoder().encode(
            Query(
                siteID: credentials.siteID, metrics: [apiMetric],
                dateRange: [Self.iso8601(from), Self.iso8601(to)],
                dimensions: dimension.map { [$0] }))

        let result = try await Self.send(
            QueryResult.self, "/api/v2/query", method: "POST", credentials: credentials,
            body: body, http: http)
        return result.results ?? []
    }

    // MARK: - Dates

    /// An instant, to the second.
    ///
    /// Fixed to POSIX and Gregorian by `ISO8601DateFormatter`, so a user on a
    /// non-Gregorian calendar does not put a Buddhist year in the body and get
    /// a 400 back.
    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Reads one of Plausible's bucket labels.
    ///
    /// Plausible labels a bucket `2026-10-05` or `2026-10-05 14:00:00`, with
    /// no offset, in the site's reporting timezone. Read as the window's own
    /// zone rather than as UTC or as the machine default: the two agree for
    /// almost everybody — Plausible is configured once, to where you are —
    /// and when they do not, this only shifts where a bar sits, never what it
    /// counts. The machine default would additionally disagree with the zone
    /// `bucketSum` is about to bucket in, which puts a bar in the wrong
    /// bucket or outside the window entirely.
    static func instant(ofBucketLabel label: String, timeZone: TimeZone) throws -> Date {
        guard let match = label.prefixMatch(
            of: /(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2}))?/)
        else {
            throw ProviderFailure.badResponse("Plausible returned an unreadable bucket: \(label)")
        }

        var components = DateComponents()
        components.year = Int(match.output.1)
        components.month = Int(match.output.2)
        components.day = Int(match.output.3)
        components.hour = match.output.4.flatMap { Int($0) } ?? 0
        components.minute = match.output.5.flatMap { Int($0) } ?? 0

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // `Calendar` samples the zone's offset at the instant it resolves,
        // which is the two-pass dance the Worker's `instantOfWallClock` has to
        // do by hand across a DST change.
        guard let date = calendar.date(from: components) else {
            throw ProviderFailure.badResponse("Plausible returned an unreadable bucket: \(label)")
        }
        return date
    }

    /// A missing or non-finite figure is a zero.
    ///
    /// Plausible sends `null` for a bucket it has no rows for, and a nil that
    /// propagated into the sum would make the whole window's figure nil.
    static func number(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return value
    }
}

/// Plausible's wire shapes, nested under the adapter that reads them.
///
/// Nested rather than at file scope because `Query`, `QueryResult` and `Site`
/// are names every analytics provider in this module wants. At the top level
/// the second one to be written fails to compile, and the error names a file
/// its author never touched.
extension PlausibleProvider {
    struct Query: Encodable {
        let siteID: String
        let metrics: [String]
        /// A pair of ISO-8601 instants.
        let dateRange: [String]
        /// Omitted entirely for a window total, which is not the same request
        /// as one dimensioned by time.
        let dimensions: [String]?

        enum CodingKeys: String, CodingKey {
            case siteID = "site_id"
            case metrics
            case dateRange = "date_range"
            case dimensions
        }
    }

    struct QueryResult: Decodable {
        let results: [Row]?

        struct Row: Decodable {
            /// One entry per requested metric, and Plausible sends `null` for
            /// a bucket with no rows in it.
            let metrics: [Double?]?
            let dimensions: [String]?
        }
    }
}
