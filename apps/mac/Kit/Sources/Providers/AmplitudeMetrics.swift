import Foundation
import MetricsCore

/// Amplitude's metrics, read on this Mac.
///
/// Ported from `packages/integrations/src/providers/amplitude/index.ts`. The
/// arithmetic is deliberately the same arithmetic, down to which headline
/// comes from Amplitude and which is summed here — a widget must not change
/// its number because the fetch moved off the Worker.
///
/// Two decisions in that file are the whole of this one:
///
/// - **Always `i=1`.** Amplitude's own `i=7` buckets a week from Sunday,
///   while every other series in the notch starts its week on a Monday, and
///   two chart tiles disagreeing about where a week begins is worse than one
///   extra sum here. So days come back daily and are rolled up locally with
///   `bucketSum` — the server aggregates *within* a day, this aggregates
///   across them, and neither double-counts the other.
/// - **Not every headline is the sum of its bars.** A de-duplicated user
///   count over a multi-day window cannot be had by adding up daily uniques:
///   that counts a person once per day they showed up. Amplitude returns the
///   window figure separately, in `seriesCollapsed`, and that is the headline
///   for the metrics where it exists.
extension AmplitudeProvider {
    /// How a metric is asked for, and whether its bars add up to its headline.
    struct Spec: Sendable {
        let path: String
        let params: [String: String]
        /// False when the window total is a de-duplicated count of people
        /// rather than a sum over days — then the headline comes from
        /// `seriesCollapsed` and not from the series.
        let additive: Bool
    }

