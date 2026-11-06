import Foundation
import MetricsCore

/// Lemon Squeezy's metrics, read on this Mac.
///
/// Ported from `packages/integrations/src/providers/lemonsqueezy/index.ts`.
/// The arithmetic is deliberately the same arithmetic, down to which orders
/// are excluded and how an annual price becomes a monthly one — a widget must
/// not change its number because the fetch moved off the Worker.
extension LemonSqueezyProvider {
    /// Pages walked before giving up, and how many rows a page asks for.
    ///
    /// The same caps the Worker uses, so the point at which a big store starts
    /// undercounting is the same point in both. 20 × 100 is the ceiling the
    /// truncation note names.
    static let maxPages = 20
    static let pageSize = 100

    /// How many rows the payments feed carries. `RECENT_PAYMENTS_LIMIT` in
    /// `packages/integrations/src/list.ts`, where the sort and the headline
    /// total live for every payment provider.
    static let recentPaymentsLimit = 10

    /// Orders that took payment. `pending`, `failed` and `fraudulent` did not.
    static let paidStatuses: Set<String> = ["paid", "refunded", "partial_refund"]

    public func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let creds = try Credentials(credentials)

        switch window.metric {
        case "revenue":
            return try await orderSeries(creds: creds, window: window, http: http) {
                Double($0.attributes.total)
            }
        case "refunds":
            // `refunded_amount`, bucketed by the *order's* date: Lemon Squeezy
            // does not expose when the refund happened, only that it did and
            // for how much. The methodology string says so.
            return try await orderSeries(creds: creds, window: window, http: http) {
                Double($0.attributes.refundedAmount ?? 0)
            }
        case "mrr":
            return try await mrr(creds: creds, window: window, http: http)
        case "active_subscribers":
            return try await activeSubscribers(creds: creds, http: http)
        case "recent_payments":
            return try await recentPayments(creds: creds, window: window, http: http)
        default:
            // Not a bug: the catalogue is the Worker's and lists metrics this
            // build has not been taught yet. The caller falls back to the API.
            throw ProviderFailure.unsupported(
                "This build cannot read Lemon Squeezy's \(window.metric) yet.")
        }
    }

    // MARK: - Metrics

    /// Revenue, or refunds — the same walk over the same orders.
    ///
    /// `amountOf` is passed in rather than read off `window.metric` because
    /// that line is the only difference between the two metrics, and a second
    /// copy of the walk is a second place for the currency filtering and the
    /// window arithmetic to drift.
    private func orderSeries(
        creds: Credentials, window: MetricWindow, http: ProviderHTTP,
        amountOf: @Sendable (Resource<OrderAttributes>) -> Double
    ) async throws -> MetricValue {
        // Only widened backwards when the tile actually draws a delta. The
        // extra half is pages rather than correctness — everything older than
        // `window.from` falls outside every bucket `bucketSum` emits — so a
        // tile with no delta on it would be paying for rows nothing reads.
        // The same condition the Worker's `comparePrevious` applies.
        let span = window.to.timeIntervalSince(window.from)
        let earliest = window.comparePrevious
            ? window.from.addingTimeInterval(-span)
            : window.from

        // Lemon Squeezy cannot filter orders by date, but it returns them
        // newest first — so the walk stops at the first order older than the
        // window instead of reading the store's whole history.
        let page = try await walk(
            OrderAttributes.self, "/orders", creds: creds, http: http,
            params: creds.storeFilter,
            stopWhen: { row in
                guard let at = Self.instant(row.attributes.createdAt) else { return false }
                return at < earliest
            })

        let paid = page.items.filter { row in
            guard Self.paidStatuses.contains(row.attributes.status),
                  let at = Self.instant(row.attributes.createdAt)
            else { return false }
            return at <= window.to
        }
        let split = Self.splitByCurrency(paid, preferred: window.preferredCurrency)

        let events: [(at: Date, amount: Double)] = split.kept.compactMap { row in
            guard let at = Self.instant(row.attributes.createdAt) else { return nil }
            let amount = amountOf(row)
            // Zero-amount rows are dropped rather than bucketed: for refunds
            // that is most of the book, and an event with no amount only
            // slows the sum down.
            guard amount > 0 else { return nil }
            return (at: at, amount: amount)
        }

        let points = bucketSum(
            events, from: window.from, to: window.to,
            granularity: window.granularity, timeZone: window.timeZone)

        let inWindow = { (at: Date) in at >= window.from && at <= window.to }
        let value = events.filter { inWindow($0.at) }.reduce(0) { $0 + $1.amount }
        // Nil rather than zero when nobody asked: a tile that reads
        // `previousValue` would otherwise draw "down 100%" against a window
        // this fetch never looked at.
        let previous: Double? = window.comparePrevious
            ? events.filter { !inWindow($0.at) }.reduce(0) { $0 + $1.amount }
            : nil

        return MetricValue(
            value: value,
            previousValue: previous,
            points: window.wantSeries ? points : [],
            currency: window.preferredCurrency,
            note: Self.join(split.note, Self.truncationNote(page.truncated)))
    }

    /// A snapshot of the subscription book, not a total over a window.
    ///
    /// A Lemon Squeezy subscription carries no amount — only a `price_id` — so
    /// the prices have to be fetched separately. They are deduplicated first:
    /// a store with 800 subscribers typically has a handful of prices, and one
    /// request per subscription would spend the whole poll on them.
    private func mrr(
        creds: Credentials, window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let page = try await activeSubscriptions(creds: creds, http: http)

        var priceIds: [Int] = []
        for row in page.items {
            guard let id = row.attributes.firstSubscriptionItem?.priceId else { continue }
            if !priceIds.contains(id) { priceIds.append(id) }
        }

        var prices: [Int: PriceAttributes] = [:]
        for id in priceIds {
            let body = try await get(
                Single<PriceAttributes>.self, "/prices/\(id)", creds: creds, http: http)
            if let attributes = body.data?.attributes { prices[id] = attributes }
        }

        var total: Double = 0
        var unpriced = 0

        for row in page.items {
            guard let item = row.attributes.firstSubscriptionItem,
                  let price = prices[item.priceId],
                  price.category == "subscription",
                  let unit = price.renewalIntervalUnit
            else {
                // A one-off purchase sold as a subscription item, or a price
                // this key could not read. Counted and named in the note
                // rather than silently treated as zero, because a book that
                // is quietly missing half its plans looks like churn.
                unpriced += 1
                continue
            }
            total += toMonthly(
                Double(price.unitPrice) * Double(item.quantity ?? 1),
                interval: unit,
                intervalCount: price.renewalIntervalQuantity ?? 1)
        }

        return MetricValue(
            // Minor units are integers. Rounding once at the end rather than
            // per subscription keeps an annual plan's twelfth from drifting
            // across a book of hundreds.
            value: total.rounded(),
            // The store's currency, which `verify` recorded. Lemon Squeezy
            // prices carry no currency of their own — a store has exactly one.
            currency: window.preferredCurrency,
            note: Self.join(
                unpriced > 0
                    // Worded character for character the same as the Worker's,
                    // because the same widget must not read differently
                    // depending on which side fetched it. Both were fixed
                    // together; neither is safe to correct alone.
                    ? "\(unpriced) subscription\(unpriced == 1 ? " was" : "s were") excluded "
                        + "for having no recurring price."
                    : nil,
                Self.truncationNote(page.truncated)))
    }

    private func activeSubscribers(
        creds: Credentials, http: ProviderHTTP
    ) async throws -> MetricValue {
        let page = try await activeSubscriptions(creds: creds, http: http)
        return MetricValue(
            value: Double(page.items.count),
            note: Self.truncationNote(page.truncated))
    }

    private func activeSubscriptions(
        creds: Credentials, http: ProviderHTTP
    ) async throws -> Walk<SubscriptionAttributes> {
        var params = creds.storeFilter
        // Trials included, which is what the methodology promises: Lemon
        // Squeezy reports a trialling subscription as `active` itself.
        params["filter[status]"] = "active"
        return try await walk(
            SubscriptionAttributes.self, "/subscriptions", creds: creds, http: http, params: params)
    }

    /// The newest orders that took payment, as rows.
    ///
    /// Orders come back newest first, so one page does — and the page asks for
    /// twice the limit because the paid filter runs on this side: a store with
    /// a run of failed checkouts would otherwise return ten rows and show
    /// three.
    private func recentPayments(
        creds: Credentials, window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        var params = creds.storeFilter
        params["page[number]"] = "1"
        params["page[size]"] = String(Self.recentPaymentsLimit * 2)

        let body = try await get(
            Page<OrderAttributes>.self, "/orders", creds: creds, http: http, params: params)

        let rows: [(at: Date, item: MetricListItem)] = (body.data ?? []).compactMap { row in
            guard Self.paidStatuses.contains(row.attributes.status),
                  // A row with no readable timestamp cannot be sorted into a
                  // feed whose whole claim is "newest first", so it is left
                  // out rather than shown in an arbitrary place.
                  let at = Self.instant(row.attributes.createdAt)
            else { return nil }

            let product = [
                row.attributes.firstOrderItem?.productName,
                row.attributes.firstOrderItem?.variantName,
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

            let buyer = [row.attributes.userName, row.attributes.userEmail]
                .compactMap { $0 }
                .first { !$0.isEmpty }

            return (
                at: at,
                item: MetricListItem(
                    id: row.id,
                    t: ISO8601.string(from: at),
                    label: buyer ?? "Customer",
                    detail: product.isEmpty ? nil : product,
                    amount: Double(row.attributes.total),
                    currency: row.attributes.currency.uppercased(),
                    status: row.attributes.status,
                    // No `state`: a payment is not pass or fail, it just
                    // happened, and drawing a tick beside every order would
                    // imply the ones without a tick failed.
                    state: nil)
            )
        }

        let items = rows.sorted { $0.at > $1.at }
            .prefix(Self.recentPaymentsLimit)
            .map(\.item)

        // Rows in another currency are listed with their own code rather than
        // dropped — a list can show a currency where a sum cannot — so the
        // headline totals only the ones in the user's. That is the shared
        // half of this metric in `list.ts`, and the one thing a provider
        // could plausibly get wrong on its own.
        let want = window.preferredCurrency.uppercased()
        let value = items.reduce(0.0) { sum, item in
            guard let amount = item.amount, item.currency?.uppercased() == want else { return sum }
            return sum + amount
        }

        return MetricValue(
            value: value,
            points: [MetricPoint(t: ISO8601.string(from: Date()), v: value)],
            currency: window.preferredCurrency,
            items: Array(items))
    }

    // MARK: - Notes

    /// Only the currencies the user asked for.
    ///
    /// Summing mixed currencies at 1:1 is the kind of wrong that looks right,
    /// so other currencies are dropped and the exclusion is named in the note.
    /// Named rather than counted, unlike Stripe's: a Lemon Squeezy store sells
    /// in one currency, so a row in another means the user pointed the notch
    /// at a different one and the code is the useful half of that sentence.
    static func splitByCurrency(
        _ rows: [Resource<OrderAttributes>], preferred: String
    ) -> (kept: [Resource<OrderAttributes>], note: String?) {
        let want = preferred.uppercased()
        let kept = rows.filter { $0.attributes.currency.uppercased() == want }
        let others = Set(rows.map { $0.attributes.currency.uppercased() }).subtracting([want])
        guard !others.isEmpty else { return (kept, nil) }
        return (kept, "\(others.sorted().joined(separator: " and ")) excluded; totals are \(want) only.")
    }

    /// Said when the cap was hit with orders still to come.
    ///
    /// A number that is too low is reported with the reason rather than
    /// refused: unlike Stripe, this adapter has no Sigma to point at, and a
    /// store that large still wants today's figure.
    static func truncationNote(_ truncated: Bool) -> String? {
        truncated
            ? "Only the first \(maxPages * pageSize) records were read, so this is an undercount."
            : nil
    }

    static func join(_ notes: String?...) -> String? {
        let present = notes.compactMap { $0 }.filter { !$0.isEmpty }
        return present.isEmpty ? nil : present.joined(separator: " ")
    }

    /// A Lemon Squeezy timestamp.
    ///
    /// Microseconds (`2026-02-05T14:22:13.000000Z`) and whole seconds both
    /// arrive, depending on the resource, and `ISO8601.parse` takes either.
    static func instant(_ raw: String) -> Date? { ISO8601.parse(raw) }

    // MARK: - Paging

    struct Walk<A: Decodable & Sendable>: Sendable {
        let items: [Resource<A>]
        /// True when the cap was hit with more still to come, so the caller
        /// reports a number it cannot stand behind rather than a wrong one.
        let truncated: Bool
    }

    /// Walks `page[number]` until a short page, `lastPage`, or `stopWhen`.
    ///
    /// `stopWhen` lets a caller end the walk early on an ordering it knows
    /// about — orders come back newest first, so a date-windowed query does
    /// not have to read the whole history of the store.
    func walk<A: Decodable & Sendable>(
        _ type: A.Type, _ path: String, creds: Credentials, http: ProviderHTTP,
        params: [String: String], stopWhen: (@Sendable (Resource<A>) -> Bool)? = nil
    ) async throws -> Walk<A> {
        var items: [Resource<A>] = []

        for page in 1...Self.maxPages {
            var query = params
            query["page[number]"] = String(page)
            query["page[size]"] = String(Self.pageSize)

            let body = try await get(Page<A>.self, path, creds: creds, http: http, params: query)
            let batch = body.data ?? []

            for row in batch {
                if stopWhen?(row) == true { return Walk(items: items, truncated: false) }
                items.append(row)
            }

            // A short page is the end of the list. The `lastPage` check is the
            // second of two on purpose: `meta` is absent on some responses,
            // and treating a missing `lastPage` as "keep going" is what a
            // short page then stops.
            if batch.count < Self.pageSize { return Walk(items: items, truncated: false) }
            if let last = body.meta?.page?.lastPage, page >= last {
                return Walk(items: items, truncated: false)
            }
        }

        return Walk(items: items, truncated: true)
    }
}
