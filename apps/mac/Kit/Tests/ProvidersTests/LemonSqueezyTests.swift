import Foundation
import MetricsCore
import Testing

@testable import Providers

/// Lemon Squeezy's statuses, in the buckets the caller acts differently on.
@Suite("lemon squeezy failures")
struct LemonSqueezyFailureTests {
    private func response(_ status: Int, body: String = "", headers: [String: String] = [:])
        -> ProviderHTTP.Response
    {
        ProviderHTTP.Response(status: status, headers: headers, body: Data(body.utf8))
    }

    /// JSON:API puts the explanation in `errors[].detail`, which is not where
    /// Stripe puts it — so this pins that the right reader is wired up.
    @Test("a rejected key is an auth failure, and carries the API's own words")
    func badKey() {
        let failure = LemonSqueezyProvider.failure(
            for: response(401, body: #"{"errors":[{"detail":"Unauthenticated."}]}"#))
        #expect(failure == .authFailed("Unauthenticated."))
    }

    /// The one worth being deliberate about. A store on somebody else's
    /// account, or a deleted price, is a statement about one resource; calling
    /// it an auth failure would mark the connection broken and ask the user to
    /// replace a key that works.
    @Test("a forbidden or missing resource is unsupported, not an auth failure")
    func oneResource() {
        for status in [403, 404] {
            #expect(
                LemonSqueezyProvider.failure(for: response(status))
                    == .unsupported("That key may not read this part of the store."))
        }
    }

    @Test("a spent quota carries the wait the API asked for")
    func rateLimited() {
        let failure = LemonSqueezyProvider.failure(for: response(429, headers: ["Retry-After": "45"]))
        #expect(failure == .rateLimited("Lemon Squeezy's rate limit is spent.", retryAfter: 45))
    }

    @Test("a 5xx is their outage, retried rather than reported as a bad key")
    func down() {
        #expect(
            LemonSqueezyProvider.failure(for: response(502))
                == .providerDown("Lemon Squeezy is having trouble."))
    }

    /// 406 is what a missing `Accept: application/vnd.api+json` looks like,
    /// and it reads as a routing problem unless the body survives.
    @Test("any other 4xx keeps the explanation the API sent")
    func explained() {
        let failure = LemonSqueezyProvider.failure(
            for: response(406, body: #"{"message":"Not Acceptable"}"#))
        #expect(failure == .badResponse("Not Acceptable"))
    }

    @Test("and says the status when it sent none")
    func unexplained() {
        #expect(
            LemonSqueezyProvider.failure(for: response(418))
                == .badResponse("Lemon Squeezy returned 418."))
    }
}

@Suite("lemon squeezy credentials")
struct LemonSqueezyCredentialTests {
    @Test("a missing api key is refused before any request is made")
    func missing() {
        #expect(throws: ProviderFailure.self) {
            _ = try LemonSqueezyProvider.Credentials([:])
        }
    }

    /// An empty text field arrives as `""`, which is not a store id and is not
    /// the same as "every store". Left unnormalised it becomes
    /// `filter[store_id]=` on every request.
    @Test("an empty store id means every store, not store zero")
    func emptyStore() throws {
        let creds = try LemonSqueezyProvider.Credentials(["api_key": "lsq_key", "store_id": "  "])
        #expect(creds.storeId == nil)
        #expect(creds.storeFilter.isEmpty)
    }

    @Test("a store id is filtered on")
    func pinnedStore() throws {
        let creds = try LemonSqueezyProvider.Credentials(["api_key": "lsq_key", "store_id": "41"])
        #expect(creds.storeFilter == ["filter[store_id]": "41"])
    }
}

@Suite("lemon squeezy notes")
struct LemonSqueezyNoteTests {
    private func order(_ currency: String) -> LemonSqueezyProvider.Resource<
        LemonSqueezyProvider.OrderAttributes
    > {
        LemonSqueezyFixtures.order(id: "1", currency: currency, total: 100, status: "paid")
    }

    /// Summing mixed currencies at 1:1 is the kind of wrong that looks right,
    /// so the rows are dropped and the codes are named.
    @Test("rows in another currency are excluded and named")
    func excluded() {
        let split = LemonSqueezyProvider.splitByCurrency(
            [order("USD"), order("EUR"), order("gbp"), order("EUR")], preferred: "usd")
        #expect(split.kept.count == 1)
        #expect(split.note == "EUR and GBP excluded; totals are USD only.")
    }

