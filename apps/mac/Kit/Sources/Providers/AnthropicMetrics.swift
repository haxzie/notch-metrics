import Foundation
import MetricsCore

/// Claude's metrics, read on this Mac.
///
/// Ported from `packages/integrations/src/providers/anthropic/index.ts`. The
/// arithmetic is deliberately the same arithmetic, down to which cache tiers
/// count as input and where the decimal point in a cost sits — a widget must
/// not change its number because the fetch moved off the Worker.
///
/// The one structural difference from every payments adapter here: Anthropic's
/// two reports are **bucketed by the API itself**. A row is not a transaction
/// with its own instant, it is a whole hour or a whole day stamped with the
/// bucket's start. That is why the headline figure is summed from the rows
/// rather than from `bucketSum`'s output: the window edge is an instant and a
/// bucket is a whole day, so a sum taken from the drawn buckets would pull a
/// neighbouring day's tokens into the total.
extension AnthropicProvider {
    /// Requests one metric will page through before giving up.
    ///
    /// The same cap the Worker uses, and bounded for the same reason as the
    /// plan that precedes it: a provider returning fewer buckets per page than
    /// documented must not turn four planned requests into a loop that
    /// outlives the fetch.
    static let maxPages = 4

    /// The bucket widths the reports offer, and how many of each one response
    /// carries.
    enum BucketWidth: String {
        case hour = "1h"
        case day = "1d"

        var seconds: TimeInterval {
            switch self {
            case .hour: return AnthropicProvider.hour
            case .day: return AnthropicProvider.day
            }
        }

        /// Buckets one response carries. The cost report is daily only.
        var perPage: Int {
            switch self {
            case .hour: return 168
            case .day: return 31
            }
        }
    }

    public func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let creds = try Self.credentials(credentials)

