import Foundation
import MetricsCore

/// Dodo Payments' metrics, read on this Mac.
///
/// Ported from `packages/integrations/src/providers/dodopayments/index.ts`.
/// The arithmetic is deliberately the same arithmetic, down to which payments
/// are excluded and how an annual plan becomes a monthly amount — a widget
/// must not change its number because the fetch moved off the Worker.
extension DodoPaymentsProvider {
    /// Pages walked before giving up, and the page size asked for.
    ///
    /// The same caps the Worker uses, so the point at which a big account's
    /// number becomes an undercount is the same in both. Termination is on a
    /// page shorter than `pageSize`, because Dodo sends no cursor and no
    /// `has_more`: a loop waiting for a cursor field it never sends does not
    /// end.
    static let maxPages = 20
    static let pageSize = 100

    /// Rows a list widget carries. `RECENT_PAYMENTS_LIMIT` in `list.ts`, which
    /// is what the tallest tile can show.
    static let recentPaymentsLimit = 10

    public func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let key = try requiredCredential(credentials, "api_key")
        let mode = Self.mode(in: credentials)

        switch window.metric {
        case "mrr":
            return try await mrr(key: key, mode: mode, window: window, http: http)
        case "active_subscribers":
            return try await activeSubscribers(key: key, mode: mode, http: http)
        case "revenue":
            return try await revenue(
                key: key, mode: mode, window: window, http: http, include: { _ in true })
        case "one_time_sales":
            return try await revenue(
                key: key, mode: mode, window: window, http: http, include: { $0.isOneTime })
        case "recent_payments":
            return try await recentPayments(key: key, mode: mode, window: window, http: http)
        default:
            // Not a bug: the catalogue is the Worker's and lists metrics this
            // build has not been taught yet. The caller falls back to the API.
            throw ProviderFailure.unsupported(
                "This build cannot read Dodo Payments' \(window.metric) yet.")
        }
    }

    // MARK: - Metrics

    /// A snapshot of the subscription book, not a total over a window.
    ///
    /// The value is deliberately not the sum of any series: MRR is what the
    /// book is worth right now, and Dodo exposes no history of it. The window
    /// is used only to pick the currency to report in.
    private func mrr(
        key: String, mode: Mode, window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let page = try await walk(
            DodoSubscription.self, "/subscriptions", key: key, mode: mode, http: http,
            params: ["status": "active"])
        let split = Self.splitByCurrency(page.items, preferred: window.preferredCurrency)

        let total = split.kept.reduce(0.0) { sum, row in
            sum
                + toMonthly(
                    row.recurringPreTaxAmount,
                    // Dodo capitalises these ("Month"); `toMonthly` matches on
                    // lower case and would otherwise fall through to its
                    // unknown-interval case and report a yearly plan's full
                    // price as one month's.
                    interval: row.paymentFrequencyInterval.lowercased(),
                    intervalCount: row.paymentFrequencyCount)
        }

        return MetricValue(
            // Minor units are integers. Rounding once at the end rather than
            // per subscription keeps an annual plan's twelfth from drifting
            // across a book.
            value: total.rounded(),
            currency: window.preferredCurrency,
            note: Self.join(split.note, Self.truncationNote(page.truncated)))
    }

    /// Subscriptions in status `active` right now.
    ///
    /// Counted across every currency — unlike MRR, a head count of a mixed
    /// book is still a true number.
    private func activeSubscribers(
        key: String, mode: Mode, http: ProviderHTTP
    ) async throws -> MetricValue {
        let page = try await walk(
            DodoSubscription.self, "/subscriptions", key: key, mode: mode, http: http,
            params: ["status": "active"])
        return MetricValue(
            value: Double(page.items.count),
            note: Self.truncationNote(page.truncated))
    }

    /// Succeeded payments in the window, summed — optionally only those
    /// `include` says yes to.
    ///
    /// Total revenue and one-time sales are the same walk with a different
    /// filter, because the list has no server-side way to ask for either.
    ///
    /// When the widget asked to compare, the fetched range is widened
    /// backwards by the window's own length and the earlier half becomes
    /// `previousValue` — one walk rather than two, because Dodo's filter takes
    /// a range and a second request would pay the round trips again.
    ///
    /// Only when it asked. The flag doubles the rows read, and a tile with no
    /// delta on it would be paying that for nothing.
    private func revenue(
        key: String, mode: Mode, window: MetricWindow, http: ProviderHTTP,
        include: (DodoPayment) -> Bool
    ) async throws -> MetricValue {
        let page = try await walk(
            DodoPayment.self, "/payments", key: key, mode: mode, http: http,
            params: [
                "created_at_gte": Self.timestamp(Self.fetchFrom(window)),
                "created_at_lte": Self.timestamp(window.to),
            ])

        return Self.revenueValue(
            page.items, truncated: page.truncated, window: window, include: include)
    }

    /// The earliest instant a revenue walk asks for.
    ///
    /// The window's own length again, back from its start, when a comparison
    /// was asked for: the previous period has to be the same length or the
    /// delta is between a month and a fortnight.
    static func fetchFrom(_ window: MetricWindow) -> Date {
        guard window.comparePrevious else { return window.from }
        return window.from.addingTimeInterval(-window.to.timeIntervalSince(window.from))
    }

    /// The arithmetic of a revenue metric, over rows already fetched.
    ///
    /// Separate from the walk so the part a port gets wrong — which payments
    /// count, which currency, which half of a widened range — is reachable
    /// without a network.
    static func revenueValue(
        _ payments: [DodoPayment], truncated: Bool, window: MetricWindow,
        include: (DodoPayment) -> Bool
    ) -> MetricValue {
        // Gross, and only money that actually arrived. `processing` has not
        // been captured and `requires_capture` may never be.
        let succeeded = payments.filter { $0.status == "succeeded" && include($0) }
        let split = splitByCurrency(succeeded, preferred: window.preferredCurrency)

        let events: [(at: Date, amount: Double)] = split.kept.compactMap { row in
            guard let at = ISO8601.parse(row.createdAt) else { return nil }
            return (at: at, amount: row.totalAmount)
        }

        // Buckets over the requested window only, so the chart is the window
        // the widget asked for even when twice as much was fetched. The
        // earlier half lands on bucket starts this never emits and is
        // therefore left out of the series by construction.
        let points = bucketSum(
            events, from: window.from, to: window.to,
            granularity: window.granularity, timeZone: window.timeZone)

        // Summed from the events rather than from the buckets: the window's
        // edges are instants and a bucket is a whole day, so the first and
        // last bucket can reach outside what was asked for — which with a
        // comparison fetched would pull the preceding period's money into the
        // headline.
        let inWindow = { (at: Date) in at >= window.from && at <= window.to }
        let value = events.filter { inWindow($0.at) }.reduce(0.0) { $0 + $1.amount }
        let previousValue = window.comparePrevious
            ? events.filter { !inWindow($0.at) }.reduce(0.0) { $0 + $1.amount }
            : nil

        return MetricValue(
            value: value,
            previousValue: previousValue,
            points: window.wantSeries ? points : [],
            currency: window.preferredCurrency,
            note: join(split.note, truncationNote(truncated)))
    }

    /// The newest payments that actually took money.
    ///
    /// One page, over-fetched by a factor of two: Dodo lists newest first, so
    /// twice the limit covers a run of failed attempts at the top without
    /// walking pages on every poll.
    private func recentPayments(
        key: String, mode: Mode, window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let body = try await get(
            DodoList<DodoPayment>.self, "/payments", key: key, mode: mode, http: http,
            params: [
                "page_size": String(Self.recentPaymentsLimit * 2),
                "page_number": "0",
            ])

        let rows = (body.items ?? [])
            .filter { $0.status == "succeeded" }
            .compactMap(Self.listItem)

        return Self.recentPaymentsValue(rows, preferred: window.preferredCurrency)
    }

    /// One payment as a list row, or nothing if its timestamp cannot be read.
    ///
    /// Dropped rather than kept with a placeholder date: the sort and the cap
    /// below are on the timestamp, so a row with an unreadable one would take
    /// a slot at one end of the feed from a payment that really happened.
    static func listItem(_ payment: DodoPayment) -> MetricListItem? {
        guard let at = ISO8601.parse(payment.createdAt) else { return nil }
        let name = payment.customer?.name?.trimmingCharacters(in: .whitespaces)
        let email = payment.customer?.email?.trimmingCharacters(in: .whitespaces)
        return MetricListItem(
            id: payment.paymentId,
            t: ISO8601.string(from: at),
            label: (name?.isEmpty == false ? name : nil)
                ?? (email?.isEmpty == false ? email : nil)
                ?? "Customer",
            detail: nil,
            amount: payment.totalAmount,
            currency: payment.currency.uppercased(),
            status: payment.status,
            // No state: a payment is not pass or fail, it just happened, and
            // these are the succeeded ones anyway.
            state: nil)
    }

    /// The shared half of a payments feed: the sort, the cap and the headline.
    ///
    /// A port of `recentPayments` in `list.ts`. The headline is not the row
    /// count — it is the rows' total in the user's own currency, so a tile too
    /// short to show rows still says something true. Rows in another currency
    /// stay in the list with their own code rather than being dropped, because
    /// a list can show a currency where a sum cannot.
    static func recentPaymentsValue(
        _ rows: [MetricListItem], preferred: String
    ) -> MetricValue {
        let items = rows
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .prefix(recentPaymentsLimit)
        let want = preferred.uppercased()
        let value = items.reduce(0.0) { sum, item in
            guard let amount = item.amount, item.currency?.uppercased() == want else { return sum }
            return sum + amount
        }

        return MetricValue(
            value: value,
            // The one point the Worker emits for this metric. The widget draws
            // no chart, but the shape stays the same on both paths.
            points: [MetricPoint(t: ISO8601.string(from: Date()), v: value)],
            currency: preferred,
            items: Array(items))
    }

    // MARK: - Notes

    /// Keeps only the currencies the user asked for, and names the rest.
    ///
    /// Summing mixed currencies at 1:1 is the kind of wrong that looks right,
    /// so other currencies are dropped and the exclusion is said out loud.
    static func splitByCurrency<T: DodoRow>(
        _ rows: [T], preferred: String
    ) -> (kept: [T], note: String?) {
        let want = preferred.uppercased()
        let kept = rows.filter { $0.currency.uppercased() == want }
        let others = Set(rows.map { $0.currency.uppercased() }.filter { $0 != want })
        guard !others.isEmpty else { return (kept, nil) }
        return (
            kept,
            "\(others.sorted().joined(separator: " and ")) excluded; totals are \(want) only."
        )
    }

    static func truncationNote(_ truncated: Bool) -> String? {
        truncated
            ? "Only the first \(maxPages * pageSize) records were read, so this is an undercount."
            : nil
    }

    static func join(_ notes: String?...) -> String? {
        let present = notes.compactMap { $0 }.filter { !$0.isEmpty }
        return present.isEmpty ? nil : present.joined(separator: " ")
    }

    /// What Dodo's `created_at_gte`/`_lte` filters expect, and what the Worker
    /// sends them: an ISO-8601 instant with fractional seconds.
    static func timestamp(_ date: Date) -> String { ISO8601.string(from: date) }

    // MARK: - Paging

    struct Page<T> {
        let items: [T]
        /// True when the cap was hit with a full page still coming, so the
        /// caller can say the figure is an undercount rather than present it
        /// as the whole book.
        let truncated: Bool
    }

    /// Walks `page_number` until a page comes back short.
    func walk<T: Decodable>(
        _ type: T.Type, _ path: String, key: String, mode: Mode, http: ProviderHTTP,
        params: [String: String]
    ) async throws -> Page<T> {
        var items: [T] = []

        for page in 0..<Self.maxPages {
            var query = params
            query["page_number"] = String(page)
            query["page_size"] = String(Self.pageSize)

            let body = try await get(
                DodoList<T>.self, path, key: key, mode: mode, http: http, params: query)
            let batch = body.items ?? []
            items.append(contentsOf: batch)
            if batch.count < Self.pageSize { return Page(items: items, truncated: false) }
        }

        return Page(items: items, truncated: true)
    }
}
