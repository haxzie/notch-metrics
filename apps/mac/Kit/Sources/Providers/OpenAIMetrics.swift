import Foundation
import MetricsCore

/// OpenAI's metrics, read on this Mac.
///
/// Ported from `packages/integrations/src/providers/openai/index.ts`. The
/// arithmetic is deliberately the same arithmetic, down to the page budget and
/// which currencies are excluded — a widget must not change its number
/// because the fetch moved off the Worker.
///
/// What makes this connector unlike the payments ones in this module: both
/// reports are **bucketed by OpenAI itself**. A response is not a list of
/// transactions to sum, it is a list of buckets each carrying one row of
/// totals. So there is nothing to aggregate per row, and the only reason
/// `bucketSum` appears below is to re-bucket already-dated rows to the
/// granularity the chart draws — day to day is a no-op, day to week is not.
extension OpenAIProvider {
    /// Buckets OpenAI returns in one response, by `bucket_width`.
    static let perPage: [String: Int] = ["1h": 168, "1d": 31]

    /// Four requests per window, which reaches 124 days of daily buckets.
    ///
    /// Enough for every range up to 90 days; a year is refused by `planWalk`
    /// with a message rather than by a tile spinning until it times out. This
    /// is the cap that was missing when a 90-day spend tile asked for a walk
    /// it could never finish.
    static let maxPages = 4

    public func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let creds = try Self.credentials(credentials)