        switch window.metric {
        case "tokens":
            // Input plus output. Input is the four cache tiers added together,
            // which is what the Console's Usage page shows and is not what was
            // billed, since a cache read costs a tenth of the rest.
            return try await usage(creds, window: window, http: http) {
                Self.inputTokens($0) + Double($0.outputTokens ?? 0)
            }
        case "input_tokens":
            return try await usage(creds, window: window, http: http, pick: Self.inputTokens)
        case "output_tokens":
            // Thinking tokens are output tokens and are counted here.
            return try await usage(creds, window: window, http: http) {
                Double($0.outputTokens ?? 0)
            }
        case "api_spend":
            return try await spend(creds, window: window, http: http)
        default:
            // Not a bug: the catalogue is the Worker's and lists metrics this
            // build has not been taught yet. The caller falls back to the API.
            throw ProviderFailure.unsupported(
                "This build cannot read Claude's \(window.metric) yet.")
        }
    }

    // MARK: - Metrics

    /// One of the three token metrics, which differ only in which column of
    /// the messages report they add up.
    ///
    /// `pick` is passed in rather than switched on `window.metric`: the three
    /// walk the same report with the same plan, and a second copy of the walk
    /// would be a second place for the window arithmetic to drift.
    private func usage(
        _ creds: Credentials, window: MetricWindow, http: ProviderHTTP,
        pick: @Sendable (UsageResult) -> Double
    ) async throws -> MetricValue {
        // Hourly is real here: the messages report buckets by `1h`, which is
        // also the granularity these metrics default to. Spend below cannot,
        // which is why the two declare different sets — and why the granularity
        // is read off the window rather than assumed. A 90-day tile asking for
        // hourly buckets is a walk this connector could never finish, and the
        // plan below is what turns that into a sentence instead of a timeout.
        let width: BucketWidth = window.granularity == .hour ? .hour : .day
        let plan = try Self.plan(window: window, bucket: width)

        var params: [(String, String)] = [
            ("starting_at", ISO8601.string(from: plan.start)),
            ("ending_at", ISO8601.string(from: window.to)),
            ("bucket_width", width.rawValue),
            ("limit", String(width.perPage)),
        ]
        if let workspace = creds.workspaceId {
            params.append(("workspace_ids[]", workspace))
        }

        let rows = try await Self.walk(
            UsageResult.self, path: "/organizations/usage_report/messages",
            key: creds.adminKey, params: params, http: http)

        return Self.series(
            rows.map { (at: $0.at, amount: pick($0.result)) },
            window: window, comparePrevious: plan.comparePrevious, currency: nil)
    }

    /// Billed cost per day: tokens, web search and code execution.
    private func spend(
        _ creds: Credentials, window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        if window.granularity == .hour {
            // Refused rather than silently answered at day width, which would
            // draw twenty-four identical bars and read as though the money
            // arrived in a lump.
            throw ProviderFailure.unsupported(
                "Claude reports cost once a day. Pick a range of 7 days or longer.")
        }

        let plan = try Self.plan(window: window, bucket: .day)

        // The cost report has no workspace filter, only a grouping. Asking for
        // the grouping and discarding the other rows is the only way to scope
        // it; without the `group_by` every row comes back with a nil
        // `workspace_id` and a scoped connection would silently report the
        // whole organisation's bill.
        let scoped = creds.workspaceId
        var params: [(String, String)] = [
            // Floored, not passed through: an unaligned start is snapped up to
            // the next midnight, which silently drops the first day of the
            // window.
            ("starting_at", ISO8601.string(from: Self.startOfUTCDay(plan.start))),
            ("ending_at", ISO8601.string(from: window.to)),
            ("limit", String(BucketWidth.day.perPage)),
        ]
        if scoped != nil { params.append(("group_by[]", "workspace_id")) }

        let rows = try await Self.walk(
            CostResult.self, path: "/organizations/cost_report",
            key: creds.adminKey, params: params, http: http)

        var foreign: Set<String> = []
        var events: [(at: Date, amount: Double)] = []

        for row in rows {
            if let scoped, row.result.workspaceId != scoped { continue }

            let currency = (row.result.currency?.isEmpty == false ? row.result.currency! : "USD")
                .uppercased()
            // Dropped rather than converted, as everywhere else in this
            // module: there is no rate to convert at, and a total that
            // silently added euros to dollars is worse than one that says what
            // it left out. The report is USD-only today, so this is a guard
            // against a change rather than a case anyone has seen.
            guard currency == "USD" else {
                foreign.insert(currency)
                continue
            }

            // `amount` is a decimal string already in *minor* units —
            // "123.78912" is $1.2379, not $123.79. Reading it as dollars
            // overstates the bill by a hundred times and looks plausible
            // enough to ship. So: no multiply by 100 here, only the rounding
            // to whole minor units that `series` does.
            guard let cents = Double(row.result.amount), cents.isFinite else {
                throw ProviderFailure.badResponse(
                    "Claude returned \"\(row.result.amount)\" as a cost")
            }
            events.append((at: row.at, amount: cents))
        }

        return Self.series(
            events, window: window, comparePrevious: plan.comparePrevious,
            // USD, not `window.preferredCurrency`: the rows that survived the
            // filter above are all dollars, and labelling them with whatever
            // the widget asked for would rename the money rather than convert
            // it.
            currency: "USD",
            note: foreign.isEmpty
                ? nil
                : "\(foreign.sorted().joined(separator: " and ")) charges were excluded "
                    + "rather than converted.")
    }

    /// Input tokens, across all four of the fields that are input tokens.
    ///
    /// Leaving any of them out undercounts silently: a cache-heavy workload
    /// reads most of its context rather than sending it, so
    /// `uncached_input_tokens` alone can be a tenth of the real volume.
    static func inputTokens(_ result: UsageResult) -> Double {
        let creation = result.cacheCreation
        return Double(
            (result.uncachedInputTokens ?? 0) + (result.cacheReadInputTokens ?? 0)
                + (creation?.ephemeral5mInputTokens ?? 0)
                + (creation?.ephemeral1hInputTokens ?? 0))
    }

    // MARK: - The window

    /// How far back to ask, and whether the comparison fits in the page budget.
    ///
    /// A port of `planWalk`. Widening the window backwards by its own length
    /// doubles the buckets, so a comparison that would not fit is dropped
    /// rather than paged for — and a *window* that does not fit is a sentence,
    /// not a truncated number: a total missing its first forty days is wrong
    /// in a way nothing on the tile could show.
    static func plan(
        window: MetricWindow, bucket: BucketWidth
    ) throws -> (start: Date, comparePrevious: Bool) {
        let budget = Double(bucket.perPage * Self.maxPages) * bucket.seconds
        let span = window.to.timeIntervalSince(window.from)

        if window.comparePrevious && span * 2 <= budget {
            return (window.from.addingTimeInterval(-span), true)
        }
        if span <= budget { return (window.from, false) }

        let days = Int((budget / Self.day).rounded(.up))
        throw ProviderFailure.unsupported(
            "That range is longer than the \(days) days this connector will page through. "
                + "Pick a shorter one.")
    }

    /// Both metric families are flows, so the headline is the window's total.
    ///
    /// `comparePrevious` is honoured because all four of Claude's descriptors
    /// set `compare`. When it is false `previousValue` stays nil rather than
    /// zero: a tile reading zero would draw "down 100%" against a window this
    /// fetch never looked at.
    static func series(
        _ events: [(at: Date, amount: Double)], window: MetricWindow,
        comparePrevious: Bool, currency: String?, note: String? = nil
    ) -> MetricValue {
        let current = events.filter { $0.at >= window.from }
        let previous = comparePrevious ? events.filter { $0.at < window.from } : []

        // Points over the requested window only, never the widened one, and
        // re-bucketed into the viewer's time zone — the same two passes the
        // Worker makes. The API's buckets are UTC-aligned and a chart is read
        // in local time, so this is a translation rather than a second
        // bucketing of already-bucketed data.
        let points =
            window.wantSeries
            ? bucketSum(
                current, from: window.from, to: window.to,
                granularity: window.granularity, timeZone: window.timeZone
            ).map { MetricPoint(t: $0.t, v: $0.v.rounded()) }
            : []

        return MetricValue(
            // Whole units. Tokens are counts, and spend is integer minor units
            // plus an ISO 4217 code; a fractional cent on the headline figure
            // is a rendering bug waiting to happen.
            value: current.reduce(0) { $0 + $1.amount }.rounded(),
            previousValue: comparePrevious
                ? previous.reduce(0) { $0 + $1.amount }.rounded() : nil,
            points: points,
            currency: currency,
            note: note)
    }

    // MARK: - Paging

    /// Walks one report, flattening every bucket's results into timestamped rows.
    ///
    /// The timestamp on a row is its *bucket's* start, not an instant anything
    /// happened at. `series` splits the windows on it and `bucketSum` draws
    /// with it, both of which are only sound because the bucket width was
    /// chosen to match the granularity being asked for.
    static func walk<R: Decodable>(
        _ type: R.Type, path: String, key: String, params: [(String, String)],
        http: ProviderHTTP
    ) async throws -> [(at: Date, result: R)] {
        var rows: [(at: Date, result: R)] = []
        var page: String?

        for _ in 0..<Self.maxPages {
            var query = params
            if let page { query.append(("page", page)) }

            let body = try await Self.get(
                Page<R>.self, path: path, key: key, params: query, http: http)

            for bucket in body.data {
                // A bucket whose start cannot be read is dropped rather than
                // guessed into a window: placing it wrongly would move real
                // tokens across the compare boundary.
                guard let at = ISO8601.parse(bucket.startingAt) else { continue }
                for row in bucket.results { rows.append((at: at, result: row)) }
            }

            guard body.hasMore == true, let next = body.nextPage, !next.isEmpty else { return rows }
            page = next
        }

        return rows
    }
}