    /// The three charts, keyed on the metric id the catalogue serves.
    ///
    /// A function rather than a dictionary literal so an unknown metric is
    /// one `nil` rather than a lookup that has to be checked twice.
    static func spec(for metric: String) -> Spec? {
        switch metric {
        case "active_users":
            // `_active` is Amplitude's own pseudo-event for "Any Active
            // Event"; without it this would need every event name listed by
            // hand. The headline is Amplitude's de-duplicated figure, so the
            // bars deliberately do not add up to it: one person active on
            // three days is one user and three bars.
            return Spec(
                path: "/api/2/events/segmentation",
                params: ["e": #"{"event_type":"_active"}"#, "m": "uniques"],
                additive: false)
        case "new_users":
            // The users endpoint rather than a segmentation query: "first
            // ever event" is not expressible as an event filter, and `m=new`
            // is the same figure Amplitude's own New Users chart shows. A
            // user is new on exactly one day, so these bars do add up.
            return Spec(path: "/api/2/users", params: ["m": "new"], additive: true)
        case "events":
            // `_all` is "Any Event", for the same reason `_active` is used
            // above.
            return Spec(
                path: "/api/2/events/segmentation",
                params: ["e": #"{"event_type":"_all"}"#, "m": "totals"],
                additive: true)
        default:
            return nil
        }
    }

    public func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let creds = try Credentials(credentials)
        guard let spec = Self.spec(for: window.metric) else {
            // Not a bug: the catalogue is the Worker's and lists metrics this
            // build has not been taught yet. The caller falls back to the API.
            throw ProviderFailure.unsupported(
                "This build cannot read Amplitude's \(window.metric) yet.")
        }

        let current = try await chart(
            spec, creds: creds, from: window.from, to: window.to,
            timeZone: window.timeZone, http: http)

        // All three descriptors set `compare: true` in the Worker, so all
        // three honour the flag. Opt-in because it doubles the calls, and a
        // tile with no delta on it would be paying that for nothing.
        var previousValue: Double?
        if window.comparePrevious {
            let length = window.to.timeIntervalSince(window.from)
            let previous = try await chart(
                spec, creds: creds,
                from: window.from.addingTimeInterval(-length),
                // A millisecond before `from`, so the two windows do not both
                // claim the boundary day — Amplitude's range is inclusive at
                // both ends, and a shared day would be counted twice.
                to: window.from.addingTimeInterval(-0.001),
                timeZone: window.timeZone, http: http)
            previousValue = Self.headline(spec, previous)
        }

        return MetricValue(
            value: Self.headline(spec, current),
            // Left nil, never zero, when no comparison was asked for: a zero
            // would draw "down 100%" against a window nobody fetched.
            previousValue: previousValue,
            // Bucketed over the requested window only, so the earlier half of
            // a comparison never reaches the chart.
            points: window.wantSeries
                ? bucketSum(
                    current.rows.map { (at: $0.at, amount: $0.amount) },
                    from: window.from, to: window.to,
                    granularity: window.granularity, timeZone: window.timeZone)
                : [])
    }

    // MARK: - One chart

    /// The daily rows, plus the window figure when the API gives one.
    struct ChartResult: Sendable {
        let rows: [(at: Date, amount: Double)]
        /// Nil when Amplitude sent no `seriesCollapsed`, which is every
        /// endpoint that has no de-duplication to do.
        let collapsed: Double?
    }

    func chart(
        _ spec: Spec, creds: Credentials, from: Date, to: Date,
        timeZone: TimeZone, http: ProviderHTTP
    ) async throws -> ChartResult {
        var params = spec.params
        // Both ends inclusive, as whole days in the window's timezone rather
        // than this machine's: the figures have to match the project's own
        // charts, and a user reading a US project from Berlin would otherwise
        // see a day the dashboard does not.
        params["start"] = Self.day(from, timeZone: timeZone)
        params["end"] = Self.day(to, timeZone: timeZone)
        // Daily, always. See the note at the top of the file.
        params["i"] = "1"

        let body = try await get(
            ChartResponse.self, spec.path, creds: creds, params: params, http: http)

        // The two endpoints label their groups differently — `seriesLabels`
        // for segmentation, `seriesMeta` for users — and neither matters:
        // one unsegmented query has exactly one group, so the series is
        // always the first.
        let series = body.data?.series?.first ?? []
        let labels = body.data?.xValues ?? []

        var rows: [(at: Date, amount: Double)] = []
        for (index, label) in labels.enumerated() {
            // A label this adapter cannot read is dropped rather than
            // bucketed at the epoch, which would put a bar on 1 January 1970
            // and silently remove it from the window.
            guard let at = Self.dayAt(label) else { continue }
            let amount = index < series.count ? series[index] : nil
            rows.append((at: at, amount: Self.number(amount)))
        }

        return ChartResult(
            rows: rows,
            collapsed: Self.finite(body.data?.seriesCollapsed?.first?.first?.value))
    }

    /// The headline for one window: Amplitude's own total, or the sum of the days.
    static func headline(_ spec: Spec, _ result: ChartResult) -> Double {
        if !spec.additive, let collapsed = result.collapsed { return collapsed }
        return result.rows.reduce(0) { $0 + $1.amount }
    }

    /// A null, or an absent day, is nothing happening rather than a gap.
    static func number(_ value: Double?) -> Double { finite(value) ?? 0 }

    /// Nil for anything JSON can carry that arithmetic cannot.
    static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    // MARK: - Dates

    /// `YYYYMMDD` of a moment in the given zone, which is what the Dashboard
    /// API's `start` and `end` take.
    ///
    /// A port of `ymd` in `packages/integrations/src/normalise.ts` with its
    /// dashes stripped, which is exactly what the Worker's adapter does to it.
    static func day(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        // POSIX, or a user on a non-Gregorian calendar sends a Buddhist year
        // in the query string and Amplitude answers 400.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    /// Noon UTC of a `YYYYMMDD` or `YYYY-MM-DD` label.
    ///
    /// A port of `dayAt`. Noon rather than midnight so the row lands on that
    /// calendar day in any zone within ±11 hours — a midnight timestamp
    /// bucketed in Los Angeles falls into the previous day, which shifts
    /// every bar on the chart by one.
    static func dayAt(_ label: String) -> Date? {
        let digits = label.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }
        guard let year = Int(digits.prefix(4)),
              let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.dropFirst(6).prefix(2))
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
}

/// Amplitude's wire shapes, nested under the adapter that reads them.
///
/// Nested rather than at file scope because `ChartResponse` is a name every
/// analytics provider in this module wants. At the top level the second one
/// to be written fails to compile, and the error names a file its author
/// never touched.
extension AmplitudeProvider {
    /// A response from either Dashboard chart endpoint.
    struct ChartResponse: Decodable {
        let data: Payload?

        struct Payload: Decodable {
            /// One row per group, one value per bucket. Nullable, because
            /// Amplitude sends null rather than zero for a day it has no
            /// answer for.
            let series: [[Double?]]?
            /// The day labels, in the same order as a series' values.
            let xValues: [String]?
            /// Per group, the figure for the window as a whole rather than
            /// per day.
            ///
            /// The only way to get a de-duplicated user count over a
            /// multi-day window out of this API.
            let seriesCollapsed: [[Collapsed]]?
        }

        struct Collapsed: Decodable {
            let value: Double?
        }
    }
}