        switch window.metric {
        case "tokens":
            return try await usage(creds: creds, window: window, http: http) {
                Double($0.inputTokens + $0.outputTokens)
            }
        case "input_tokens":
            return try await usage(creds: creds, window: window, http: http) {
                Double($0.inputTokens)
            }
        case "output_tokens":
            return try await usage(creds: creds, window: window, http: http) {
                Double($0.outputTokens)
            }
        case "api_requests":
            return try await usage(creds: creds, window: window, http: http) {
                Double($0.numModelRequests)
            }
        case "api_spend":
            return try await spend(creds: creds, window: window, http: http)
        default:
            // Not a bug: the catalogue is the Worker's and lists metrics this
            // build has not been taught yet. The caller falls back to the API.
            throw ProviderFailure.unsupported("This build cannot read OpenAI's \(window.metric) yet.")
        }
    }

    // MARK: - Metrics

    /// One column of the completions usage report, totalled over the window.
    ///
    /// All four usage metrics walk the same report and differ only in which
    /// column they add up, so the column is an argument rather than a second
    /// switch on `window.metric` — whose `default` arm would be unreachable,
    /// `fetch` above having already decided this is not spend.
    private func usage(
        creds: Credentials, window: MetricWindow, http: ProviderHTTP,
        pick: @Sendable (UsageResult) -> Double
    ) async throws -> MetricValue {
        let width = Self.bucketWidth(window.granularity)
        let plan = try Self.planWalk(window: window, width: width)

        let rows = try await walk(
            UsageResult.self, "/organization/usage/completions", creds: creds, http: http,
            params: [
                "start_time": Self.unixSeconds(plan.start),
                "end_time": Self.unixSeconds(window.to),
                "bucket_width": width,
                "limit": String(Self.perPage[width] ?? 31),
            ])

        return Self.series(
            rows.map { (at: $0.at, amount: pick($0.result)) },
            window: window, comparePrevious: plan.comparePrevious, currency: nil)
    }

    /// Billed cost per day, in integer minor units.
    private func spend(
        creds: Credentials, window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        // Refused rather than answered with a flat line. The cost report has
        // no hourly bucket at all, so an hourly range would put a whole day's
        // charge in one bucket and nothing in the other twenty-three.
        if window.granularity == .hour {
            throw ProviderFailure.unsupported(
                "OpenAI reports cost once a day. Pick a range of 7 days or longer.")
        }

        let plan = try Self.planWalk(window: window, width: "1d")

        let rows = try await walk(
            CostResult.self, "/organization/costs", creds: creds, http: http,
            params: [
                "start_time": Self.unixSeconds(plan.start),
                "end_time": Self.unixSeconds(window.to),
                "limit": String(Self.perPage["1d"] ?? 31),
            ])

        return Self.spendValue(rows, window: window, comparePrevious: plan.comparePrevious)
    }

    /// The spend arithmetic, over buckets already fetched.
    ///
    /// Split out of the walk for exactly the reasons a port gets this wrong:
    /// the float-to-minor-units conversion, the currency exclusion and which
    /// half of a widened range a bucket lands in are all reachable here
    /// without a network.
    static func spendValue(
        _ rows: [(at: Date, result: CostResult)], window: MetricWindow, comparePrevious: Bool
    ) -> MetricValue {
        // Other currencies are excluded rather than converted. OpenAI bills in
        // USD today, so this is a guard against a future that silently sums at
        // 1:1 — there is no rate to convert at.
        var foreign: Set<String> = []
        var events: [(at: Date, amount: Double)] = []

        for row in rows {
            guard let amount = row.result.amount else { continue }
            let currency = amount.currency.uppercased()
            guard currency == "USD" else {
                foreign.insert(currency)
                continue
            }
            // `value` is dollars as a float. Multiplied by 100 here and
            // rounded once per bucket in `series`, rather than rounded per
            // line item: a day of thousandth-of-a-cent rows would otherwise
            // round to zero a few hundred times over and report nothing spent.
            events.append((at: row.at, amount: amount.value * 100))
        }

        return series(
            events, window: window, comparePrevious: comparePrevious, currency: "USD",
            note: foreign.isEmpty
                ? nil
                : "\(foreign.sorted().joined(separator: " and ")) charges were excluded "
                    + "rather than converted.")
    }

    /// Buckets dated rows into the shape the notch renders.
    ///
    /// `value` is the total over the window and `previousValue` the total over
    /// the window before it — both of these are flow metrics, unlike a
    /// subscription book, so the sum is the right headline.
    static func series(
        _ events: [(at: Date, amount: Double)], window: MetricWindow,
        comparePrevious: Bool, currency: String?, note: String? = nil
    ) -> MetricValue {
        // Summed from the rows rather than from the buckets: a window edge is
        // an instant and a bucket is a whole day, so the first and last bucket
        // can reach outside what was asked for — which with a comparison
        // fetched would pull the earlier period into the headline.
        let current = events.filter { $0.at >= window.from }
        let previous = comparePrevious ? events.filter { $0.at < window.from } : []

        // Over the requested window only, so the chart is the window the
        // widget asked for even when twice as much was fetched.
        let points = window.wantSeries
            ? bucketSum(
                current, from: window.from, to: window.to,
                granularity: window.granularity, timeZone: window.timeZone
            ).map { MetricPoint(t: $0.t, v: $0.v.rounded()) }
            : []

        return MetricValue(
            // Whole units on both halves. Money is an integer here and
            // everywhere else, and a token count was never fractional.
            value: current.reduce(0.0) { $0 + $1.amount }.rounded(),
            // Nil rather than zero when no comparison was asked for: zero is
            // a delta of minus one hundred per cent on screen.
            previousValue: comparePrevious
                ? previous.reduce(0.0) { $0 + $1.amount }.rounded()
                : nil,
            points: points,
            currency: currency,
            note: note)
    }

    // MARK: - Planning the walk

    /// The provider-side bucket width that can serve this granularity.
    ///
    /// Read off the window rather than assumed. These metrics default to
    /// `hour`, which is why a 90-day tile once asked for 2,160 hourly buckets
    /// — a walk no page budget could finish.
    static func bucketWidth(_ granularity: Granularity) -> String {
        granularity == .hour ? "1h" : "1d"
    }

    /// How far back a bounded page walk can reach, and whether the comparison
    /// window fits inside it.
    ///
    /// A port of `planWalk`. Degrades before it fails: the comparison window
    /// is the first thing dropped, because a number with no delta is still the
    /// number somebody asked for. Only when the plain window alone is over
    /// budget does this refuse, and then it says so rather than leaving a tile
    /// spinning on a walk that cannot complete.
    static func planWalk(
        window: MetricWindow, width: String
    ) throws -> (start: Date, comparePrevious: Bool) {
        let bucket = width == "1h" ? hourSeconds : daySeconds
        let budget = Double(perPage[width] ?? 31) * Double(maxPages) * bucket
        let span = window.to.timeIntervalSince(window.from)

        if window.comparePrevious && span * 2 <= budget {
            return (start: window.from.addingTimeInterval(-span), comparePrevious: true)
        }
        if span <= budget { return (start: window.from, comparePrevious: false) }

        let days = Int((budget / daySeconds).rounded(.up))
        throw ProviderFailure.unsupported(
            "That range is longer than the \(days) days this connector will page through. "
                + "Pick a shorter one.")
    }

    // MARK: - Paging

    /// Walks every page of one report, flattening buckets to dated rows.
    ///
    /// The cap is a second line of defence behind `planWalk`: that plans for
    /// the *expected* bucket count, and a provider that returned fewer buckets
    /// per page than documented would otherwise turn a planned four requests
    /// into an unbounded loop.
    private func walk<R: Decodable>(
        _ type: R.Type, _ path: String, creds: Credentials, http: ProviderHTTP,
        params: [String: String]
    ) async throws -> [(at: Date, result: R)] {
        var rows: [(at: Date, result: R)] = []
        var page: String?

        for _ in 0..<Self.maxPages {
            var query = params
            if let page { query["page"] = page }
            let url = Self.query(path, params: query, projectId: creds.projectId)

            let body = try await Self.get(Page<R>.self, url, creds: creds, http: http)
            for bucket in body.data {
                // Dated by the bucket's own start, not by when we read it. The
                // point of a dated row is that re-bucketing to a week lands it
                // in the right one.
                let at = Date(timeIntervalSince1970: bucket.startTime)
                for result in bucket.results { rows.append((at: at, result: result)) }
            }

            guard body.hasMore == true, let next = body.nextPage, !next.isEmpty else { return rows }
            page = next
        }

        return rows
    }
}