    @Test("a single-currency book says nothing")
    func nothingToSay() {
        let split = LemonSqueezyProvider.splitByCurrency([order("USD"), order("usd")], preferred: "USD")
        #expect(split.kept.count == 2)
        #expect(split.note == nil)
    }

    @Test("the truncation note names the cap it hit")
    func truncation() {
        #expect(LemonSqueezyProvider.truncationNote(false) == nil)
        #expect(
            LemonSqueezyProvider.truncationNote(true)
                == "Only the first 2000 records were read, so this is an undercount.")
    }

    @Test("two notes become one sentence pair, and no notes becomes nil")
    func joined() {
        #expect(LemonSqueezyProvider.join("One.", nil, "Two.") == "One. Two.")
        #expect(LemonSqueezyProvider.join(nil, nil) == nil)
    }

    /// Lemon Squeezy sends microseconds on an order and whole seconds
    /// elsewhere. A timestamp this adapter cannot read drops the row from
    /// every window, which is a silent undercount rather than an error.
    @Test("both timestamp shapes parse")
    func timestamps() {
        #expect(LemonSqueezyProvider.instant("2026-02-05T14:22:13.000000Z") != nil)
        #expect(LemonSqueezyProvider.instant("2026-02-05T14:22:13Z") != nil)
        #expect(LemonSqueezyProvider.instant("not a date") == nil)
    }
}

/// Serialized, because the stub below answers through a `URLProtocol` and a
/// `URLProtocol` subclass is registered on a session configuration by type —
/// so its instance state is static, and two of these running at once would
/// read each other's pages.
@Suite("lemon squeezy metrics", .serialized)
struct LemonSqueezyMetricTests {
    private let provider = LemonSqueezyProvider()
    private let credentials = ["api_key": "lsq_test_key"]

    private func window(
        _ metric: String, from: String = "2026-02-01T00:00:00Z", to: String = "2026-02-04T00:00:00Z",
        wantSeries: Bool = true, comparePrevious: Bool = false, currency: String = "USD"
    ) -> MetricWindow {
        MetricWindow(
            metric: metric,
            from: LemonSqueezyFixtures.date(from), to: LemonSqueezyFixtures.date(to),
            granularity: .day, wantSeries: wantSeries, comparePrevious: comparePrevious,
            timeZone: TimeZone(identifier: "UTC")!, preferredCurrency: currency)
    }

    /// Gross, by `total`: a later refund does not remove the order from the
    /// day it was paid, which is what the methodology promises.
    @Test("revenue buckets paid orders by day and leaves the unpaid out")
    func revenue() async throws {
        let stub = LemonSqueezyStub([
            "/v1/orders": [
                LemonSqueezyFixtures.orderPage([
                    (id: "1", at: "2026-02-03T10:00:00.000000Z", total: 2500, status: "paid",
                     currency: "USD", refunded: 0),
                    (id: "2", at: "2026-02-03T18:00:00.000000Z", total: 1500, status: "refunded",
                     currency: "USD", refunded: 1500),
                    (id: "3", at: "2026-02-02T09:00:00.000000Z", total: 999, status: "pending",
                     currency: "USD", refunded: 0),
                    (id: "4", at: "2026-02-01T09:00:00.000000Z", total: 700, status: "paid",
                     currency: "EUR", refunded: 0),
                    // Before the window, and before the window before it: the
                    // walk stops here rather than reading the store's history.
                    (id: "5", at: "2025-11-01T09:00:00.000000Z", total: 4000, status: "paid",
                     currency: "USD", refunded: 0),
                ])
            ]
        ])

        let value = try await provider.fetch(
            credentials, window: window("revenue"), http: stub.http)

        #expect(value.value == 4000)
        #expect(value.currency == "USD")
        #expect(value.points.count == 4)
        #expect(value.points[2].v == 4000)
        #expect(value.points[0].v == 0)
        #expect(value.note == "EUR excluded; totals are USD only.")
        // One page, and the walk stopped at the old order rather than asking
        // for a second.
        #expect(stub.calls.count == 1)
    }

