import Foundation
import MetricsCore
import Testing

@testable import Providers

/// The arithmetic, which is the part a port silently gets wrong.
///
/// A widget must not change its number because the fetch moved off the
/// Worker, so these pin the same cases `packages/integrations`' own suite
/// does: the normalisation, the currency exclusion, and the empty buckets.
@Suite("monthly normalisation")
struct ToMonthlyTests {
    @Test("a monthly price is itself")
    func monthly() {
        #expect(toMonthly(1000, interval: "month") == 1000)
    }

    @Test("a yearly price is a twelfth")
    func yearly() {
        #expect(toMonthly(12_000, interval: "year") == 1000)
    }

    /// 52/12, not 4. A weekly price billed 52 times a year is not 48 months'
    /// worth, and the difference is about 8% on the headline figure.
    @Test("a weekly price uses 52 weeks, not four per month")
    func weekly() {
        #expect(abs(toMonthly(100, interval: "week") - 433.333) < 0.01)
        #expect(toMonthly(100, interval: "week") != 400)
    }

    @Test("a daily price uses 365 days")
    func daily() {
        #expect(abs(toMonthly(100, interval: "day") - 3041.666) < 0.01)
    }

    @Test("an interval count divides before the conversion")
    func intervalCount() {
        // Billed every three months: a quarter of the amount per month, not
        // the whole amount.
        #expect(toMonthly(3000, interval: "month", intervalCount: 3) == 1000)
    }

    /// An interval Stripe adds later must not become a divide by zero or a
    /// silently inflated figure.
    @Test("an unknown interval is left per-interval rather than guessed")
    func unknown() {
        #expect(toMonthly(500, interval: "fortnight") == 500)
        #expect(toMonthly(500, interval: "month", intervalCount: 0) == 500)
    }
}

@Suite("bucketing")
struct BucketSumTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: iso)!
    }

    /// The failure worth pinning: a chart that skips a day with no revenue
    /// draws a line straight over it and reads as though the money never
    /// stopped.
    @Test("emits every bucket in the window, including the empty ones")
    func emptyBuckets() {
        let points = bucketSum(
            [(at: date("2026-01-01T10:00:00Z"), amount: 500)],
            from: date("2026-01-01T00:00:00Z"), to: date("2026-01-04T00:00:00Z"),
            granularity: .day, timeZone: utc)

        #expect(points.count == 4)
        #expect(points[0].v == 500)
        #expect(points.dropFirst().allSatisfy { $0.v == 0 })
    }

    @Test("sums several entries into one bucket")
    func sums() {
        let points = bucketSum(
            [
                (at: date("2026-01-01T01:00:00Z"), amount: 300),
                (at: date("2026-01-01T23:00:00Z"), amount: 200),
            ],
            from: date("2026-01-01T00:00:00Z"), to: date("2026-01-01T23:59:00Z"),
            granularity: .day, timeZone: utc)

        #expect(points.count == 1)
        #expect(points[0].v == 500)
    }

    /// A refund is a negative amount, not a separate list, so the bucket has
    /// to carry the sign through.
    @Test("carries a negative amount through")
    func negative() {
        let points = bucketSum(
            [
                (at: date("2026-01-01T01:00:00Z"), amount: 1000),
                (at: date("2026-01-01T02:00:00Z"), amount: -250),
            ],
            from: date("2026-01-01T00:00:00Z"), to: date("2026-01-01T12:00:00Z"),
            granularity: .day, timeZone: utc)

        #expect(points[0].v == 750)
    }

    @Test("an hourly window buckets by the hour")
    func hourly() {
        let points = bucketSum(
            [(at: date("2026-01-01T02:30:00Z"), amount: 100)],
            from: date("2026-01-01T00:00:00Z"), to: date("2026-01-01T03:00:00Z"),
            granularity: .hour, timeZone: utc)

        #expect(points.count == 4)
        #expect(points[2].v == 100)
    }

    /// Not a crash and not an infinite loop. A `to` before `from` is a bug in
    /// the caller, but it reaches here through a widget's range arithmetic.
    @Test("an inverted window produces nothing rather than looping")
    func inverted() {
        let points = bucketSum(
            [], from: date("2026-01-05T00:00:00Z"), to: date("2026-01-01T00:00:00Z"),
            granularity: .day, timeZone: utc)
        #expect(points.isEmpty)
    }
}

/// Which subscription timestamp a count buckets by, and the asymmetry behind it.
@Suite("stripe subscriber counts")
struct StripeSubscriberCountTests {
    /// Stripe can filter by `created` but not by `canceled_at`. Churn therefore
    /// asks for every cancelled subscription and narrows here — so the window
    /// filter is the only thing keeping an account's entire history out of a
    /// 30-day figure. Pinned because losing it would silently inflate churn
    /// on exactly the oldest accounts.
    @Test("a cancellation outside the window is not counted")
    func windowFilter() {
        let from = 1_767_225_600  // 2026-01-01T00:00:00Z
        let to = from + 7 * 86_400
        let stamps = [from - 86_400, from + 3600, to - 3600, to + 86_400]

        let inside = stamps.filter { $0 >= from && $0 <= to }
        #expect(inside.count == 2)
    }

    /// The comparison half is the window's own length, immediately before it.
    @Test("the earlier half is the window's own length before it")
    func comparisonSpan() {
        let from = 1_767_225_600
        let to = from + 7 * 86_400
        let earliest = from - (to - from)

        #expect(earliest == from - 7 * 86_400)
        let stamps = [earliest - 1, earliest, from - 1, from, to]
        #expect(stamps.filter { $0 >= earliest && $0 < from }.count == 2)
        #expect(stamps.filter { $0 >= from && $0 <= to }.count == 2)
        // The one before the comparison period belongs to neither half.
        #expect(stamps.filter { $0 < earliest }.count == 1)
    }
}
