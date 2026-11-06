import Foundation
import MetricsCore

/// Polar's metrics, read on this Mac.
///
/// Ported from `packages/integrations/src/providers/polar/index.ts`. The
/// arithmetic is deliberately the same arithmetic — which orders count as
/// paid, how a window is split against its previous one, how many rows a feed
/// carries — because a widget must not change its number because the fetch
/// moved off the Worker.
extension PolarProvider {
    /// How many rows a list widget carries. `RECENT_PAYMENTS_LIMIT` in
    /// `packages/integrations/src/list.ts`, and the two have to agree or the
    /// same tile shows a different number of payments on either path.
    static let recentPaymentsLimit = 10

    public func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let creds = try Self.credentials(credentials)

        switch window.metric {
        case "mrr":
            // The currency is the organization's, which Polar does not put in
            // the metrics response — hence the extra call, exactly as the
            // Worker's adapter makes it.
            let currency = Self.currency(of: try await organization(creds, http: http))
            return try await latest(
                creds, slug: .monthlyRecurringRevenue, currency: currency, window: window,
                http: http)
        case "active_subscribers":
            return try await latest(
                creds, slug: .activeSubscriptions, currency: nil, window: window, http: http)
        case "revenue":
            let currency = Self.currency(of: try await organization(creds, http: http))
            return try await overWindow(
                creds, slug: .revenue, currency: currency, window: window, http: http)
        case "new_subscribers":
            return try await overWindow(
                creds, slug: .newSubscriptions, currency: nil, window: window, http: http)
        case "churned_subscribers":
            return try await overWindow(
                creds, slug: .churnedSubscriptions, currency: nil, window: window, http: http)
        case "recent_payments":
            return try await recentPayments(creds, window: window, http: http)
        default:
            // Not a bug: the catalogue is the Worker's and lists metrics this
            // build has not been taught yet. The caller falls back to the API.
            throw ProviderFailure.unsupported("This build cannot read Polar's \(window.metric) yet.")
        }
    }

    // MARK: - The metrics endpoint

    /// Which figure to ask `/metrics/` for.
    ///
    /// Outbound only, so unlike an enum decoded off the wire this one is
    /// strict: a slug Polar renames is a request that 422s, not a tile that
    /// silently reads zero.
    enum Slug: String {
        case revenue
        case monthlyRecurringRevenue = "monthly_recurring_revenue"
        case activeSubscriptions = "active_subscriptions"
        case newSubscriptions = "new_subscriptions"
        case churnedSubscriptions = "churned_subscriptions"

        /// Every value is nullable: a figure Polar did not compute for a
        /// period is null, not zero, and the difference is what `latest`
        /// depends on.
        func value(in period: MetricPeriod) -> Double? {
            switch self {
            case .revenue: return period.revenue
            case .monthlyRecurringRevenue: return period.monthlyRecurringRevenue
            case .activeSubscriptions: return period.activeSubscriptions
            case .newSubscriptions: return period.newSubscriptions
            case .churnedSubscriptions: return period.churnedSubscriptions
            }
        }
    }

    struct MetricPeriod: Decodable {
        let timestamp: String
        let revenue: Double?
        let monthlyRecurringRevenue: Double?
        let activeSubscriptions: Double?
        let newSubscriptions: Double?
        let churnedSubscriptions: Double?

        enum CodingKeys: String, CodingKey {
            case timestamp
            case revenue
            case monthlyRecurringRevenue = "monthly_recurring_revenue"
            case activeSubscriptions = "active_subscriptions"
            case newSubscriptions = "new_subscriptions"
            case churnedSubscriptions = "churned_subscriptions"
        }
    }

    struct MetricsResponse: Decodable {
        let periods: [MetricPeriod]?
    }

    private func periods(
        _ credentials: Credentials, slug: Slug, from: Date, to: Date,
        granularity: Granularity, timeZone: TimeZone, http: ProviderHTTP
    ) async throws -> [MetricPeriod] {
        let body = try await get(
            MetricsResponse.self, "/metrics/", credentials: credentials,
            params: [
                "start_date": Self.isoDay(from, timeZone: timeZone),
                "end_date": Self.isoDay(to, timeZone: timeZone),
                // Polar's own interval names happen to match ours.
                "interval": granularity.rawValue,
                "timezone": timeZone.identifier,
                // Only this metric's query runs server-side, which matters on
                // an endpoint that would otherwise compute fifty-odd figures
                // per call.
                "metrics": slug.rawValue,
            ],
            http: http)
        return body.periods ?? []
    }

    /// A snapshot: the most recent period Polar has a value for.
    ///
    /// Polar computes MRR and active subscriptions per period and the last few
    /// can be null while its pipeline catches up. Taking the last non-null
    /// value rather than the last period keeps a tile from showing zero at
    /// midnight.
    ///
    /// `comparePrevious` is ignored here, and the descriptors agree: `mrr` and
    /// `active_subscribers` are scalars with no window, so there is no
    /// previous window to compare against.
    private func latest(
        _ credentials: Credentials, slug: Slug, currency: String?,
        window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        // A week of days, not the widget's window: the window could be a year
        // at month resolution, and the answer to "what is MRR" is "now", not
        // "this month so far".
        let now = Date()
        let rows = try await periods(
            credentials, slug: slug, from: now.addingTimeInterval(-7 * 24 * 60 * 60), to: now,
            granularity: .day, timeZone: window.timeZone, http: http)

        let value = rows.reversed().compactMap { slug.value(in: $0) }.first ?? 0

        return MetricValue(
            // Whole minor units. Money is an integer here and everywhere else;
            // a fractional cent on the headline figure is a rendering bug
            // waiting to happen, and a fractional subscription is nonsense.
            value: value.rounded(),
            currency: currency)
    }

    /// A total over the window, with the previous window for the delta.
    ///
    /// One call covers both windows: Polar buckets the whole span and the
    /// split is done here by timestamp, which halves the calls on an endpoint
    /// with a per-minute budget.
    ///
    /// The earlier half is asked for only when the tile wants a delta, as the
    /// Worker does it. A tile with no delta would otherwise have Polar compute
    /// twice the periods for a figure nobody reads — and `previousValue` stays
    /// nil rather than becoming a zero, because a zero is a figure: it draws
    /// as "down 100%" against a window the fetch never looked at.
    private func overWindow(
        _ credentials: Credentials, slug: Slug, currency: String?,
        window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let span = window.to.timeIntervalSince(window.from)
        let from = window.comparePrevious
            ? window.from.addingTimeInterval(-span) : window.from
        let rows = try await periods(
            credentials, slug: slug, from: from, to: window.to,
            granularity: window.granularity, timeZone: window.timeZone, http: http)

        // A period whose timestamp cannot be read is dropped from both
        // windows rather than guessed into one of them.
        let valued: [(at: Date, amount: Double)] = rows.compactMap { row in
            guard let at = Self.instant(row.timestamp, timeZone: window.timeZone) else { return nil }
            return (at: at, amount: (slug.value(in: row) ?? 0).rounded())
        }

        let current = valued.filter { $0.at >= window.from }
        // Still filtered when no comparison was asked for: `start_date` is a
        // day, so a window starting mid-afternoon comes back with that
        // morning's period attached, and counting it would overstate the
        // figure by whatever happened before the window opened.
        let previous = valued.filter { $0.at < window.from }

        // Polar's own buckets, not `bucketSum`'s: the server already bucketed
        // the span at the interval that was asked for, and re-bucketing a
        // period's total by its start would move a month's revenue to
        // whichever bucket that instant happens to land in.
        let points = current.map {
            MetricPoint(t: ISO8601.string(from: $0.at), v: $0.amount)
        }

        return MetricValue(
            value: current.reduce(0) { $0 + $1.amount },
            previousValue: window.comparePrevious
                ? previous.reduce(0) { $0 + $1.amount } : nil,
            points: window.wantSeries ? points : [],
            currency: currency)
    }

    // MARK: - The payments feed

    struct Order: Decodable {
        let id: String
        let createdAt: String
        let status: String
        let totalAmount: Double
        let currency: String
        let description: String?
        let customer: Customer?
        let product: Product?

        struct Customer: Decodable {
            let name: String?
            let email: String?
        }

        struct Product: Decodable {
            let name: String?
        }

        enum CodingKeys: String, CodingKey {
            case id
            case status
            case currency
            case description
            case customer
            case product
            case createdAt = "created_at"
            case totalAmount = "total_amount"
        }
    }

    struct OrderPage: Decodable {
        let items: [Order]?
    }

    /// Orders that took payment. `pending` and `draft` did not; `void` never will.
    static let paidStatuses: Set<String> = ["paid", "refunded", "partially_refunded"]

    /// The latest paid orders, newest first.
    ///
    /// Twice the limit is asked for because the unpaid ones are filtered here
    /// rather than by Polar: ten pending orders at the top of the list would
    /// otherwise leave the feed empty. No paging beyond that one request —
    /// a feed is a glance at what just happened, and the dashboard is one
    /// click away for the rest.
    private func recentPayments(
        _ credentials: Credentials, window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let page = try await get(
            OrderPage.self, "/orders/", credentials: credentials,
            params: [
                "limit": String(Self.recentPaymentsLimit * 2),
                "sorting": "-created_at",
            ],
            http: http)

        let items = Self.rows(from: page.items ?? [], timeZone: window.timeZone)

        // The headline is their total in the user's currency, so a tile too
        // short to show rows still says something true. Rows in another
        // currency are listed with their own code rather than dropped,
        // because a list can show a currency where a sum cannot.
        let wanted = window.preferredCurrency.uppercased()
        let value = items.reduce(0.0) { total, item in
            guard item.currency?.uppercased() == wanted, let amount = item.amount else {
                return total
            }
            return total + amount
        }

        return MetricValue(
            value: value,
            points: [MetricPoint(t: ISO8601.string(from: Date()), v: value)],
            currency: window.preferredCurrency,
            items: items)
    }

    /// Polar's orders as list rows: filtered, sorted, capped.
    ///
    /// The sort and the cap are `recentPaymentsMetric`'s on the Worker, shared
    /// with every other payment provider. There is no such shared half here
    /// yet, so they are done where the rows are built — and they are not
    /// decoration: Polar's `-created_at` orders by creation while the feed
    /// claims to be newest first, which is the same thing only until an order
    /// is backdated.
    static func rows(from orders: [Order], timeZone: TimeZone) -> [MetricListItem] {
        orders
            .filter { paidStatuses.contains($0.status) }
            .compactMap { order -> (at: Date, item: MetricListItem)? in
                guard let at = instant(order.createdAt, timeZone: timeZone) else { return nil }
                return (
                    at: at,
                    item: MetricListItem(
                        id: order.id,
                        t: ISO8601.string(from: at),
                        label: nonEmpty(order.customer?.name)
                            ?? nonEmpty(order.customer?.email) ?? "Customer",
                        detail: nonEmpty(order.product?.name) ?? nonEmpty(order.description),
                        // Minor units, as Polar sends them. Never divided by
                        // 100: money stays an integer all the way to the
                        // formatter.
                        amount: order.totalAmount,
                        currency: order.currency.uppercased(),
                        status: humanStatus(order.status),
                        // No state. A payment is not pass or fail — it
                        // happened — and a tile that drew it green or red
                        // would be inventing an outcome.
                        state: nil)
                )
            }
            .sorted { $0.at > $1.at }
            .prefix(recentPaymentsLimit)
            .map(\.item)
    }

    /// `partially_refunded` as the user reads it.
    ///
    /// The first underscore only, which is what the Worker's `replace` does
    /// with a string pattern. No Polar status has two.
    static func humanStatus(_ status: String) -> String {
        guard let underscore = status.firstIndex(of: "_") else { return status }
        return status.replacingCharacters(in: underscore...underscore, with: " ")
    }

    /// Nil for a field Polar sent as an empty string.
    ///
    /// The Worker's `||` chain falls through an empty string; `??` would stop
    /// at it and label a row with nothing.
    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    // MARK: - Dates

    /// `YYYY-MM-DD` in the user's zone, because Polar's periods are calendar
    /// periods in the `timezone` the request names.
    static func isoDay(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        // POSIX, or a user on a non-Gregorian calendar gets a Buddhist year
        // in the query string and Polar answers 422.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// One of Polar's timestamps.
    ///
    /// More forms than `ISO8601.parse` accepts, and each one is a shape Polar
    /// actually sends: `/orders/` returns FastAPI's microsecond precision,
    /// which the six-digit fraction below is for, and `/metrics/` returns a
    /// period start that can arrive with no zone at all.
    ///
    /// A zone-less one is read in the zone the request asked Polar to bucket
    /// in, which is the zone those period starts are expressed in. That is a
    /// **deliberate divergence** from the Worker, and not a porting slip:
    /// `new Date("2026-01-01T00:00:00")` there reads it in the Worker's own
    /// zone, which is UTC, and so files a Tokyo user's midnight bucket nine
    /// hours early — on the far side of the window boundary for the first
    /// bucket of every window.
    static func instant(_ raw: String, timeZone: TimeZone) -> Date? {
        if let date = ISO8601.parse(raw) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd",
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}
