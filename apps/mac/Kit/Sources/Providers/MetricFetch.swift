import Foundation
import MetricsCore

/// What a widget is asking for.
///
/// The Swift half of `MetricRequest` in `packages/integrations/src/types.ts`.
/// Dates rather than a range string: the range is resolved to a window by the
/// caller, so an adapter cannot disagree with the rest of the app about what
/// "last 30 days" means.
public struct MetricWindow: Sendable {
    public let metric: String
    public let from: Date
    public let to: Date
    public let granularity: Granularity
    /// False for a tile with no chart, which lets an adapter skip a page walk
    /// whose only purpose is the points nobody draws.
    public let wantSeries: Bool
    /// Whether the tile wants a previous-period figure to show a delta against.
    ///
    /// The Worker reads this off the metric descriptor's `supportsCompare`,
    /// and so does the caller here. An adapter that honours it widens the
    /// window backwards by its own length, sums the earlier half into
    /// `previousValue` and reports only the later half as `value`.
    ///
    /// Opt-in rather than always-on because it doubles the rows fetched, and
    /// a tile with no delta on it would be paying that for nothing.
    public let comparePrevious: Bool
    /// The widget's own arguments, as the manifest's `params` declare them.
    public let params: [String: String]
    public let timeZone: TimeZone
    /// What to report money in. An adapter drops transactions in anything
    /// else rather than converting: there is no rate to convert at.
    public let preferredCurrency: String

    public init(
        metric: String, from: Date, to: Date, granularity: Granularity,
        wantSeries: Bool, comparePrevious: Bool = false, params: [String: String] = [:],
        timeZone: TimeZone = .current, preferredCurrency: String = "USD"
    ) {
        self.metric = metric
        self.from = from
        self.to = to
        self.granularity = granularity
        self.wantSeries = wantSeries
        self.comparePrevious = comparePrevious
        self.params = params
        self.timeZone = timeZone
        self.preferredCurrency = preferredCurrency
    }
}

/// One number, and the points behind it.
///
/// The Swift half of `RawSeries`. Deliberately smaller than `MetricSeries`:
/// everything the caller already knows — which widget asked, which range,
/// when the answer was generated — is assembled outside, so an adapter cannot
/// get those wrong and there is one place that fills them in.
public struct MetricValue: Sendable {
    public let value: Double
    public let previousValue: Double?
    public let points: [MetricPoint]
    public let currency: String?
    public let items: [MetricListItem]?
    /// Something true about this answer that the number cannot say: "4
    /// transactions in another currency were excluded."
    public let note: String?

    public init(
        value: Double, previousValue: Double? = nil, points: [MetricPoint] = [],
        currency: String? = nil, items: [MetricListItem]? = nil, note: String? = nil
    ) {
        self.value = value
        self.previousValue = previousValue
        self.points = points
        self.currency = currency
        self.items = items
        self.note = note
    }
}

/// Sums amounts into the buckets a chart draws.
///
/// A port of `bucketSum`. Every bucket in the window is emitted, including
/// the empty ones: a chart that skips a day with no revenue draws a line
/// straight over it and reads as though the money never stopped.
public func bucketSum(
    _ entries: [(at: Date, amount: Double)],
    from: Date, to: Date, granularity: Granularity, timeZone: TimeZone
) -> [MetricPoint] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    let component: Calendar.Component
    switch granularity {
    case .hour: component = .hour
    case .day: component = .day
    case .week: component = .weekOfYear
    case .month: component = .month
    }

    // Bucket starts first, so the shape of the series does not depend on
    // which buckets happen to have data in them.
    var starts: [Date] = []
    var cursor = calendar.dateInterval(of: component, for: from)?.start ?? from
    while cursor <= to {
        starts.append(cursor)
        guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor
        else { break }
        cursor = next
    }

    var totals: [Date: Double] = [:]
    for entry in entries {
        guard let start = calendar.dateInterval(of: component, for: entry.at)?.start else { continue }
        totals[start, default: 0] += entry.amount
    }

    return starts.map { MetricPoint(t: ISO8601DateFormatter().string(from: $0), v: totals[$0] ?? 0) }
}

/// A recurring amount expressed per month.
///
/// A port of `toMonthly`. The weekly and daily cases use 52/12 and 365/12
/// rather than 4 and 30: a "weekly" price billed 52 times a year is not 48
/// months' worth, and the difference is about 8% on the headline number.
public func toMonthly(_ amount: Double, interval: String, intervalCount: Int = 1) -> Double {
    let perInterval = amount / Double(max(1, intervalCount))
    switch interval {
    case "month": return perInterval
    case "year": return perInterval / 12
    case "week": return perInterval * 52 / 12
    case "day": return perInterval * 365 / 12
    default: return perInterval
    }
}