/// Anthropic's wire shapes, nested under the adapter that reads them.
///
/// Nested rather than at file scope because `Page`, `UsageResult` and
/// `CostResult` are names half this module wants. At the top level the second
/// one to be written fails to compile, and the error names a file its author
/// never touched.
extension AnthropicProvider {
    /// One page of either report: a list of buckets, each with its own rows.
    struct Page<R: Decodable>: Decodable {
        let data: [Bucket<R>]
        let hasMore: Bool?
        let nextPage: String?

        struct Bucket<T: Decodable>: Decodable {
            let startingAt: String
            let endingAt: String?
            let results: [T]

            enum CodingKeys: String, CodingKey {
                case startingAt = "starting_at"
                case endingAt = "ending_at"
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
        /// Optional, every one of them, where the Worker's types declare them
        /// required. The Worker decodes with Zod's loose object and would read
        /// a missing field as `undefined`; `JSONDecoder` throws, and a throw
        /// here fails the whole page rather than one column. A token metric
        /// reading low is recoverable, four blank widgets on an API change are
        /// not — and the contract fixtures are what catch the drift.
        let uncachedInputTokens: Int?
        let cacheReadInputTokens: Int?
        /// Null for an organisation that uses no prompt caching.
        let cacheCreation: CacheCreation?
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case uncachedInputTokens = "uncached_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreation = "cache_creation"
            case outputTokens = "output_tokens"
        }
    }

    /// The two cache-write tiers, priced differently and both input.
    struct CacheCreation: Decodable {
        let ephemeral1hInputTokens: Int?
        let ephemeral5mInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
            case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
        }
    }

    struct CostResult: Decodable {
        /// A decimal string in **minor** units. Never parsed as dollars; see
        /// the note in `spend`.
        let amount: String
        let currency: String?
        /// Nil unless the request asked for the workspace grouping.
        let workspaceId: String?

        enum CodingKeys: String, CodingKey {
            case amount
            case currency
            case workspaceId = "workspace_id"
        }
    }
}
