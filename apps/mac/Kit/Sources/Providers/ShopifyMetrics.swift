import Foundation
import MetricsCore

/// Shopify's metrics, read on this Mac.
///
/// Ported from `packages/integrations/src/providers/shopify/index.ts`. The
/// arithmetic is deliberately the same arithmetic — which orders count as
/// paid, which money bag each metric reads, where a walk stops and what it
/// says when it does — because a widget must not change its number because
/// the fetch moved off the Worker.
extension ShopifyProvider {
    /// Orders are read by walking the `orders` connection rather than by
    /// asking ShopifyQL for a pre-aggregated series.
    ///
    /// ShopifyQL would be cheaper and would match the merchant's own Analytics
    /// page exactly — but it needs `read_reports`, which is a third scope
    /// beyond the two a merchant grants us, and it is not on every Shopify
    /// plan. A connector that works for everyone who grants `read_orders`
    /// beats one that is exact for some and broken for the rest.
    ///
    /// The cost of that choice is this cap. Shopify's budget is points per
    /// second rather than requests, and a page of 120 orders with two money
    /// bags each costs about 600 of a standard store's 1000 — so the walk is
    /// bounded and *says so* in the note rather than quietly reporting a
    /// fraction of a busy month.
    static let pageSize = 120
    static let maxPages = 5

    /// Customers carry no nested objects, so a page of them is cheap.
    static let customerPageSize = 250
    static let customerMaxPages = 4

    /// How many rows a list widget carries. `RECENT_PAYMENTS_LIMIT` in
    /// `packages/integrations/src/list.ts`, and the two have to agree or the
    /// same tile shows a different number of payments on either path.
    static let recentPaymentsLimit = 10

    /// An order that took money.
    ///
    /// `AUTHORIZED` and `PENDING` have not: an authorisation can expire and a
    /// pending bank transfer can never arrive, and counting either as a sale
    /// makes today's revenue drift *downwards* over the following week.
    static let paidStatuses: Set<String> = [
        "PAID", "PARTIALLY_PAID", "PARTIALLY_REFUNDED", "REFUNDED",
    ]

    public func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let creds = try Self.credentials(credentials)

