import Foundation
import MetricsCore

/// npm's two metrics, read on this Mac.
///
/// The arithmetic is the Worker's arithmetic: npm publishes whole UTC days
/// and nothing finer, so a weekly or monthly chart is rolled up here rather
/// than asked for — `bucketSum` over one row per day is the roll-up, not a
/// second bucketing.
extension NpmProvider {
    /// npm's own package-name rule: lower case, optionally scoped.
    static let namePattern = "^(@[a-z0-9-~][a-z0-9-._~]*/)?[a-z0-9-~][a-z0-9-._~]*$"

    public func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        switch window.metric {
        case "downloads":
            return try await downloads(window: window, http: http)
        case "weekly_downloads":
            return try await weeklyDownloads(window: window, http: http)
        default:
            throw ProviderFailure.unsupported("This build cannot read npm's \(window.metric) yet.")
        }
    }

    // MARK: - Metrics

    private func downloads(window: MetricWindow, http: ProviderHTTP) async throws -> MetricValue {
        let name = try Self.packageFor(window)
        let current = try await Self.days(name, from: window.from, to: window.to, http: http)

        let rows = current.compactMap { row -> (at: Date, amount: Double)? in
            // Midday UTC, not midnight. The day is a UTC day whatever zone
            // the reader is in, and midnight parsed into a zone behind UTC
            // lands on the day before — which shifts every bar by one and is
            // invisible unless somebody counts.
            guard let at = Self.instant(ofDay: row.day) else { return nil }
            return (at: at, amount: Double(row.downloads))
        }

        let points = bucketSum(
            rows, from: window.from, to: window.to,
            granularity: window.granularity, timeZone: window.timeZone)

        var notes: [String] = []
        let missing = Self.unaggregated(current)
        if missing > 0 {
            notes.append(
                "\(missing) of \(current.count) days have not been aggregated by npm yet "
                    + "and read as zero.")
        }

        var previousValue: Double?
        if window.comparePrevious {
            let span = window.to.timeIntervalSince(window.from)
            let previousTo = window.from.addingTimeInterval(-0.001)
            let previous = try await Self.days(
                name, from: previousTo.addingTimeInterval(-span), to: previousTo, http: http)

            // Only when the two windows are aggregated to about the same
            // depth. npm backfills late and scattered — September 2026 had
            // gaps on the 7th, 8th and 15th — so a window missing three days
            // compared against one missing none reports npm's own backlog as
            // a fall in downloads.
            // A tenth of the window, and at least a day. A couple of
            // missing days either side is noise; a quarter of the window
            // missing on one side is a comparison that would mostly measure
            // npm's backlog.
            let tolerance = max(1, Int((Double(current.count) / 10).rounded()))
            let gaps = Self.interiorGaps(current)
            let previousGaps = Self.interiorGaps(previous)
            if abs(previousGaps - gaps) <= tolerance {
                previousValue = previous.reduce(0) { $0 + Double($1.downloads) }
            } else {
                notes.append(
                    "No comparison: npm has left \(gaps) days uncounted inside this window and "
                        + "\(previousGaps) inside the one before, so a change between them would "
                        + "mostly measure npm's backlog.")
            }
        }

        return MetricValue(
            // Summed from the rows, never from the buckets: a bucket is a
            // whole period and the window's edges are instants.
            value: rows.reduce(0) { $0 + $1.amount },
            previousValue: previousValue,
            points: window.wantSeries ? points : [],
            note: notes.isEmpty ? nil : notes.joined(separator: " "))
    }

    /// Days npm has not finished counting, which it reports as a zero.
    static func unaggregated(_ days: [Range.Day]) -> Int {
        days.filter { $0.downloads == 0 }.count
    }

    /// Gaps with an aggregated day after them.
    ///
    /// npm lags a day or two at the end of every window, so one ending today
    /// always has trailing zeros where the window before it has none.
    /// Counting those made the two look incomparable every single time and
    /// the delta was withheld on every poll. What actually makes a
    /// comparison meaningless is npm failing to backfill days *inside* the
    /// window — react had six of those in one month, in two separate runs.
    static func interiorGaps(_ days: [Range.Day]) -> Int {
        guard let lastCounted = days.lastIndex(where: { $0.downloads > 0 }) else { return 0 }
        return unaggregated(Array(days[..<lastCounted]))
    }

    private static func days(
        _ name: String, from: Date, to: Date, http: ProviderHTTP
    ) async throws -> [Range.Day] {
        let body = try await get(
            Range.self, "/downloads/range/\(day(from)):\(day(to))/\(encode(name))", http: http)
        return body.downloads
    }

    /// npm's own "Weekly Downloads": a trailing seven-day sum, one point per
    /// day.
    ///
    /// Not calendar weeks. npmjs.com's figure for react on 4 November was
    /// 248,185,175, which is exactly the seven days ending that day —
    /// `/downloads/point/last-week` returns the same number. Discrete
    /// Monday-to-Sunday bars gave 116M, 126M and 243M on consecutive weeks:
    /// the wrong shape, and wildly unstable, because npm's counts service
    /// had no data at all for 13–15 and 19–21 October — the same days for
    /// every package — so a week holding three of them came out half empty.
    ///
    /// A rolling window spreads those gaps over seven points instead of
    /// crushing one bar, which is why npm's own chart stays smooth through
    /// the same outage.
    private func weeklyDownloads(
        window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let name = try Self.packageFor(window)
        let span = window.to.timeIntervalSince(window.from)

        // Six days of lead-in so the first point has a whole week behind it,
        // and another window's worth when a comparison is wanted.
        let lead: TimeInterval = 6 * 86_400
        let earliest = window.from.addingTimeInterval(-lead - (window.comparePrevious ? span : 0))
        let fetched = try await Self.days(name, from: earliest, to: window.to, http: http)

        // Trailing days npm has not counted are dropped rather than summed
        // as zero. Kept, they drag the last points down — react's rolling
        // total fell from 248M to 171M across two of them — and npm's own
        // page does not show that dip because it ends at the last complete
        // day.
        var end = fetched.count
        while end > 0, fetched[end - 1].downloads == 0 { end -= 1 }
        let counted = Array(fetched[..<end])

        var rolling: [(at: Date, value: Double)] = []
        if counted.count >= 7 {
            for i in 6..<counted.count {
                let total = counted[(i - 6)...i].reduce(0) { $0 + $1.downloads }
                guard let at = Self.instant(ofDay: counted[i].day) else { continue }
                rolling.append((at: at, value: Double(total)))
            }
        }

        let inWindow = rolling.filter { $0.at >= window.from }
        let latest = inWindow.last ?? rolling.last

        // The figure a window earlier, which is what the delta is against —
        // not a sum over the window, because this metric is a snapshot at
        // every point along it.
        var previousValue: Double?
        if window.comparePrevious, let latest {
            let at = latest.at.addingTimeInterval(-span)
            previousValue = rolling.last(where: { $0.at <= at })?.value
        }

        let skipped = Self.unaggregated(counted)
        return MetricValue(
            value: latest?.value ?? 0,
            previousValue: previousValue,
            points: window.wantSeries
                ? inWindow.map { MetricPoint(t: ISO8601DateFormatter().string(from: $0.at), v: $0.value) }
                : [],
            note: skipped > 0
                ? "\(skipped) days inside this window were never counted by npm, so the line "
                    + "dips through them."
                : nil)
    }

    // MARK: - The package

    /// Which package this request is about.
    ///
    /// Re-validated here as well as by the manifest's `pattern`, because that
    /// is a hint the app renders and this value reaches a request path. A
    /// scoped name carries a slash, which is exactly the character that would
    /// otherwise address a different endpoint on an allowed host.
    static func packageFor(_ window: MetricWindow) throws -> String {
        let name = (window.params["package"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !name.isEmpty else {
            throw ProviderFailure.unsupported("Pick a package for this widget.")
        }
        guard name.range(of: namePattern, options: .regularExpression) != nil else {
            throw ProviderFailure.unsupported("\"\(name)\" is not an npm package name.")
        }
        return name
    }

    /// Each segment encoded separately, so a scope's slash survives as a slash.
    static func encode(_ name: String) -> String {
        name.split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                String(segment).addingPercentEncoding(
                    withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~")))
                    ?? String(segment)
            }
            .joined(separator: "/")
    }

    /// `YYYY-MM-DD` in UTC, which is the only thing npm's range endpoint takes.
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// A `YYYY-MM-DD` label as the middle of that UTC day. See the note in
    /// `downloads` for why it is midday and not midnight.
    static func instant(ofDay label: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.date(from: "\(label)T12:00:00Z")
    }

    // MARK: - Wire shapes

    /// No `authorization` header anywhere here. The downloads API is public,
    /// and sending the token to a host with no use for it is a credential in
    /// one more place for nothing.
    private static func get<T: Decodable>(
        _ type: T.Type, _ path: String, http: ProviderHTTP
    ) async throws -> T {
        let response = try await http.get(
            stats + path, headers: ["accept": "application/json"])
        guard response.ok else {
            throw failure(for: response, subject: "npm's download statistics")
        }
        return try response.json(type)
    }

    struct Range: Decodable {
        let start: String
        let end: String
        let downloads: [Day]

        struct Day: Decodable {
            let downloads: Int
            let day: String
        }
    }

    struct Point: Decodable {
        let downloads: Int
    }
}