    /// `refunded_amount` on the same orders, bucketed by the order's own date
    /// because the API does not say when the refund happened.
    @Test("refunds read refunded_amount, not the total")
    func refunds() async throws {
        let stub = LemonSqueezyStub([
            "/v1/orders": [
                LemonSqueezyFixtures.orderPage([
                    (id: "1", at: "2026-02-03T10:00:00.000000Z", total: 2500, status: "paid",
                     currency: "USD", refunded: 0),
                    (id: "2", at: "2026-02-02T18:00:00.000000Z", total: 1500, status: "refunded",
                     currency: "USD", refunded: 1500),
                    (id: "3", at: "2026-02-02T19:00:00.000000Z", total: 900, status: "partial_refund",
                     currency: "USD", refunded: 400),
                ])
            ]
        ])

        let value = try await provider.fetch(credentials, window: window("refunds"), http: stub.http)

        #expect(value.value == 1900)
        #expect(value.points[1].v == 1900)
        #expect(value.points[2].v == 0)
    }

    /// A tile with no chart still gets the headline, and the points it would
    /// not draw are not sent.
    @Test("a tile that wants no series gets none")
    func noSeries() async throws {
        let stub = LemonSqueezyStub([
            "/v1/orders": [
                LemonSqueezyFixtures.orderPage([
                    (id: "1", at: "2026-02-03T10:00:00.000000Z", total: 2500, status: "paid",
                     currency: "USD", refunded: 0)
                ])
            ]
        ])

        let value = try await provider.fetch(
            credentials, window: window("revenue", wantSeries: false), http: stub.http)
        #expect(value.value == 2500)
        #expect(value.points.isEmpty)
    }

    /// Orders older than the window count towards the previous one, which is
    /// what the compare chip reads.
    @Test("the window before the window is totalled separately when asked")
    func previous() async throws {
        let stub = LemonSqueezyStub(["/v1/orders": [Self.straddlingPage]])

        let value = try await provider.fetch(
            credentials, window: window("revenue", comparePrevious: true), http: stub.http)
        #expect(value.value == 2000)
        #expect(value.previousValue == 500)
        // The earlier order is outside every bucket the chart draws, so the
        // comparison does not leak into the series.
        #expect(value.points.reduce(0) { $0 + $1.v } == 2000)
    }

    /// The flag is the whole point: an order before the window is not read at
    /// all, so a tile with no delta on it does not pay for the pages. Nil
    /// rather than zero, because a tile reading `previousValue` would
    /// otherwise draw "down 100%" against a window nothing looked at.
    @Test("with no comparison asked for, the earlier window is never read")
    func noComparison() async throws {
        let stub = LemonSqueezyStub(["/v1/orders": [Self.straddlingPage]])

        let value = try await provider.fetch(credentials, window: window("revenue"), http: stub.http)
        #expect(value.value == 2000)
        #expect(value.previousValue == nil)
        #expect(value.points.reduce(0) { $0 + $1.v } == 2000)
    }

    /// One order inside the window and one in the window before it.
    private static let straddlingPage = LemonSqueezyFixtures.orderPage([
        (id: "1", at: "2026-02-03T10:00:00.000000Z", total: 2000, status: "paid",
         currency: "USD", refunded: 0),
        (id: "2", at: "2026-01-30T10:00:00.000000Z", total: 500, status: "paid",
         currency: "USD", refunded: 0),
    ])

    /// The arithmetic worth pinning: a yearly price is a twelfth, quantity
    /// multiplies, and the rounding happens once at the end.
    @Test("mrr normalises each price to a month and prices are fetched once each")
    func mrr() async throws {
        let stub = LemonSqueezyStub([
            "/v1/subscriptions": [
                LemonSqueezyFixtures.subscriptionPage([
                    (id: "s1", priceId: 10, quantity: 1),
                    (id: "s2", priceId: 10, quantity: 3),
                    (id: "s3", priceId: 11, quantity: 1),
                    // No recurring price: a one-off sold as a subscription
                    // item. Named in the note rather than counted as zero.
                    (id: "s4", priceId: 12, quantity: 1),
                ])
            ],
            "/v1/prices/10": [
                LemonSqueezyFixtures.price(unitPrice: 1000, category: "subscription", unit: "month")
            ],
            "/v1/prices/11": [
                LemonSqueezyFixtures.price(unitPrice: 12_000, category: "subscription", unit: "year")
            ],
            "/v1/prices/12": [
                LemonSqueezyFixtures.price(unitPrice: 5000, category: "one_time", unit: nil)
            ],
        ])

        let value = try await provider.fetch(credentials, window: window("mrr"), http: stub.http)

        // 1000 + 3000 + 12000/12.
        #expect(value.value == 5000)
        #expect(value.currency == "USD")
        #expect(value.note == "1 subscription was excluded for having no recurring price.")
        // Three prices for four subscriptions: the ids are deduplicated before
        // anything is fetched, which is what keeps a 800-subscriber store from
        // making 800 requests.
        #expect(stub.calls.filter { $0.contains("/prices/") }.count == 3)
    }

