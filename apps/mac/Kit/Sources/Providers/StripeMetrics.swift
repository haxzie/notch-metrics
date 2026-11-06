import Foundation
import MetricsCore

/// Stripe's metrics, read on this Mac.
///
/// Ported from `packages/integrations/src/providers/stripe/index.ts`. The
/// arithmetic is deliberately the same arithmetic, down to which transactions
/// are excluded and how a weekly price becomes a monthly one — a widget must
/// not change its number because the fetch moved off the Worker.
extension StripeProvider {
    /// Pages Stripe walks before giving up.
    ///
    /// The same cap the Worker uses. An account with tens of thousands of
    /// subscriptions cannot have its MRR computed by walking the list API, and
    /// the cap turns "this hung and then failed" into an error that says what
    /// is wrong and what the answer is.
    static let maxPages = 20
    static let pageSize = 100

    public func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let key = try requiredCredential(credentials, "secret_key")

        switch window.metric {
        case "revenue":
            return try await balanceSeries(key: key, window: window, http: http, type: "charge", sign: 1)
        case "refunds":
            return try await balanceSeries(key: key, window: window, http: http, type: "refund", sign: -1)
        case "mrr":
            return try await mrr(key: key, window: window, http: http)
        case "active_subscribers":
            return try await activeSubscribers(key: key, http: http)
        case "new_subscribers":
            return try await subscriptionCounts(key: key, window: window, http: http, field: .created)
        case "churned_subscribers":
            return try await subscriptionCounts(
                key: key, window: window, http: http, field: .canceled)
        default:
            // Not a bug: the catalogue is the Worker's and lists metrics this
            // build has not been taught yet. The caller falls back to the API.
            throw ProviderFailure.unsupported("This build cannot read Stripe's \(window.metric) yet.")
        }
    }

    // MARK: - Metrics

    /// Gross charges, or refunds, bucketed over the window.
    ///
    /// Balance transactions rather than charges: a charge that failed or was
    /// disputed never reaches the balance, and counting it would report money
    /// that is not there.
    private func balanceSeries(
        key: String, window: MetricWindow, http: ProviderHTTP,
        type: String, sign: Double
    ) async throws -> MetricValue {
        let page = try await walk(
            BalanceTransaction.self, "/balance_transactions", key: key, http: http,
            params: [
                "type": type,
                "created[gte]": String(Int(window.from.timeIntervalSince1970)),
                "created[lte]": String(Int(window.to.timeIntervalSince1970)),
            ])
        if page.truncated { throw Self.tooLarge }

        // Dropped rather than converted. There is no rate to convert at, and
        // a total that silently added euros to dollars is worse than one that
        // says what it left out.
        let wanted = window.preferredCurrency.lowercased()
        let kept = page.items.filter { $0.currency.lowercased() == wanted }
        let excluded = page.items.count - kept.count

        let points = bucketSum(
            kept.map { (at: Date(timeIntervalSince1970: TimeInterval($0.created)),
                        amount: Double($0.amount) * sign) },
            from: window.from, to: window.to,
            granularity: window.granularity, timeZone: window.timeZone)

        return MetricValue(
            value: points.reduce(0) { $0 + $1.v },
            points: window.wantSeries ? points : [],
            currency: window.preferredCurrency,
            note: excluded > 0
                ? "\(excluded) transaction\(excluded == 1 ? "" : "s") in another currency "
                    + "\(excluded == 1 ? "was" : "were") excluded."
                : nil)
    }

    /// Active subscriptions, each item normalised to a monthly amount.
    ///
    /// A snapshot of the book right now, not a sum over the window — which is
    /// what the methodology string on the manifest promises, and why the
    /// window is used only to timestamp the answer.
    private func mrr(
        key: String, window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let page = try await walk(
            Subscription.self, "/subscriptions", key: key, http: http,
            params: ["status": "active", "expand[]": "data.items.data.price"])
        if page.truncated { throw Self.tooLarge }

        let wanted = window.preferredCurrency.lowercased()
        var total: Double = 0
        var excluded = 0

        for subscription in page.items {
            let discount = subscription.discounts?.first?.coupon?.percentOff ?? 0
            for item in subscription.items.data {
                guard let price = item.price, let recurring = price.recurring,
                      let unitAmount = price.unitAmount
                else { continue }
                guard price.currency.lowercased() == wanted else {
                    excluded += 1
                    continue
                }
                let gross = Double(unitAmount) * Double(item.quantity ?? 1)
                let monthly = toMonthly(
                    gross, interval: recurring.interval, intervalCount: recurring.intervalCount ?? 1)
                total += monthly * (1 - discount / 100)
            }
        }

        return MetricValue(
            // Rounded to whole minor units. Money is an integer here and
            // everywhere else; a fractional cent on the headline figure is a
            // rendering bug waiting to happen.
            value: total.rounded(),
            currency: window.preferredCurrency,
            note: excluded > 0
                ? "\(excluded) subscription item\(excluded == 1 ? "" : "s") in another currency "
                    + "\(excluded == 1 ? "was" : "were") excluded."
                : nil)
    }

    /// Which timestamp on a subscription a count is bucketed by.
    enum SubscriptionDate {
        case created, canceled
    }

    /// Subscriptions started, or cancelled, in the window.
    ///
    /// Stripe can filter by `created` but **not** by `canceled_at`, so churn
    /// has to pull every cancelled subscription the account has ever had and
    /// bucket them here. That asymmetry is the whole reason this takes a
    /// `field` rather than being two near-identical functions — and it is why
    /// churn is the metric most likely to hit the page cap on an old account.
    private func subscriptionCounts(
        key: String, window: MetricWindow, http: ProviderHTTP, field: SubscriptionDate
    ) async throws -> MetricValue {
        let from = Int(window.from.timeIntervalSince1970)
        let to = Int(window.to.timeIntervalSince1970)
        // Widened only when a delta is wanted, so a tile without one does not
        // pay for pages it will never show.
        let earliest = window.comparePrevious
            ? Int(window.from.addingTimeInterval(-window.to.timeIntervalSince(window.from))
                .timeIntervalSince1970)
            : from

        let params: [String: String] =
            field == .created
            ? ["status": "all", "created[gte]": String(earliest), "created[lte]": String(to)]
            : ["status": "canceled"]

        let page = try await walk(
            Subscription.self, "/subscriptions", key: key, http: http, params: params)
        if page.truncated { throw Self.tooLarge }

        let stamps = page.items.compactMap { subscription -> Int? in
            field == .created ? subscription.created : subscription.canceledAt
        }

        // Summed from the events, never from the buckets: a window edge is an
        // instant and a bucket is a whole day, so a headline taken off the
        // buckets would pull the preceding period's subscriptions into the
        // figure on screen.
        let current = stamps.filter { $0 >= from && $0 <= to }
        let earlier = stamps.filter { $0 >= earliest && $0 < from }

        let points = bucketSum(
            current.map {
                (at: Date(timeIntervalSince1970: TimeInterval($0)), amount: 1.0)
            },
            from: window.from, to: window.to,
            granularity: window.granularity, timeZone: window.timeZone)

        return MetricValue(
            value: Double(current.count),
            // Nil rather than zero when no comparison was asked for. Zero
            // would let a tile draw "down 100%" against a window this fetch
            // never looked at.
            previousValue: window.comparePrevious ? Double(earlier.count) : nil,
            points: window.wantSeries ? points : [])
    }

    private func activeSubscribers(key: String, http: ProviderHTTP) async throws -> MetricValue {
        let page = try await walk(
            Subscription.self, "/subscriptions", key: key, http: http,
            params: ["status": "active"])
        if page.truncated { throw Self.tooLarge }
        return MetricValue(value: Double(page.items.count))
    }

    static var tooLarge: ProviderFailure {
        .unsupported(
            "This Stripe account has more subscriptions than can be counted here. "
                + "Stripe Sigma is the way to report on an account this size.")
    }

    // MARK: - Paging

    private struct Page<T> {
        let items: [T]
        /// True when the cap was hit with more still to come, so the caller
        /// reports a number it cannot stand behind rather than a wrong one.
        let truncated: Bool
    }

    private struct StripeList<T: Decodable>: Decodable {
        let data: [T]
        let hasMore: Bool

        enum CodingKeys: String, CodingKey {
            case data
            case hasMore = "has_more"
        }
    }

    private func walk<T: Decodable & StripeObject>(
        _ type: T.Type, _ path: String, key: String, http: ProviderHTTP,
        params: [String: String]
    ) async throws -> Page<T> {
        var items: [T] = []
        var startingAfter: String?

        for _ in 0..<Self.maxPages {
            var query = params
            query["limit"] = String(Self.pageSize)
            if let startingAfter { query["starting_after"] = startingAfter }

            let body = try await get(StripeList<T>.self, path, key: key, http: http, params: query)
            items.append(contentsOf: body.data)
            if !body.hasMore { return Page(items: items, truncated: false) }
            // An empty page with `has_more` set would otherwise loop forever
            // on the same cursor.
            guard let last = body.data.last else { return Page(items: items, truncated: false) }
            startingAfter = last.id
        }

        return Page(items: items, truncated: true)
    }

    private func get<T: Decodable>(
        _ type: T.Type, _ path: String, key: String, http: ProviderHTTP,
        params: [String: String]
    ) async throws -> T {
        var components = URLComponents(string: "https://api.stripe.com/v1" + path)
        // Sorted, so a request is reproducible in a log and in a test.
        components?.queryItems = params.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url?.absoluteString else {
            throw ProviderFailure.badResponse("Could not build a Stripe URL for \(path).")
        }

        let response = try await http.get(
            url,
            headers: [
                "authorization": "Bearer \(key)",
                "stripe-version": "2024-06-20",
            ])
        guard response.ok else { throw Self.failure(for: response) }
        return try response.json(type)
    }
}