/// OpenAI's wire shapes, nested under the adapter that reads them.
///
/// Nested rather than at file scope because `Page`, `UsageResult` and
/// `CostResult` are names several connectors in this module want. At the top
/// level the second one to be written fails to compile, and the error names a
/// file its author never touched.
extension OpenAIProvider {
    /// One page of either report: buckets, each holding rows of totals.
    struct Page<R: Decodable>: Decodable {
        let data: [Bucket]
        let hasMore: Bool?
        let nextPage: String?

        struct Bucket: Decodable {
            /// Unix seconds. The row's date, not the time of the request.
            let startTime: TimeInterval
            let results: [R]

            enum CodingKeys: String, CodingKey {
                case startTime = "start_time"
                case results
            }
        }

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
            case nextPage = "next_page"
        }
    }

    struct UsageResult: Decodable {
        let inputTokens: Int
        let outputTokens: Int
        let numModelRequests: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case numModelRequests = "num_model_requests"
        }
    }

    struct CostResult: Decodable {
        /// Absent on a bucket with nothing billed in it, which is a day with
        /// no spend rather than a malformed response.
        let amount: Amount?
        let organizationId: String?

        struct Amount: Decodable {
            /// Dollars as a float — OpenAI's choice, not ours. Converted to
            /// integer minor units in `spendValue` and nowhere else.
            let value: Double
            let currency: String
        }

        enum CodingKeys: String, CodingKey {
            case amount
            case organizationId = "organization_id"
        }
    }
}