        // One wrapper rather than seven: a `Throttled` that escapes is logged
        // as an unhandled error and the tile says "something went wrong",
        // with the wait Shopify asked for thrown away.
        return try await Self.unthrottled {
            switch window.metric {
            case "revenue":
                return try await fromOrders(creds, window: window, http: http, kind: .money)
            case "orders":
                return try await fromOrders(creds, window: window, http: http, kind: .count)
            case "average_order_value":
                return try await fromOrders(creds, window: window, http: http, kind: .average)
            case "refunds":
                return try await fromOrders(
                    creds, window: window, http: http, kind: .money,
                    bag: { Self.money($0.totalRefundedSet)?.amount ?? 0 })
            case "new_customers":
                return try await newCustomers(creds, window: window, http: http)
            case "customers":
                return try await totalCustomers(creds, http: http)
            case "recent_payments":
                return try await recentPayments(creds, window: window, http: http)
            default:
                // Not a bug: the catalogue is the Worker's and lists metrics
                // this build has not been taught yet. The caller falls back to
                // the API.
                throw ProviderFailure.unsupported(
                    "This build cannot read Shopify's \(window.metric) yet.")
            }
        }
    }

    // MARK: - Queries

    static let ORDERS_PAGE = """
        query NotchOrders($first: Int!, $after: String, $query: String!) {
          orders(first: $first, after: $after, query: $query, sortKey: CREATED_AT, reverse: true) {
            nodes {
              id
              name
              createdAt
              test
              displayFinancialStatus
              totalPriceSet { shopMoney { amount currencyCode } }
              totalRefundedSet { shopMoney { amount currencyCode } }
            }
            pageInfo { hasNextPage endCursor }
          }
        }
        """

    static let RECENT_ORDERS = """
        query NotchRecentOrders($first: Int!) {
          orders(first: $first, sortKey: CREATED_AT, reverse: true) {
            nodes {
              id
              name
              createdAt
              test
              displayFinancialStatus
              totalPriceSet { shopMoney { amount currencyCode } }
              totalRefundedSet { shopMoney { amount currencyCode } }
              customer { displayName email }
              lineItems(first: 1) { nodes { title } }
            }
          }
        }
        """

    static let CUSTOMERS_PAGE = """
        query NotchCustomers($first: Int!, $after: String, $query: String!) {
          customers(first: $first, after: $after, query: $query, sortKey: CREATED_AT, reverse: true) {
            nodes { id createdAt }
            pageInfo { hasNextPage endCursor }
          }
        }
        """

    static let CUSTOMERS_TOTAL = """
        query NotchCustomersTotal {
          customersCount { count precision }
        }
        """

    /// A Shopify search-syntax window. Inclusive at both ends, like the request.
    static func createdBetween(_ from: Date, _ to: Date) -> String {
        "created_at:>='\(ISO8601.string(from: from))' created_at:<='\(ISO8601.string(from: to))'"
    }

    // MARK: - The order walk

    /// Everything one walk of the orders connection produced.
    struct Walked {
        let orders: [Order]
        /// Hit the page cap or a throttle: every total from this walk is a floor.
        let truncated: Bool
        /// How many orders had been read when Shopify started throttling, or nil.
        let throttledAfter: Int?
    }

    /// Shopify paginates this connection with a cursor in the *body* —
    /// `pageInfo.endCursor` — rather than with a `Link` header.
    ///
    /// Both exist at Shopify: the retired REST Admin API pages with `Link`,
    /// and the GraphQL one this adapter speaks does not. The Worker's adapter
    /// walks cursors, so this walks cursors; reading a header that is never
    /// sent would stop after the first page and report a fraction of the
    /// window as though it were all of it.
    func walkOrders(
        _ credentials: Credentials, from: Date, to: Date, http: ProviderHTTP
    ) async throws -> Walked {
        var orders: [Order] = []
        var after: String?

        for _ in 0..<Self.maxPages {
            let body: OrdersPage
            do {
                body = try await graphql(
                    OrdersPage.self, credentials, query: Self.ORDERS_PAGE,
                    variables: Variables(
                        first: Self.pageSize, after: after,
                        query: Self.createdBetween(from, to)),
                    http: http)
            } catch let throttled as Throttled {
                // The first page is an error — there is nothing to show. A
                // later one is a bounded undercount, which the note explains,
                // and that beats blanking a tile that already has most of the
                // month in it.
                if orders.isEmpty {
                    throw ProviderFailure.rateLimited(
                        "\(credentials.shopDomain) is rate limited",
                        retryAfter: throttled.retryAfterSeconds)
                }
                return Walked(orders: orders, truncated: true, throttledAfter: orders.count)
            }

            orders.append(contentsOf: body.orders.nodes)
            if !body.orders.pageInfo.hasNextPage {
                return Walked(orders: orders, truncated: false, throttledAfter: nil)
            }
            // `hasNextPage` with no cursor would otherwise re-request the
            // first page until the cap, five times over.
            guard let cursor = body.orders.pageInfo.endCursor else {
                return Walked(orders: orders, truncated: false, throttledAfter: nil)
            }
            after = cursor
        }

        return Walked(orders: orders, truncated: true, throttledAfter: nil)
    }

    static func paidOrders(_ walked: Walked) -> [Order] {
        walked.orders.filter { order in
            !(order.test ?? false) && paidStatuses.contains(order.displayFinancialStatus ?? "")
        }
    }

    // MARK: - Sales, orders, AOV and refunds

    /// What a metric wants out of the shared walk.
    ///
    /// `revenue` and `refunds` differ only in which money bag they read;
    /// `orders` counts rows; `average_order_value` is the window's own ratio.
    enum OrderKind {
        case money
        case count
        case average
    }

    /// Sales, orders, AOV and refunds, all from one walk.
    ///
    /// One shared body rather than four, because the four metrics disagree
    /// about what to *do* with an order and not about which orders there are
    /// — and because on the Worker a user with all four tiles sends them as
    /// one batch, where four walks would be four times the Shopify budget for
    /// exactly the same orders.
    private func fromOrders(
        _ credentials: Credentials, window: MetricWindow, http: ProviderHTTP,
        kind: OrderKind,
        /// Which bag the amount comes out of.
        ///
        /// Defaulted to the order total, which is what three of the four want:
        /// sales sum it, the average divides it by the row count, and only
        /// refunds read the other bag. A default of zero here would make the
        /// average — which takes no `bag` of its own — read zero on every
        /// store, and a zero AOV looks like a quiet day rather than a bug.
        bag: @Sendable (Order) -> Double = {
            ShopifyProvider.money($0.totalPriceSet)?.amount ?? 0
        }
    ) async throws -> MetricValue {
        // The comparison window, when the tile wants a delta: widened
        // backwards by the window's own length, with only the later half
        // reported as `value`. Opt-in because it doubles the orders read.
        let windowLength = window.to.timeIntervalSince(window.from)
        let from =
            window.comparePrevious
            ? window.from.addingTimeInterval(-windowLength) : window.from

        let walked = try await walkOrders(
            credentials, from: from, to: window.to, http: http)
        let paid = Self.paidOrders(walked)
        let currency = Self.shopCurrency(paid, fallback: window.preferredCurrency)

        // An order whose timestamp cannot be read is dropped rather than
        // counted in the comparison half: it is not in the window, and
        // `previousValue` is where "not in the window" otherwise lands.
        let events: [(at: Date, amount: Double)] = paid.compactMap { order in
            guard let at = Self.instant(order.createdAt) else { return nil }
            return (at: at, amount: bag(order))
        }

        let current = events.filter { $0.at >= window.from && $0.at <= window.to }
        let previous = events.filter { !($0.at >= window.from && $0.at <= window.to) }
        func sum(_ rows: [(at: Date, amount: Double)]) -> Double {
            rows.reduce(0) { $0 + $1.amount }
        }
        func bucket(_ rows: [(at: Date, amount: Double)]) -> [MetricPoint] {
            bucketSum(
                rows, from: window.from, to: window.to,
                granularity: window.granularity, timeZone: window.timeZone)
        }

        switch kind {
        case .count:
            let points = bucket(current.map { (at: $0.at, amount: 1) })
            return MetricValue(
                value: Double(current.count),
                previousValue: window.comparePrevious ? Double(previous.count) : nil,
                points: window.wantSeries ? points : [],
                // No currency: this one is a count, and labelling it in money
                // would have the tile format "14" as $0.14.
                currency: nil,
                note: Self.truncationNote(walked))

        case .average:
            // Same from, to and granularity, so the two walks produce the
            // same bucket sequence and can be zipped.
            let totals = bucket(current)
            let counts = bucket(current.map { (at: $0.at, amount: 1) })
            let points = zip(totals, counts).map { total, count in
                MetricPoint(t: total.t, v: Self.divide(total.v, count.v))
            }
            return MetricValue(
                // The headline is the window's own ratio, not the mean of the
                // points: a Tuesday with two orders would otherwise weigh as
                // much as a Black Friday with four hundred.
                value: Self.divide(sum(current), Double(current.count)),
                previousValue: window.comparePrevious
                    ? Self.divide(sum(previous), Double(previous.count)) : nil,
                points: window.wantSeries ? points : [],
                currency: currency,
                note: Self.notes(
                    Self.currencyNote(currency, preferred: window.preferredCurrency),
                    Self.truncationNote(walked)))

        case .money:
            let points = bucket(current)
            return MetricValue(
                value: sum(current),
                previousValue: window.comparePrevious ? sum(previous) : nil,
                points: window.wantSeries ? points : [],
                currency: currency,
                note: Self.notes(
                    Self.currencyNote(currency, preferred: window.preferredCurrency),
                    Self.truncationNote(walked)))
        }
    }

    /// Zero rather than NaN: a day with no orders has no average, and 0 renders.
    static func divide(_ total: Double, _ count: Double) -> Double {
        count == 0 ? 0 : (total / count).rounded()
    }

    // MARK: - Customers

    private func newCustomers(
        _ credentials: Credentials, window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let windowLength = window.to.timeIntervalSince(window.from)
        let from =
            window.comparePrevious
            ? window.from.addingTimeInterval(-windowLength) : window.from

        var rows: [Customer] = []
        var after: String?
        // True until a page says it is the last one. A walk that runs the cap
        // out never gets that confirmation, and the note says so.
        var truncated = true

        for _ in 0..<Self.customerMaxPages {
            let body = try await graphql(
                CustomersPage.self, credentials, query: Self.CUSTOMERS_PAGE,
                variables: Variables(
                    first: Self.customerPageSize, after: after,
                    query: Self.createdBetween(from, window.to)),
                http: http)
            rows.append(contentsOf: body.customers.nodes)
            guard body.customers.pageInfo.hasNextPage,
                  let cursor = body.customers.pageInfo.endCursor
            else {
                truncated = false
                break
            }
            after = cursor
        }

        let events: [(at: Date, amount: Double)] = rows.compactMap { row in
            guard let at = Self.instant(row.createdAt) else { return nil }
            return (at: at, amount: 1)
        }
        let current = events.filter { $0.at >= window.from && $0.at <= window.to }
        let points = bucketSum(
            current, from: window.from, to: window.to,
            granularity: window.granularity, timeZone: window.timeZone)

        return MetricValue(
            value: Double(current.count),
            previousValue: window.comparePrevious
                ? Double(events.count - current.count) : nil,
            points: window.wantSeries ? points : [],
            note: truncated
                ? "Only the first \(Self.customerMaxPages * Self.customerPageSize) customers "
                    + "in the window were read, so this is an undercount."
                : nil)
    }

    private func totalCustomers(
        _ credentials: Credentials, http: ProviderHTTP
    ) async throws -> MetricValue {
        let body = try await graphql(
            CustomersTotal.self, credentials, query: Self.CUSTOMERS_TOTAL, http: http)

        return MetricValue(
            value: Double(body.customersCount?.count ?? 0),
            // Shopify stops counting at ten thousand and says so in
            // `precision`. Passing that on matters: the tile is otherwise a
            // store's growth flatlining at exactly 10,000 with no explanation.
            note: body.customersCount?.precision == "AT_LEAST"
                ? "Shopify reports this as a floor rather than an exact count "
                    + "above ten thousand."
                : nil)
    }

    // MARK: - The payments feed

    /// The latest orders that took payment, newest first.
    ///
    /// Twice the limit is asked for because the newest orders include the
    /// unpaid ones and those are filtered here rather than by Shopify: ten
    /// pending orders at the top would otherwise leave the feed empty. No
    /// paging beyond that one request — a feed is a glance at what just
    /// happened, and the admin is one click away for the rest.
    private func recentPayments(
        _ credentials: Credentials, window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let body = try await graphql(
            RecentOrders.self, credentials, query: Self.RECENT_ORDERS,
            variables: Variables(first: Self.recentPaymentsLimit * 2), http: http)

        let rows = Self.rows(from: body.orders.nodes)

        // A store sells in exactly one currency, and it is usually not the
        // one the notch was told to prefer. Totalling in the user's filters
        // every row out and the tile reads zero beside a list of ten sales,
        // so the store's own currency wins and the note says so. The same
        // `totalIn` override the Worker's `recentPaymentsMetric` takes — and
        // it is read off the uncapped rows, as there.
        let totalledIn =
            rows.first(where: { $0.currency != nil })?.currency ?? window.preferredCurrency
        let items = Array(rows.prefix(Self.recentPaymentsLimit))

        // The headline is not the row count: a tile too short to show rows
        // still has to say something true, and that is their total in one
        // currency. Rows in another are listed with their own code rather
        // than dropped, because a list can show a currency where a sum cannot.
        let wanted = totalledIn.uppercased()
        let value = items.reduce(0.0) { total, item in
            guard item.currency?.uppercased() == wanted, let amount = item.amount else {
                return total
            }
            return total + amount
        }

        return MetricValue(
            value: value,
            points: [MetricPoint(t: ISO8601.string(from: Date()), v: value)],
            currency: totalledIn,
            items: items,
            note: Self.currencyNote(totalledIn, preferred: window.preferredCurrency))
    }

    /// Shopify's orders as list rows: filtered, sorted, newest first.
    ///
    /// The sort is `recentPaymentsMetric`'s on the Worker, shared with every
    /// other payment provider. It is not decoration: Shopify's
    /// `sortKey: CREATED_AT` orders by creation while the feed claims to be
    /// newest first, which is the same thing only until an order is
    /// backdated. The cap is applied by the caller, after the currency for
    /// the headline has been read off the full set.
    static func rows(from orders: [Order]) -> [MetricListItem] {
        orders
            .filter { !($0.test ?? false) && paidStatuses.contains($0.displayFinancialStatus ?? "") }
            .compactMap { order -> (at: Date, item: MetricListItem)? in
                guard let at = instant(order.createdAt) else { return nil }
                let total = money(order.totalPriceSet)
                return (
                    at: at,
                    item: MetricListItem(
                        id: order.id,
                        t: ISO8601.string(from: at),
                        // The order number is the fallback rather than
                        // "Customer": every Shopify order has one, it is what
                        // the merchant searches by, and a list of ten rows all
                        // reading "Customer" identifies nothing.
                        label: nonEmpty(order.customer?.displayName)
                            ?? nonEmpty(order.customer?.email) ?? nonEmpty(order.name)
                            ?? order.id,
                        detail: nonEmpty(order.lineItems?.nodes.first?.title),
                        // Minor units, from Shopify's decimal string. Never
                        // divided by 100: money stays an integer all the way
                        // to the formatter.
                        amount: total?.amount,
                        currency: total?.currency,
                        status: order.displayFinancialStatus?.lowercased(),
                        // No state. A payment is not pass or fail — it
                        // happened — and a tile that drew it green or red
                        // would be inventing an outcome.
                        state: nil)
                )
            }
            .sorted { $0.at > $1.at }
            .map(\.item)
    }

    /// Nil for a field Shopify sent as an empty string.
    ///
    /// The Worker's `||` chain falls through an empty string; `??` would stop
    /// at it and label a row with nothing.
    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    // MARK: - Money

    /// Shopify reports money as a decimal string in the shop's currency.
    ///
    /// Reported in that currency rather than converted into the user's
    /// preferred one, and rather than filtered down to it the way a
    /// multi-currency processor's rows are: `shopMoney` is *already* one
    /// currency — the store's — so there is nothing to exclude, and inventing
    /// a rate would be the kind of wrong that looks right.
    static func money(_ bag: MoneyBag?) -> (amount: Double, currency: String)? {
        guard let shopMoney = bag?.shopMoney else { return nil }
        let currency = shopMoney.currencyCode.uppercased()
        guard let parsed = Double(shopMoney.amount), parsed.isFinite else { return nil }
        return (amount: minorUnits(parsed, currency: currency), currency: currency)
    }

    /// A decimal major-unit amount as integer minor units.
    ///
    /// $12.34 is 1234 and ¥1234 is 1234 — the exponent depends on the
    /// currency, not on how many digits Shopify happened to print, and the
    /// exceptions are the whole reason this is a table: multiplying by 100
    /// would make every yen figure a hundred times too large and every dinar
    /// a tenth of what it is.
    ///
    /// The same table as `MINOR_UNIT_EXPONENT` in
    /// `packages/integrations/src/normalise.ts`. Rounded rather than
    /// truncated, so a half-cent from a tax or discount split does not vanish.
    static func minorUnits(_ amount: Double, currency: String) -> Double {
        let exponent: Int
        switch currency.uppercased() {
        case "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW",
             "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF":
            exponent = 0
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND":
            exponent = 3
        default:
            exponent = 2
        }
        return (amount * pow(10, Double(exponent))).rounded()
    }

    /// The currency every figure in this walk is in.
    ///
    /// Read off the orders rather than asked for, because `verify` runs once
    /// and a store can change its currency afterwards. Falls back to the
    /// user's preference only when the window held no orders at all, where
    /// the figure is zero and the label does not matter.
    static func shopCurrency(_ orders: [Order], fallback: String) -> String {
        for order in orders {
            if let total = money(order.totalPriceSet) { return total.currency }
        }
        return fallback.uppercased()
    }

    // MARK: - Notes

    static func notes(_ parts: String?...) -> String? {
        let present = parts.compactMap { $0 }
        return present.isEmpty ? nil : present.joined(separator: " ")
    }

    static func truncationNote(_ walked: Walked) -> String? {
        guard walked.truncated else { return nil }
        if let after = walked.throttledAfter {
            return "Shopify rate limited the request after \(after) orders, "
                + "so this is an undercount."
        }
        return "Only the \(maxPages * pageSize) most recent orders in the window were read, "
            + "so this is an undercount."
    }

    /// The store's currency against the user's preference.
    ///
    /// Said once, in the note, rather than hidden: a tile labelled in EUR
    /// next to one labelled in USD is confusing only until somebody explains
    /// why.
    static func currencyNote(_ currency: String, preferred: String) -> String? {
        guard currency.uppercased() != preferred.uppercased() else { return nil }
        return "Totals are in the store's own currency, \(currency.uppercased()), "
            + "not \(preferred.uppercased())."
    }

    // MARK: - Dates

    /// One of Shopify's timestamps.
    ///
    /// `ISO8601.parse` covers what the Admin API actually sends — UTC with a
    /// `Z` — and the fallbacks cover the offset form a store's own export
    /// tooling produces, because a date this cannot read drops the order out
    /// of the window entirely rather than merely misplacing it by an hour.
    static func instant(_ raw: String) -> Date? {
        if let date = ISO8601.parse(raw) { return date }

        let formatter = DateFormatter()
        // POSIX, or a user on a non-Gregorian calendar parses a Buddhist year
        // out of a perfectly good timestamp.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd",
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}