/// Everything Stripe returns carries an id, and the walk pages on it.
public protocol StripeObject {
    var id: String { get }
}

/// Stripe's wire shapes, nested under the adapter that reads them.
///
/// Nested rather than at file scope because `Subscription`, `Charge` and
/// `BalanceTransaction` are names every payments provider in this module
/// wants. At the top level the second one to be written fails to compile,
/// and the error names a file its author never touched.
extension StripeProvider {
    struct BalanceTransaction: Decodable, StripeObject {
        let id: String
        /// Minor units, as Stripe sends them. Never divided by 100 here:
        /// money stays an integer all the way to the formatter.
        let amount: Int
        let currency: String
        /// Unix seconds.
        let created: Int
    }

    struct Subscription: Decodable, StripeObject {
        let id: String
        let items: Items
        let discounts: [Discount]?
        /// Unix seconds. Absent on the subscription list unless it is in a
        /// terminal state, which is why churn asks for `status: canceled`.
        let created: Int?
        let canceledAt: Int?

        struct Items: Decodable {
            let data: [Item]
        }

        struct Item: Decodable {
            let price: Price?
            let quantity: Int?
        }

        struct Price: Decodable {
            let currency: String
            let unitAmount: Int?
            let recurring: Recurring?

            enum CodingKeys: String, CodingKey {
                case currency
                case unitAmount = "unit_amount"
                case recurring
            }
        }

        struct Recurring: Decodable {
            let interval: String
            let intervalCount: Int?

            enum CodingKeys: String, CodingKey {
                case interval
                case intervalCount = "interval_count"
            }
        }

        struct Discount: Decodable {
            let coupon: Coupon?
        }

        struct Coupon: Decodable {
            let percentOff: Double?

            enum CodingKeys: String, CodingKey {
                case percentOff = "percent_off"
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, items, discounts, created
            case canceledAt = "canceled_at"
        }
    }
}