    @Test("active subscribers counts the rows the active filter returned")
    func activeSubscribers() async throws {
        let stub = LemonSqueezyStub([
            "/v1/subscriptions": [
                LemonSqueezyFixtures.subscriptionPage([
                    (id: "s1", priceId: 10, quantity: 1),
                    (id: "s2", priceId: 10, quantity: 1),
                ])
            ]
        ])

        let value = try await provider.fetch(
            credentials, window: window("active_subscribers"), http: stub.http)
        #expect(value.value == 2)
        #expect(value.note == nil)
        #expect(stub.calls[0].contains("filter%5Bstatus%5D=active")
            || stub.calls[0].contains("filter[status]=active"))
    }

    /// The list shape, which nothing else exercises yet: sorted newest first,
    /// capped at ten, and a headline that is the rows in the user's currency
    /// rather than the row count.
    @Test("recent payments returns rows newest first, capped, totalled in one currency")
    func recentPayments() async throws {
        var rows: [(id: String, at: String, total: Int, status: String, currency: String, refunded: Int)] = []
        // Oldest first on the wire, so a feed that forgot to sort would fail.
        for index in 1...12 {
            rows.append(
                (id: "o\(index)", at: String(format: "2026-02-0%dT0%d:00:00.000000Z", 1 + index / 10, index % 10),
                 total: index * 100, status: "paid", currency: "USD", refunded: 0))
        }
        rows.append(
            (id: "eur", at: "2026-02-04T23:00:00.000000Z", total: 9999, status: "paid",
             currency: "EUR", refunded: 0))
        rows.append(
            (id: "failed", at: "2026-02-04T23:30:00.000000Z", total: 5000, status: "failed",
             currency: "USD", refunded: 0))

        let stub = LemonSqueezyStub(["/v1/orders": [LemonSqueezyFixtures.orderPage(rows)]])

        let value = try await provider.fetch(
            credentials, window: window("recent_payments"), http: stub.http)

        let items = try #require(value.items)
        #expect(items.count == 10)
        // The euro order is the newest paid one, so it leads the feed — listed
        // with its own code rather than dropped, because a list can show a
        // currency where a sum cannot.
        #expect(items[0].id == "eur")
        #expect(items[0].currency == "EUR")
        #expect(!items.contains { $0.id == "failed" })
        // Newest first, all the way down.
        let instants = items.compactMap { ISO8601.parse($0.t) }
        #expect(instants.count == 10)
        #expect(instants == instants.sorted(by: >))

        // The nine dollar rows that made the cap, and not the euro one.
        let dollars = items.filter { $0.currency == "USD" }.compactMap(\.amount).reduce(0, +)
        #expect(value.value == dollars)
        #expect(value.value > 0)
        #expect(value.currency == "USD")

        let row = try #require(items.first { $0.id == "o12" })
        #expect(row.label == "Ada Lovelace")
        #expect(row.detail == "Pro · Monthly")
        #expect(row.status == "paid")
        // A payment is not pass or fail, so there is no state to draw.
        #expect(row.state == nil)
        // One page, asking for twice the limit because the paid filter runs
        // on this side.
        #expect(stub.calls.count == 1)
        #expect(stub.calls[0].contains("20"))
    }

    /// The cap is the Worker's cap, and hitting it says so rather than
    /// reporting a short number as a whole one.
    @Test("hitting the page cap is reported as an undercount")
    func truncated() async throws {
        let full = LemonSqueezyFixtures.subscriptionPage(
            (1...100).map { (id: "s\($0)", priceId: 10, quantity: 1) })
        let stub = LemonSqueezyStub(["/v1/subscriptions": Array(repeating: full, count: 25)])

        let value = try await provider.fetch(
            credentials, window: window("active_subscribers"), http: stub.http)

        #expect(value.value == 2000)
        #expect(value.note == "Only the first 2000 records were read, so this is an undercount.")
        #expect(stub.calls.count == LemonSqueezyProvider.maxPages)
    }

    /// `lastPage` ends the walk even when the page was full, which is the
    /// case a short-page check alone would read as "keep going".
    @Test("lastPage ends the walk without a short page")
    func lastPage() async throws {
        let page = LemonSqueezyFixtures.subscriptionPage(
            (1...100).map { (id: "s\($0)", priceId: 10, quantity: 1) }, lastPage: 1)
        let stub = LemonSqueezyStub(["/v1/subscriptions": [page, page]])

        let value = try await provider.fetch(
            credentials, window: window("active_subscribers"), http: stub.http)
        #expect(value.value == 100)
        #expect(stub.calls.count == 1)
    }

    @Test("verify names the store and takes its currency")
    func verify() async throws {
        let stub = LemonSqueezyStub([
            "/v1/users/me": [#"{"data":{"id":"7","attributes":{"name":"Ada","email":"a@b.c"}}}"#],
            "/v1/stores": [
                #"{"data":[{"id":"41","attributes":{"name":"Lemonade","currency":"gbp"}}]}"#
            ],
        ])

        let account = try await LemonSqueezyProvider().verify(
            ["api_key": "lsq_test_key", "store_id": "41"], http: stub.http)

        #expect(account.label == "Lemonade")
        #expect(account.currency == "GBP")
        #expect(account.unavailableMetrics.isEmpty)
    }

    /// Otherwise this fails later as an empty dashboard rather than a rejected
    /// connection — and as `unsupported`, because the key itself is fine.
    @Test("a store this key cannot see is refused at verify")
    func wrongStore() async {
        let stub = LemonSqueezyStub([
            "/v1/users/me": [#"{"data":{"id":"7","attributes":{"name":"Ada"}}}"#],
            "/v1/stores": [#"{"data":[{"id":"41","attributes":{"name":"Lemonade","currency":"USD"}}]}"#],
        ])

        do {
            _ = try await LemonSqueezyProvider().verify(
                ["api_key": "lsq_test_key", "store_id": "99"], http: stub.http)
            Issue.record("a store on another account was accepted")
        } catch let failure as ProviderFailure {
            #expect(failure == .unsupported("This API key cannot see store 99."))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    /// With no store pinned, the account's own name labels the connection.
    @Test("no store id labels the connection with the account")
    func wholeAccount() async throws {
        let stub = LemonSqueezyStub([
            "/v1/users/me": [#"{"data":{"id":"7","attributes":{"email":"ada@example.com"}}}"#],
            "/v1/stores": [#"{"data":[{"id":"41","attributes":{"currency":"eur"}}]}"#],
        ])

        let account = try await LemonSqueezyProvider().verify(
            ["api_key": "lsq_test_key"], http: stub.http)
        #expect(account.label == "ada@example.com")
        #expect(account.currency == "EUR")
    }

    @Test("a metric this build does not know is unsupported, not a crash")
    func unknownMetric() async {
        let stub = LemonSqueezyStub([:])
        do {
            _ = try await provider.fetch(credentials, window: window("churn"), http: stub.http)
            Issue.record("an unknown metric was answered")
        } catch let failure as ProviderFailure {
            #expect(failure == .unsupported("This build cannot read Lemon Squeezy's churn yet."))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}

// MARK: - Fixtures

/// The JSON:API bodies these tests are written against.
///
/// Hand-written rather than recorded: what matters is the envelope shape —
/// `data` / `attributes` / `meta.page` — and a recorded body would bring four
/// hundred lines of fields nothing here reads.
enum LemonSqueezyFixtures {
    static func date(_ iso: String) -> Date {
        ISO8601.parse(iso)!
    }

    static func order(
        id: String, currency: String, total: Int, status: String
    ) -> LemonSqueezyProvider.Resource<LemonSqueezyProvider.OrderAttributes> {
        let json = """
            {"id":"\(id)","attributes":{"store_id":41,"currency":"\(currency)","total":\(total),
            "status":"\(status)","refunded":false,"refunded_amount":0,
            "created_at":"2026-02-03T10:00:00.000000Z"}}
            """
        return try! JSONDecoder().decode(
            LemonSqueezyProvider.Resource<LemonSqueezyProvider.OrderAttributes>.self,
            from: Data(json.utf8))
    }

    static func orderPage(
        _ rows: [(id: String, at: String, total: Int, status: String, currency: String, refunded: Int)]
    ) -> String {
        let data = rows.map { row in
            """
            {"id":"\(row.id)","attributes":{"store_id":41,"currency":"\(row.currency)",
            "total":\(row.total),"status":"\(row.status)","refunded":\(row.refunded > 0),
            "refunded_amount":\(row.refunded),"created_at":"\(row.at)",
            "user_name":"Ada Lovelace","user_email":"ada@example.com",
            "first_order_item":{"product_name":"Pro","variant_name":"Monthly"}}}
            """
        }
        .joined(separator: ",")
        return #"{"data":[\#(data)]}"#
    }

    static func subscriptionPage(
        _ rows: [(id: String, priceId: Int, quantity: Int)], lastPage: Int? = nil
    ) -> String {
        let data = rows.map { row in
            """
            {"id":"\(row.id)","attributes":{"store_id":41,"status":"active",
            "created_at":"2026-01-01T00:00:00.000000Z",
            "first_subscription_item":{"price_id":\(row.priceId),"quantity":\(row.quantity)}}}
            """
        }
        .joined(separator: ",")
        let meta = lastPage.map { #","meta":{"page":{"currentPage":1,"lastPage":\#($0)}}"# } ?? ""
        return #"{"data":[\#(data)]\#(meta)}"#
    }

    static func price(unitPrice: Int, category: String, unit: String?) -> String {
        let renewal = unit.map { #""\#($0)""# } ?? "null"
        return """
            {"data":{"id":"10","attributes":{"unit_price":\(unitPrice),"category":"\(category)",
            "renewal_interval_unit":\(renewal),"renewal_interval_quantity":1}}}
            """
    }
}

/// A `ProviderHTTP` whose answers come from a table of paths.
///
/// Keyed by path rather than by full URL because the query string carries the
/// page number, and a stub that had to be keyed by it would have to know the
/// walk's arithmetic to answer it. Each path holds the bodies in the order
/// they are served, so a paging test is a list of pages.
final class LemonSqueezyStub: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [String: [String]]
    private var served: [String] = []

    /// Built with the adapter's own allowlist, so a request this stub answers
    /// is a request the real client would have been allowed to make.
    let http: ProviderHTTP

    init(_ bodies: [String: [String]]) {
        self.bodies = bodies
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LemonSqueezyStubProtocol.self]
        http = ProviderHTTP(
            allowedHosts: LemonSqueezyProvider().allowedHosts,
            session: URLSession(configuration: configuration))
        LemonSqueezyStubProtocol.register(self)
    }

    /// Every URL that was asked for, in order.
    var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return served
    }

    /// The body for one request, and the status it is served with.
    fileprivate func answer(for url: URL) -> (Int, Data) {
        lock.lock()
        defer { lock.unlock() }
        served.append(url.absoluteString)

        let path = url.path
        guard var queue = bodies[path], !queue.isEmpty else {
            // 404 rather than an empty body: a path this stub was not given is
            // a test asking for something the adapter should not have wanted,
            // and a silent `{}` would hide it.
            return (404, Data(#"{"errors":[{"detail":"no stub for \#(path)"}]}"#.utf8))
        }
        let body = queue.removeFirst()
        // The last page is served again for any further request, so a walk
        // that over-reads shows up as a wrong count rather than a 404.
        if !queue.isEmpty { bodies[path] = queue }
        return (200, Data(body.utf8))
    }
}

/// Answers requests out of whichever stub registered last.
///
/// `URLProtocol` subclasses are registered on a configuration by type, so the
/// instance state has to live somewhere static. One slot rather than a table:
/// these tests build a stub and immediately use it, and a leftover from
/// another suite would answer with the wrong pages.
private final class LemonSqueezyStubProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: LemonSqueezyStub?

    static func register(_ stub: LemonSqueezyStub) {
        lock.lock()
        current = stub
        lock.unlock()
    }

    private static var stub: LemonSqueezyStub? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let stub = Self.stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (status, body) = stub.answer(for: url)
        let response = HTTPURLResponse(
            url: url, statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/vnd.api+json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