/// Shopify's wire shapes, nested under the adapter that reads them.
///
/// Nested rather than at file scope because `Order`, `Customer` and
/// `Transaction` are names every payments provider in this module wants. At
/// the top level the second one to be written fails to compile, and the error
/// names a file its author never touched.
///
/// No `CodingKeys` anywhere below: a GraphQL answer carries exactly the field
/// names the query asked for, and the query asks in camel case.
extension ShopifyProvider {
    struct MoneyBag: Decodable {
        let shopMoney: Money?

        struct Money: Decodable {
            /// A decimal string, in major units. Parsed once, in `money(_:)`.
            let amount: String
            let currencyCode: String
        }
    }

    struct Order: Decodable {
        let id: String
        let name: String?
        let createdAt: String
        /// A test-mode order through Shopify's own gateway. Optional because a
        /// future Shopify version is free to drop it, and a missing flag must
        /// not silently exclude every real order.
        let test: Bool?
        let displayFinancialStatus: String?
        let totalPriceSet: MoneyBag?
        let totalRefundedSet: MoneyBag?
        let customer: Customer?
        let lineItems: LineItems?

        struct Customer: Decodable {
            let displayName: String?
            let email: String?
        }

        struct LineItems: Decodable {
            let nodes: [LineItem]

            struct LineItem: Decodable {
                let title: String?
            }
        }
    }

    struct PageInfo: Decodable {
        let hasNextPage: Bool
        let endCursor: String?
    }

    struct OrdersPage: Decodable {
        let orders: Connection

        struct Connection: Decodable {
            let nodes: [Order]
            let pageInfo: PageInfo
        }
    }

    struct RecentOrders: Decodable {
        let orders: Connection

        struct Connection: Decodable {
            let nodes: [Order]
        }
    }

    struct Customer: Decodable {
        let id: String?
        let createdAt: String
    }

    struct CustomersPage: Decodable {
        let customers: Connection

        struct Connection: Decodable {
            let nodes: [Customer]
            let pageInfo: PageInfo
        }
    }

    struct CustomersTotal: Decodable {
        let customersCount: Count?

        struct Count: Decodable {
            let count: Int?
            /// `EXACT`, or `AT_LEAST` above ten thousand.
            let precision: String?
        }
    }
}
