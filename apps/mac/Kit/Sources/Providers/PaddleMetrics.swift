import Foundation
import MetricsCore

/// Paddle's metrics, read on this Mac.
///
/// Ported from `packages/integrations/src/providers/paddle/index.ts`. The
/// arithmetic is deliberately the same arithmetic, down to which transactions
/// are excluded and how an annual price becomes a monthly one — a widget must
/// not change its number because the fetch moved off the Worker.
extension PaddleProvider {
    /// Transactions page at thirty, subscriptions at two hundred. Twenty
    /// pages of the smaller one is six hundred transactions, which is a month
    /// of a busy store; past that the walk stops and the note says so rather
    /// than reporting a number it cannot stand behind as if it were whole.
    static let maxPages = 20
    static let transactionsPage = 30
    static let subscriptionsPage = 200

    /// How many rows a list widget carries. `RECENT_PAYMENTS_LIMIT` in
    /// `packages/integrations/src/list.ts`, which is the shared half of this
    /// metric for every payment provider — so it is the same ten here.
    static let recentPaymentsLimit = 10

    public func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let creds = try Self.credentials(credentials)

        switch window.metric {
        case "mrr":
            return try await mrr(creds: creds, window: window, http: http)
        case "active_subscribers":
            return try await activeSubscribers(creds: creds, http: http)
        case "revenue":
            return try await revenue(creds: creds, window: window, http: http)
        case "new_subscribers":
            return try await subscriptionEvents(
                creds: creds, window: window, http: http, field: .started)
        case "churned_subscribers":
            return try await subscriptionEvents(
                creds: creds, window: window, http: http, field: .canceled)
        case "recent_payments":
            return try await recentPayments(creds: creds, window: window, http: http)
        default:
            // Not a bug: the catalogue is the Worker's and lists metrics this
            // build has not been taught yet. The caller falls back to the API.
            throw ProviderFailure.unsupported("This build cannot read Paddle's \(window.metric) yet.")
        }
    }

    // MARK: - Metrics

    /// A snapshot of the subscription book, not a total over a window.
    ///
    /// Each recurring item is price times quantity per cycle, normalised to a
    /// month. Other currencies are excluded and named rather than summed at
    /// 1:1, because there is no rate to convert at.
    private func mrr(
        creds: Credentials, window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let page = try await activeSubscriptions(creds: creds, http: http)
        let want = window.preferredCurrency.uppercased()
        var others: Set<String> = []
        var total: Double = 0

        for subscription in page.items {
            // The subscription's own currency, not the item price's. Paddle
            // bills a whole subscription in one currency, and a price quoted
            // in another is what the customer would have paid elsewhere.
            let code = subscription.currencyCode.uppercased()
            guard code == want else {
                others.insert(code)
                continue
            }
            for item in subscription.items {
                guard let cycle = item.price.billingCycle, item.status == "active" else { continue }
                total += toMonthly(
                    Double(try Self.minor(item.price.unitPrice.amount)) * Double(item.quantity ?? 1),
                    interval: cycle.interval,
                    intervalCount: cycle.frequency ?? 1)
            }
        }

        return MetricValue(
            // Minor units are integers. Rounding once at the end rather than
            // per subscription keeps an annual plan's twelfth from drifting
            // across a book.
            value: total.rounded(),
            currency: window.preferredCurrency,
            note: Self.join(
                Self.exclusionNote(others, want: want),
                Self.truncationNote(page.truncated, "subscriptions")))
    }

    private func activeSubscribers(
        creds: Credentials, http: ProviderHTTP
    ) async throws -> MetricValue {
        let page = try await activeSubscriptions(creds: creds, http: http)
        return MetricValue(
            value: Double(page.items.count),
            note: Self.truncationNote(page.truncated, "subscriptions"))
    }

    private func activeSubscriptions(
        creds: Credentials, http: ProviderHTTP
    ) async throws -> Walk<Subscription> {
        try await walk(
            Subscription.self, "/subscriptions", creds: creds, http: http,
            params: ["status": "active", "per_page": String(Self.subscriptionsPage)])
    }

    /// Transactions billed in the window, by their total including tax.
    ///
    /// Filtered server-side by `billed_at`, so the walk reads only the window
    /// rather than the whole ledger — which is why this metric answers for a
    /// store the subscription metrics would truncate on.
    private func revenue(
        creds: Credentials, window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let page = try await walk(
            Transaction.self, "/transactions", creds: creds, http: http,
            params: [
                "status": "paid,completed",
                "billed_at[GTE]": Self.stamp(Self.fetchStart(window)),
                "billed_at[LTE]": Self.stamp(window.to),
                "order_by": "billed_at[DESC]",
                "per_page": String(Self.transactionsPage),
            ])

        let want = window.preferredCurrency.uppercased()
        var others: Set<String> = []
        var events: [(at: Date, amount: Double)] = []

        for transaction in page.items {
            // No billing date is a transaction that has not been billed, and
            // a revenue series is bucketed by that date — there is nowhere to
            // put it.
            guard let billedAt = transaction.billedAt, let at = ISO8601.parse(billedAt) else {
                continue
            }
            let code = transaction.currencyCode.uppercased()
            guard code == want else {
                others.insert(code)
                continue
            }
            events.append((at: at, amount: Double(try Self.minor(transaction.details?.totals?.total))))
        }

        // Over the *requested* window, never the widened one. The comparison
        // period is a number, not a second series: a chart drawn over both
        // halves would show a delta the range picker never asked for.
        let points = bucketSum(
            events, from: window.from, to: window.to,
            granularity: window.granularity, timeZone: window.timeZone)
        let totals = Self.split(events, window)

        return MetricValue(
            value: totals.value,
            previousValue: totals.previousValue,
            points: window.wantSeries ? points : [],
            currency: window.preferredCurrency,
            note: Self.join(
                Self.exclusionNote(others, want: want),
                Self.truncationNote(page.truncated, "transactions")))
    }

    enum SubscriptionDate {
        case started
        case canceled
    }

    /// Subscriptions by when they started or were cancelled.
    ///
    /// Paddle's subscription list has no date filter and sorts by id only, so
    /// the whole book is read and bucketed here. The page cap bounds it; a
    /// store past the cap gets an undercount that says so.
    private func subscriptionEvents(
        creds: Credentials, window: MetricWindow, http: ProviderHTTP, field: SubscriptionDate
    ) async throws -> MetricValue {
        var params = ["per_page": String(Self.subscriptionsPage)]
        // Only churn can be narrowed. New subscriptions are counted in any
        // status, because one started and cancelled inside the same window
        // still started in it.
        if field == .canceled { params["status"] = "canceled" }

        let page = try await walk(
            Subscription.self, "/subscriptions", creds: creds, http: http, params: params)

        let events: [(at: Date, amount: Double)] = page.items.compactMap { subscription in
            // `started_at` is null on a subscription that is still trialing,
            // and `created_at` is the closest true thing — the Worker falls
            // back the same way, and a trial that never converts would
            // otherwise be invisible on the new-subscriptions tile.
            let raw: String? =
                switch field {
                case .started: subscription.startedAt ?? subscription.createdAt
                case .canceled: subscription.canceledAt
                }
            guard let raw, let at = ISO8601.parse(raw) else { return nil }
            // The whole book is in hand, so everything outside what this
            // answer covers goes now — including the comparison period, which
            // is not part of the window but is part of the answer.
            guard at >= Self.fetchStart(window), at <= window.to else { return nil }
            return (at: at, amount: 1)
        }

        let points = bucketSum(
            events, from: window.from, to: window.to,
            granularity: window.granularity, timeZone: window.timeZone)
        let totals = Self.split(events, window)

        return MetricValue(
            value: totals.value,
            previousValue: totals.previousValue,
            points: window.wantSeries ? points : [],
            note: Self.truncationNote(page.truncated, "subscriptions"))
    }

    /// Transactions that took money. `billed` is an invoice awaiting payment.
    static let paidStatuses: Set<String> = ["paid", "completed"]

    /// The latest paid transactions, as rows.
    ///
    /// One page, never a walk: a feed of ten is what the tallest tile shows,
    /// and this is the one metric polled every minute. Twenty are asked for
    /// because the status filter is applied again here — Paddle has been seen
    /// to return a `billed` row against `status=paid,completed` — and the cap
    /// to ten happens after that filter, not before it.
    private func recentPayments(
        creds: Credentials, window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let page = try await Self.get(
            Page<Transaction>.self, "/transactions", creds: creds, http: http,
            params: [
                "status": "paid,completed",
                "order_by": "billed_at[DESC]",
                "per_page": String(min(Self.recentPaymentsLimit * 2, Self.transactionsPage)),
                // Embedded, so a list of ten does not become eleven requests.
                "include": "customer",
            ])

        struct Row {
            let at: Date
            let item: MetricListItem
        }

        var rows: [Row] = []
        for transaction in page.data ?? [] {
            guard Self.paidStatuses.contains(transaction.status) else { continue }
            guard let at = ISO8601.parse(transaction.billedAt ?? transaction.createdAt) else {
                continue
            }
            rows.append(
                Row(
                    at: at,
                    item: MetricListItem(
                        id: transaction.id,
                        t: ISO8601.string(from: at),
                        // A name if Paddle has one, the email if not. Not the
                        // customer id: a row nobody recognises is a row that
                        // tells them nothing.
                        label: Self.nonEmpty(transaction.customer?.name)
                            ?? Self.nonEmpty(transaction.customer?.email) ?? "Customer",
                        detail: Self.nonEmpty(transaction.details?.lineItems?.first?.product?.name),
                        amount: Double(try Self.minor(transaction.details?.totals?.total)),
                        currency: transaction.currencyCode.uppercased(),
                        status: transaction.status,
                        // No state. A payment is not pass or fail, it just
                        // happened, and `MetricListItemState` exists for rows
                        // that have an outcome to draw.
                        state: nil)))
        }

        // Sorted and capped here rather than trusting `order_by`, which is
        // what the shared `recentPayments` builder does for every provider.
        let items = rows.sorted { $0.at > $1.at }.prefix(Self.recentPaymentsLimit).map(\.item)

        // The rows are the point, but a tile too short to show them still has
        // to say something true, and that is their total in one currency —
        // not the row count. Rows in another currency keep their own code
        // rather than being dropped, because a list can show a currency where
        // a sum cannot.
        let want = window.preferredCurrency.uppercased()
        let total = items.reduce(into: 0.0) { sum, item in
            if item.currency?.uppercased() == want { sum += item.amount ?? 0 }
        }

        return MetricValue(
            value: total,
            points: [MetricPoint(t: ISO8601.string(from: window.to), v: total)],
            currency: window.preferredCurrency,
            items: Array(items))
    }

    // MARK: - Amounts and dates

    /// `"2499"` → 2499.
    ///
    /// Paddle sends money as a string holding an integer in minor units, and
    /// it is kept an integer: parsed as a `Double` with `Double(...) ?? 0` a
    /// malformed amount becomes a free sale, which reads as a real number and
    /// is never questioned. Anything that is not an integer string is a bad
    /// response, not zero.
    static func minor(_ amount: String?) throws -> Int {
        guard let amount else { return 0 }
        guard let value = Int(amount), String(value) == amount else {
            throw ProviderFailure.badResponse("Paddle sent a non-integer amount: \(amount)")
        }
        return value
    }

    /// Paddle's time filters take RFC 3339 without a fractional second.
    static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    static func inWindow(_ at: Date, _ window: MetricWindow) -> Bool {
        at >= window.from && at <= window.to
    }

    // MARK: - The comparison period

    /// Where a fetch starts, which is earlier than the window when the tile
    /// draws a delta: the comparison period is the same length again,
    /// immediately before it.
    static func fetchStart(_ window: MetricWindow) -> Date {
        guard window.comparePrevious else { return window.from }
        return window.from.addingTimeInterval(-window.to.timeIntervalSince(window.from))
    }

    /// The window's own total, and the period before it when one was asked for.
    ///
    /// Both halves summed from the events rather than from the buckets. A
    /// window edge is an instant and a bucket is a whole day, so a headline
    /// summed from buckets pulls the preceding period's money into the figure
    /// on screen — and on a comparing metric there is now always a preceding
    /// period in hand for it to pull from.
    ///
    /// Nil rather than zero when no comparison was asked for: a tile reading
    /// zero draws "down 100%" against a window the fetch never looked at.
    static func split(
        _ events: [(at: Date, amount: Double)], _ window: MetricWindow
    ) -> (value: Double, previousValue: Double?) {
        let value = events.filter { inWindow($0.at, window) }.reduce(0) { $0 + $1.amount }
        guard window.comparePrevious else { return (value, nil) }
        // Everything not in the window, which is the earlier half and nothing
        // else: `fetchStart` is what bounded the fetch, so there is nothing
        // older than the comparison period here to be counted into it.
        let previous = events.filter { !inWindow($0.at, window) }.reduce(0) { $0 + $1.amount }
        return (value, previous)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    // MARK: - Notes

    static func exclusionNote(_ others: Set<String>, want: String) -> String? {
        guard !others.isEmpty else { return nil }
        // Sorted, so the sentence does not reorder itself between two polls
        // of the same unchanged book.
        return "\(others.sorted().joined(separator: " and ")) excluded; totals are \(want) only."
    }

    static func truncationNote(_ truncated: Bool, _ what: String) -> String? {
        guard truncated else { return nil }
        return "Only the first \(maxPages) pages of \(what) were read, so this is an undercount."
    }

    static func join(_ notes: String?...) -> String? {
        let present = notes.compactMap { $0 }
        return present.isEmpty ? nil : present.joined(separator: " ")
    }

    // MARK: - Paging

    struct Walk<T> {
        let items: [T]
        /// True when the cap was hit with more still to come, so the caller
        /// can say the number is an undercount rather than present it whole.
        let truncated: Bool
    }

    /// Follows `meta.pagination.next` until `has_more` is false or the cap.
    ///
    /// Paddle sends `next` with the original filters already on it, so the
    /// params are set once. It is resolved against the *current* URL rather
    /// than used as given, which keeps a relative `next` working and sends an
    /// absolute one pointing elsewhere back through `ProviderHTTP`'s
    /// allowlist instead of around it.
    private func walk<T: Decodable>(
        _ type: T.Type, _ path: String, creds: Credentials, http: ProviderHTTP,
        params: [String: String]
    ) async throws -> Walk<T> {
        var items: [T] = []
        var url = try Self.url(path, creds: creds, params: params)

        for _ in 0..<Self.maxPages {
            let body = try await Self.fetchJson(Page<T>.self, url, creds: creds, http: http)
            items.append(contentsOf: body.data ?? [])

            guard body.meta?.pagination?.hasMore == true,
                  let next = body.meta?.pagination?.next,
                  let resolved = URL(string: next, relativeTo: url)
            else { return Walk(items: items, truncated: false) }
            url = resolved
        }

        return Walk(items: items, truncated: true)
    }

    // MARK: - Wire shapes

    /// Paddle sends money as a string holding an integer in minor units: `"2499"`.
    ///
    /// A `String` here and not an `Int`, deliberately: decoding it as a number
    /// would make the whole response unreadable the day Paddle sends `"12.50"`,
    /// where `minor(_:)` instead names the one amount that is wrong.
    typealias Minor = String

    struct Subscription: Decodable {
        let id: String
        let status: String
        let currencyCode: String
        let createdAt: String
        let startedAt: String?
        let canceledAt: String?
        let items: [Item]

        struct Item: Decodable {
            let status: String
            let quantity: Int?
            let price: Price
        }

        struct Price: Decodable {
            let unitPrice: UnitPrice
            /// Null on a one-off price sitting on a subscription. Those are
            /// skipped by `mrr`: a charge that does not recur is not recurring
            /// revenue.
            let billingCycle: BillingCycle?

            enum CodingKeys: String, CodingKey {
                case unitPrice = "unit_price"
                case billingCycle = "billing_cycle"
            }
        }

        struct UnitPrice: Decodable {
            let amount: Minor
            let currencyCode: String

            enum CodingKeys: String, CodingKey {
                case amount
                case currencyCode = "currency_code"
            }
        }

        struct BillingCycle: Decodable {
            let interval: String
            let frequency: Int?
        }

        enum CodingKeys: String, CodingKey {
            case id
            case status
            case currencyCode = "currency_code"
            case createdAt = "created_at"
            case startedAt = "started_at"
            case canceledAt = "canceled_at"
            case items
        }
    }

    struct Transaction: Decodable {
        let id: String
        let status: String
        let currencyCode: String
        let billedAt: String?
        let createdAt: String
        /// Only present when the request asked for `include=customer`.
        let customer: Customer?
        let details: Details?

        struct Customer: Decodable {
            let name: String?
            let email: String?
        }

        struct Details: Decodable {
            let totals: Totals?
            let lineItems: [LineItem]?

            enum CodingKeys: String, CodingKey {
                case totals
                case lineItems = "line_items"
            }
        }

        struct Totals: Decodable {
            /// Including tax, before Paddle's fee. What the customer was charged,
            /// which is what the methodology on the manifest promises.
            let total: Minor?
        }

        struct LineItem: Decodable {
            let product: Product?
        }

        struct Product: Decodable {
            let name: String?
        }

        enum CodingKeys: String, CodingKey {
            case id
            case status
            case currencyCode = "currency_code"
            case billedAt = "billed_at"
            case createdAt = "created_at"
            case customer
            case details
        }
    }
}
