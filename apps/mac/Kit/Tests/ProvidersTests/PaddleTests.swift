import Foundation
import MetricsCore
import Testing

@testable import Providers

// MARK: - A stubbed Paddle

/// Answers whatever the adapter asks for, and records that it asked.
///
/// A `URLProtocol` rather than a fake `ProviderHTTP`, so the allowlist, the
/// manual redirect handling and the byte cap are all still in the path — the
/// host a request actually went to is one of the things these tests pin, and a
/// stub above `ProviderHTTP` could not see it.
final class PaddleStub: URLProtocol {
    struct Reply {
        let status: Int
        let body: String
        var headers: [String: String] = [:]

        static func ok(_ body: String) -> Reply { Reply(status: 200, body: body) }
    }

    nonisolated(unsafe) static var reply: @Sendable (URLRequest) -> Reply = { _ in .ok("{}") }
    nonisolated(unsafe) static var seen: [URLRequest] = []

    /// Every request made since the session was built, oldest first.
    static func requests() -> [URLRequest] { seen }

    static func session(_ reply: @escaping @Sendable (URLRequest) -> Reply) -> URLSession {
        Self.reply = reply
        Self.seen = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PaddleStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen.append(request)
        let reply = Self.reply(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Paddle, pointed at the stub. The allowlist is the adapter's own.
private func paddle(
    _ reply: @escaping @Sendable (URLRequest) -> PaddleStub.Reply
) -> (PaddleProvider, ProviderHTTP) {
    let provider = PaddleProvider()
    return (provider, ProviderHTTP(allowedHosts: provider.allowedHosts, session: PaddleStub.session(reply)))
}

private func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: iso)!
}

private let utc = TimeZone(identifier: "UTC")!

private func window(
    _ metric: String, from: String = "2026-01-01T00:00:00Z", to: String = "2026-01-04T00:00:00Z",
    granularity: Granularity = .day, wantSeries: Bool = true, comparePrevious: Bool = false,
    currency: String = "USD"
) -> MetricWindow {
    MetricWindow(
        metric: metric, from: date(from), to: date(to), granularity: granularity,
        wantSeries: wantSeries, comparePrevious: comparePrevious, timeZone: utc,
        preferredCurrency: currency)
}

private let liveKey = ["api_key": "pdl_live_apikey_0123456789abcdef", "mode": "live"]

// MARK: - Failures

/// Paddle's statuses, in the buckets the caller acts differently on./// Paddle's suites, nested under one serialized parent.
///
/// Not decoration. `PaddleStub` is a `URLProtocol` holding its routes in
/// static state, and Swift Testing runs top-level suites in parallel — so as
/// siblings these eight raced on that one stub, read each other's queued
/// responses, and brought the whole run down with a signal 5. `.serialized`
/// orders a suite *and its children*, which is why the fix is a parent rather
/// than the trait repeated on each of them.
///
/// Every other port using this stub pattern already nests; this file was the
/// one that did not.
@Suite(.serialized)
struct PaddleTests {
@Suite("paddle failures")
struct PaddleFailureTests {
    private func response(_ status: Int, body: String = "", headers: [String: String] = [:])
        -> ProviderHTTP.Response
    {
        ProviderHTTP.Response(status: status, headers: headers, body: Data(body.utf8))
    }

    @Test("a rejected key is an auth failure, and carries Paddle's own words")
    func badKey() {
        let failure = PaddleProvider.failure(
            for: response(
                401,
                body: #"{"error":{"code":"authentication_malformed","detail":"That key is malformed"}}"#),
            host: "api.paddle.com")
        #expect(failure == .authFailed("That key is malformed"))
    }

    /// The one worth being deliberate about, and the one place this port
    /// diverges from the Worker's shared `errorForStatus`, which calls a 403
    /// an auth failure. Paddle's permissions are per entity: a key that may
    /// not read subscriptions is a statement about one list, and marking the
    /// whole connection broken would ask the user to replace a key that works
    /// for revenue.
    @Test("a key without one permission is unsupported, not an auth failure")
    func forbidden() {
        let failure = PaddleProvider.failure(for: response(403), host: "api.paddle.com")
        #expect(failure == .unsupported("That key may not read this part of the account."))
    }

    @Test("the slug is used when Paddle sent no sentence")
    func slugOnly() {
        let failure = PaddleProvider.failure(
            for: response(403, body: #"{"error":{"code":"forbidden"}}"#), host: "api.paddle.com")
        #expect(failure == .unsupported("forbidden"))
    }

    /// A nil wait would mean polling again on the next tick into the same
    /// wall. Sixty is the Worker's fallback.
    @Test("a spent quota carries the wait Paddle asked for, or a minute")
    func rateLimited() {
        #expect(
            PaddleProvider.failure(for: response(429, headers: ["Retry-After": "30"]), host: "h")
                == .rateLimited("h asked us to wait.", retryAfter: 30))
        #expect(
            PaddleProvider.failure(for: response(429), host: "h")
                == .rateLimited("h asked us to wait.", retryAfter: 60))
    }

    @Test("a 5xx is their outage, retried rather than reported as a bad key")
    func down() {
        #expect(
            PaddleProvider.failure(for: response(503), host: "api.paddle.com")
                == .providerDown("api.paddle.com is having trouble."))
    }

    @Test("any other 4xx keeps the explanation Paddle sent, and names the status when it sent none")
    func explained() {
        #expect(
            PaddleProvider.failure(
                for: response(400, body: #"{"error":{"detail":"order_by is not supported"}}"#),
                host: "api.paddle.com") == .badResponse("order_by is not supported"))
        #expect(
            PaddleProvider.failure(for: response(418), host: "api.paddle.com")
                == .badResponse("api.paddle.com returned 418."))
    }
}

// MARK: - Credentials and host

@Suite("paddle credentials")
struct PaddleCredentialTests {
    /// The form will not submit an empty required field, so this is a bug
    /// rather than user error — but an empty bearer token reaches a live API
    /// and reads back as a revoked key.
    @Test("a missing api key is refused before any request is made")
    func missingKey() {
        #expect(throws: ProviderFailure.self) { try PaddleProvider.credentials([:]) }
    }

    /// The manifest's field defaults to live, so a connection stored before
    /// the field existed is a live one.
    @Test("an absent mode is live")
    func defaultMode() throws {
        let creds = try PaddleProvider.credentials(["api_key": "0123456789abcdefghij"])
        #expect(creds.mode == .live)
        #expect(creds.host == "api.paddle.com")
    }

    @Test("sandbox selects the sandbox host")
    func sandboxHost() throws {
        let creds = try PaddleProvider.credentials(
            ["api_key": "0123456789abcdefghij", "mode": "SANDBOX"])
        #expect(creds.host == "sandbox-api.paddle.com")
    }

    /// Guessing live for an unreadable mode sends a sandbox key to the live
    /// host, and Paddle answers that with a 403 the user reads as a revoked
    /// key. Refused instead.
    @Test("an unrecognised mode is refused rather than defaulted")
    func badMode() {
        #expect(throws: ProviderFailure.self) {
            try PaddleProvider.credentials(["api_key": "0123456789abcdefghij", "mode": "stage"])
        }
    }

    /// Both hosts are on the allowlist, so nothing but the stored mode keeps
    /// a sandbox key off the live store.
    @Test("the stored mode decides which allowlisted host is actually used")
    func modePicksHost() async throws {
        let (provider, http) = paddle { _ in .ok(#"{"data":[]}"#) }
        _ = try await provider.fetch(
            ["api_key": "0123456789abcdefghij", "mode": "sandbox"],
            window: window("active_subscribers"), http: http)
        #expect(PaddleStub.requests().allSatisfy { $0.url?.host == "sandbox-api.paddle.com" })
        #expect(!PaddleStub.requests().isEmpty)
    }

    @Test("every request pins the API version and carries the key as a bearer token")
    func headers() async throws {
        let (provider, http) = paddle { _ in .ok(#"{"data":[]}"#) }
        _ = try await provider.fetch(liveKey, window: window("active_subscribers"), http: http)
        let request = try #require(PaddleStub.requests().first)
        #expect(request.value(forHTTPHeaderField: "paddle-version") == "1")
        #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer \(liveKey["api_key"]!)")
    }
}

// MARK: - Amounts and dates

@Suite("paddle amounts")
struct PaddleAmountTests {
    @Test("a minor-unit string is an integer")
    func integers() throws {
        #expect(try PaddleProvider.minor("2499") == 2499)
        #expect(try PaddleProvider.minor("-500") == -500)
        #expect(try PaddleProvider.minor("0") == 0)
    }

    /// A transaction with no totals block is a zero, not a failure. An
    /// amount Paddle printed wrong is a failure, not a zero: parsed
    /// leniently it would become a free sale, which reads as a real number
    /// and is never questioned.
    @Test("an absent amount is zero and a non-integer one is a bad response")
    func malformed() {
        #expect(try! PaddleProvider.minor(nil) == 0)
        for bad in ["12.50", "", "2,499", "1e3", " 24"] {
            #expect(throws: ProviderFailure.self) { try PaddleProvider.minor(bad) }
        }
    }

    @Test("Paddle's time filters take no fractional second")
    func stamp() {
        #expect(PaddleProvider.stamp(date("2026-01-02T03:04:05Z")) == "2026-01-02T03:04:05Z")
    }
}

// MARK: - Metrics

@Suite("paddle revenue")
struct PaddleRevenueTests {
    private func transaction(
        _ id: String, _ billedAt: String, _ total: String, currency: String = "USD"
    ) -> String {
        """
        {"id":"\(id)","status":"completed","currency_code":"\(currency)",
         "billed_at":"\(billedAt)","created_at":"\(billedAt)",
         "details":{"totals":{"total":"\(total)"}}}
        """
    }

    private func page(_ rows: [String]) -> String {
        #"{"data":[\#(rows.joined(separator: ","))],"meta":{"pagination":{"has_more":false}}}"#
    }

    @Test("sums the window's transactions in minor units, never divided by a hundred")
    func sums() async throws {
        let body = page([
            transaction("txn_1", "2026-01-01T10:00:00.123456Z", "1500"),
            transaction("txn_3", "2026-01-03T09:00:00.000000Z", "700"),
        ])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(liveKey, window: window("revenue"), http: http)

        #expect(value.value == 2200)
        #expect(value.currency == "USD")
        #expect(value.note == nil)
    }

    /// Dropped rather than converted. There is no rate to convert at, and a
    /// total that silently added euros to dollars is worse than one that says
    /// what it left out.
    @Test("another currency is excluded and named")
    func otherCurrency() async throws {
        let body = page([
            transaction("txn_1", "2026-01-01T10:00:00.000000Z", "1500"),
            transaction("txn_2", "2026-01-02T10:00:00.000000Z", "2500", currency: "EUR"),
            transaction("txn_3", "2026-01-02T11:00:00.000000Z", "900", currency: "gbp"),
        ])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(liveKey, window: window("revenue"), http: http)

        #expect(value.value == 1500)
        #expect(value.note == "EUR and GBP excluded; totals are USD only.")
    }

    /// A chart that skips a day with no revenue draws a line straight over it
    /// and reads as though the money never stopped.
    @Test("every bucket in the window is drawn, including the empty ones")
    func buckets() async throws {
        let body = page([transaction("txn_1", "2026-01-01T10:00:00.000000Z", "1500")])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(liveKey, window: window("revenue"), http: http)

        #expect(value.points.count == 4)
        #expect(value.points[0].v == 1500)
        #expect(value.points.dropFirst().allSatisfy { $0.v == 0 })
    }

    @Test("a tile with no chart is not handed points nobody draws")
    func noSeries() async throws {
        let body = page([transaction("txn_1", "2026-01-01T10:00:00.000000Z", "1500")])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(
            liveKey, window: window("revenue", wantSeries: false), http: http)

        #expect(value.points.isEmpty)
        #expect(value.value == 1500)
    }

    /// Paddle filters by `billed_at` server-side, which is what keeps this
    /// metric answering for a store the subscription metrics truncate on.
    @Test("the window is pushed into the query rather than filtered here")
    func serverSideWindow() async throws {
        let (provider, http) = paddle { _ in .ok(#"{"data":[]}"#) }
        _ = try await provider.fetch(liveKey, window: window("revenue"), http: http)

        let query = try #require(PaddleStub.requests().first?.url?.query?.removingPercentEncoding)
        #expect(query.contains("billed_at[GTE]=2026-01-01T00:00:00Z"))
        #expect(query.contains("billed_at[LTE]=2026-01-04T00:00:00Z"))
        #expect(query.contains("status=paid,completed"))
        #expect(query.contains("per_page=30"))
    }

    /// A number this adapter cannot stand behind as whole has to say so. The
    /// Worker's cap is twenty pages and so is this one.
    @Test("a walk past the page cap says it is an undercount")
    func truncates() async throws {
        let (provider, http) = paddle { request in
            .ok(
                """
                {"data":[{"id":"txn","status":"completed","currency_code":"USD",
                  "billed_at":"2026-01-02T00:00:00.000000Z","created_at":"2026-01-02T00:00:00.000000Z",
                  "details":{"totals":{"total":"100"}}}],
                 "meta":{"pagination":{"has_more":true,
                   "next":"https://api.paddle.com/transactions?after=\(PaddleStub.seen.count)"}}}
                """)
        }
        let value = try await provider.fetch(liveKey, window: window("revenue"), http: http)

        #expect(PaddleStub.requests().count == PaddleProvider.maxPages)
        #expect(value.value == 2000)
        #expect(
            value.note
                == "Only the first 20 pages of transactions were read, so this is an undercount.")
    }
}

@Suite("paddle subscriptions")
struct PaddleSubscriptionTests {
    private func subscription(
        _ id: String, currency: String = "USD", status: String = "active",
        itemStatus: String = "active", amount: String = "1000", interval: String = "month",
        frequency: Int = 1, quantity: Int = 1,
        startedAt: String? = "2026-01-02T00:00:00.000000Z", canceledAt: String? = nil
    ) -> String {
        let cycle = #"{"interval":"\#(interval)","frequency":\#(frequency)}"#
        return """
            {"id":"\(id)","status":"\(status)","currency_code":"\(currency)",
             "created_at":"2025-12-01T00:00:00.000000Z",
             "started_at":\(startedAt.map { "\"\($0)\"" } ?? "null"),
             "canceled_at":\(canceledAt.map { "\"\($0)\"" } ?? "null"),
             "items":[{"status":"\(itemStatus)","quantity":\(quantity),
               "price":{"unit_price":{"amount":"\(amount)","currency_code":"\(currency)"},
                        "billing_cycle":\(cycle)}}]}
            """
    }

    private func page(_ rows: [String]) -> String {
        #"{"data":[\#(rows.joined(separator: ","))],"meta":{"pagination":{"has_more":false}}}"#
    }

    /// A snapshot of the book right now, not a sum over the window — which is
    /// what the methodology on the manifest promises.
    @Test("mrr normalises each cycle to a month")
    func mrr() async throws {
        let body = page([
            subscription("sub_1", amount: "1000"),
            subscription("sub_2", amount: "12000", interval: "year"),
            subscription("sub_3", amount: "3000", interval: "month", frequency: 3),
            subscription("sub_4", amount: "500", quantity: 4),
        ])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(liveKey, window: window("mrr"), http: http)

        #expect(value.value == 1000 + 1000 + 1000 + 2000)
        #expect(value.currency == "USD")
    }

    /// Rounded once at the end, not per subscription: an annual plan's
    /// twelfth otherwise drifts across a book, and money is an integer here
    /// and everywhere else.
    @Test("mrr is whole minor units")
    func wholeUnits() async throws {
        let body = page([
            subscription("sub_1", amount: "100", interval: "year"),
            subscription("sub_2", amount: "100", interval: "year"),
            subscription("sub_3", amount: "100", interval: "year"),
        ])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(liveKey, window: window("mrr"), http: http)

        // 25/3 each, 25 together. Rounding each would have given 24.
        #expect(value.value == 25)
    }

    @Test("a cancelled item and a one-off price are not recurring revenue")
    func skipped() async throws {
        let oneOff = """
            {"id":"sub_x","status":"active","currency_code":"USD",
             "created_at":"2025-12-01T00:00:00.000000Z","started_at":null,"canceled_at":null,
             "items":[{"status":"active","quantity":1,
               "price":{"unit_price":{"amount":"9900","currency_code":"USD"},
                        "billing_cycle":null}}]}
            """
        let body = page([
            subscription("sub_1", amount: "1000"),
            subscription("sub_2", itemStatus: "canceled", amount: "5000"),
            oneOff,
        ])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(liveKey, window: window("mrr"), http: http)

        #expect(value.value == 1000)
    }

    @Test("a book in another currency is excluded and named")
    func otherCurrency() async throws {
        let body = page([
            subscription("sub_1", amount: "1000"),
            subscription("sub_2", currency: "EUR", amount: "9000"),
        ])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(liveKey, window: window("mrr"), http: http)

        #expect(value.value == 1000)
        #expect(value.note == "EUR excluded; totals are USD only.")
    }

    @Test("active subscriptions are a count of the active list")
    func activeCount() async throws {
        let body = page([subscription("sub_1"), subscription("sub_2"), subscription("sub_3")])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(
            liveKey, window: window("active_subscribers"), http: http)

        #expect(value.value == 3)
        #expect(value.currency == nil)
        let query = try #require(PaddleStub.requests().first?.url?.query)
        #expect(query.contains("status=active"))
        #expect(query.contains("per_page=200"))
    }

    /// Paddle cannot filter subscriptions by date, so the whole book is read
    /// and bucketed here — and the ones outside the window are dropped rather
    /// than counted.
    @Test("new subscriptions are bucketed by when they started")
    func newSubscribers() async throws {
        let body = page([
            subscription("sub_1", startedAt: "2026-01-02T00:00:00.000000Z"),
            subscription("sub_2", startedAt: "2026-01-02T12:00:00.000000Z"),
            subscription("sub_3", startedAt: "2025-11-01T00:00:00.000000Z"),
        ])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(liveKey, window: window("new_subscribers"), http: http)

        #expect(value.value == 2)
        #expect(value.points.count == 4)
        #expect(value.points[1].v == 2)
        // Any status, because one started and cancelled in the same window
        // still started in it.
        #expect(PaddleStub.requests().first?.url?.query?.contains("status=") != true)
    }

    /// `started_at` is null while a subscription is trialing, and a trial
    /// that never converts would otherwise be invisible on the tile.
    @Test("a subscription with no start date falls back to when it was created")
    func trialing() async throws {
        let body = page([
            subscription("sub_1", startedAt: nil)  // created 2025-12-01, outside the window
        ])
        let (provider, http) = paddle { _ in .ok(body) }
        let december = try await provider.fetch(
            liveKey,
            window: window("new_subscribers", from: "2025-11-30T00:00:00Z", to: "2025-12-02T00:00:00Z"),
            http: http)

        #expect(december.value == 1)
    }

    @Test("churn asks Paddle for the cancelled list and buckets by the cancellation")
    func churn() async throws {
        let body = page([
            subscription(
                "sub_1", status: "canceled", startedAt: "2025-01-01T00:00:00.000000Z",
                canceledAt: "2026-01-03T06:00:00.000000Z"),
            subscription(
                "sub_2", status: "canceled", startedAt: "2025-01-01T00:00:00.000000Z",
                canceledAt: "2025-06-01T00:00:00.000000Z"),
            // Still running: nothing to count, and no date to count it on.
            subscription("sub_3"),
        ])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(
            liveKey, window: window("churned_subscribers"), http: http)

        #expect(value.value == 1)
        #expect(value.points[2].v == 1)
        #expect(PaddleStub.requests().first?.url?.query?.contains("status=canceled") == true)
    }
}

/// The list shape, which nothing else exercises.
@Suite("paddle recent payments")
struct PaddleRecentPaymentsTests {
    private func transaction(
        _ id: String, _ billedAt: String?, total: String = "1000", currency: String = "USD",
        status: String = "completed", name: String? = "Ada Lovelace", email: String? = nil,
        product: String? = "Pro plan"
    ) -> String {
        let quoted = { (value: String?) in value.map { "\"\($0)\"" } ?? "null" }
        return """
            {"id":"\(id)","status":"\(status)","currency_code":"\(currency)",
             "billed_at":\(quoted(billedAt)),"created_at":"2026-01-01T00:00:00.000000Z",
             "customer":{"name":\(quoted(name)),"email":\(quoted(email))},
             "details":{"totals":{"total":"\(total)"},
                        "line_items":[{"product":{"name":\(quoted(product))}}]}}
            """
    }

    private func page(_ rows: [String]) -> String {
        #"{"data":[\#(rows.joined(separator: ","))]}"#
    }

    @Test("rows carry the customer, the first product and the amount in minor units")
    func rows() async throws {
        let body = page([transaction("txn_1", "2026-01-03T10:00:00.123456Z", total: "2499")])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(liveKey, window: window("recent_payments"), http: http)

        let items = try #require(value.items)
        #expect(items.count == 1)
        #expect(items[0].id == "txn_1")
        #expect(items[0].label == "Ada Lovelace")
        #expect(items[0].detail == "Pro plan")
        #expect(items[0].amount == 2499)
        #expect(items[0].currency == "USD")
        #expect(items[0].status == "completed")
        // A payment is not pass or fail. It just happened.
        #expect(items[0].state == nil)
        // The six fractional digits Paddle prints survive the round trip.
        #expect(items[0].t.hasPrefix("2026-01-03T10:00:00.123"))
    }

    @Test("the email stands in for a missing name, and something stands in for both")
    func labels() async throws {
        let body = page([
            transaction("txn_1", "2026-01-03T10:00:00.000000Z", name: nil, email: "ada@example.com"),
            transaction("txn_2", "2026-01-02T10:00:00.000000Z", name: "", email: nil),
        ])
        let (provider, http) = paddle { _ in .ok(body) }
        let items = try #require(
            try await provider.fetch(liveKey, window: window("recent_payments"), http: http).items)

        #expect(items[0].label == "ada@example.com")
        #expect(items[1].label == "Customer")
    }

    /// Ten is what the tallest tile shows, and the cap is applied after the
    /// status filter rather than before it — which is why twenty are asked
    /// for.
    @Test("newest first, ten at most, and never an unpaid row")
    func sortedAndCapped() async throws {
        var rows = (1...12).map { index in
            transaction(
                "txn_\(index)",
                String(format: "2026-01-02T%02d:00:00.000000Z", index))
        }
        rows.append(transaction("txn_billed", "2026-01-03T23:00:00.000000Z", status: "billed"))
        let body = page(rows)
        let (provider, http) = paddle { _ in .ok(body) }
        let items = try #require(
            try await provider.fetch(liveKey, window: window("recent_payments"), http: http).items)

        #expect(items.count == 10)
        #expect(items.first?.id == "txn_12")
        #expect(items.map(\.id).contains("txn_billed") == false)
        #expect(items.map(\.id).contains("txn_1") == false)

        let query = try #require(PaddleStub.requests().first?.url?.query?.removingPercentEncoding)
        #expect(query.contains("per_page=20"))
        #expect(query.contains("include=customer"))
        #expect(PaddleStub.requests().count == 1)
    }

    /// The headline is not the row count: a tile too short to show rows still
    /// has to say something true, and that is their total in one currency.
    /// Rows in another currency keep their own code rather than being dropped
    /// — a list can show a currency where a sum cannot.
    @Test("the headline totals only the rows in the user's currency")
    func total() async throws {
        let body = page([
            transaction("txn_1", "2026-01-03T10:00:00.000000Z", total: "1500"),
            transaction("txn_2", "2026-01-03T09:00:00.000000Z", total: "2500", currency: "EUR"),
            transaction("txn_3", "2026-01-03T08:00:00.000000Z", total: "700"),
        ])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(liveKey, window: window("recent_payments"), http: http)

        #expect(value.value == 2200)
        #expect(value.currency == "USD")
        #expect(try #require(value.items).count == 3)
        #expect(try #require(value.items)[1].currency == "EUR")
    }

    @Test("a transaction never billed is timestamped by when it was created")
    func noBillingDate() async throws {
        let body = page([transaction("txn_1", nil)])
        let (provider, http) = paddle { _ in .ok(body) }
        let items = try #require(
            try await provider.fetch(liveKey, window: window("recent_payments"), http: http).items)

        #expect(items[0].date == date("2026-01-01T00:00:00Z"))
    }
}

/// The comparison period, which is the half of a delta nothing on screen
/// can check: a wrong `previousValue` renders as a confident percentage.
@Suite("paddle comparison")
struct PaddleCompareTests {
    private func transaction(_ id: String, _ billedAt: String, _ total: String) -> String {
        """
        {"id":"\(id)","status":"completed","currency_code":"USD",
         "billed_at":"\(billedAt)","created_at":"\(billedAt)",
         "details":{"totals":{"total":"\(total)"}}}
        """
    }

    private func page(_ rows: [String]) -> String {
        #"{"data":[\#(rows.joined(separator: ","))],"meta":{"pagination":{"has_more":false}}}"#
    }

    /// Three days asked for, six days fetched, and the server-side filter is
    /// what bounds it — the split below trusts that nothing older than the
    /// comparison period is in hand.
    @Test("the fetch is widened backwards by the window's own length")
    func widened() async throws {
        let (provider, http) = paddle { _ in .ok(#"{"data":[]}"#) }
        _ = try await provider.fetch(
            liveKey, window: window("revenue", comparePrevious: true), http: http)

        let query = try #require(PaddleStub.requests().first?.url?.query?.removingPercentEncoding)
        #expect(query.contains("billed_at[GTE]=2025-12-29T00:00:00Z"))
        #expect(query.contains("billed_at[LTE]=2026-01-04T00:00:00Z"))
    }

    /// The headline is the later half alone. Summed from the buckets instead
    /// it would carry the comparison period's money into the figure on
    /// screen, because a window edge is an instant and a bucket is a day.
    @Test("the window is the headline and the period before it is the comparison")
    func split() async throws {
        let body = page([
            transaction("txn_old_1", "2025-12-30T10:00:00.000000Z", "400"),
            transaction("txn_old_2", "2025-12-31T18:00:00.000000Z", "600"),
            transaction("txn_new_1", "2026-01-01T10:00:00.000000Z", "1500"),
            transaction("txn_new_2", "2026-01-03T09:00:00.000000Z", "700"),
        ])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(
            liveKey, window: window("revenue", comparePrevious: true), http: http)

        #expect(value.value == 2200)
        #expect(value.previousValue == 1000)
    }

    /// Zero here would draw "down 100%" against a window the fetch never
    /// looked at.
    @Test("a tile with no delta gets nil, not zero")
    func noComparison() async throws {
        let body = page([transaction("txn_new_1", "2026-01-01T10:00:00.000000Z", "1500")])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(liveKey, window: window("revenue"), http: http)

        #expect(value.previousValue == nil)
        #expect(value.value == 1500)
        // And the fetch stayed inside the window it was asked about.
        let query = try #require(PaddleStub.requests().first?.url?.query?.removingPercentEncoding)
        #expect(query.contains("billed_at[GTE]=2026-01-01T00:00:00Z"))
    }

    /// The comparison period is a number, not a second series: a chart drawn
    /// over both halves would show a delta the range picker never asked for.
    @Test("the chart still covers only the requested window")
    func pointsUnwidened() async throws {
        let body = page([
            transaction("txn_old_1", "2025-12-30T10:00:00.000000Z", "400"),
            transaction("txn_new_1", "2026-01-02T10:00:00.000000Z", "1500"),
        ])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(
            liveKey, window: window("revenue", comparePrevious: true), http: http)

        #expect(value.points.count == 4)
        #expect(value.points.map(\.v) == [0, 1500, 0, 0])
    }

    /// Paddle cannot filter subscriptions by date at all, so the comparison
    /// period is a wider local filter rather than a wider request.
    @Test("a counting metric compares the same way")
    func counts() async throws {
        let subscription = { (id: String, startedAt: String) in
            """
            {"id":"\(id)","status":"active","currency_code":"USD",
             "created_at":"2025-01-01T00:00:00.000000Z","started_at":"\(startedAt)",
             "canceled_at":null,"items":[]}
            """
        }
        let body = page([
            subscription("sub_old_1", "2025-12-30T00:00:00.000000Z"),
            subscription("sub_old_2", "2025-12-31T00:00:00.000000Z"),
            subscription("sub_old_3", "2025-12-31T12:00:00.000000Z"),
            subscription("sub_new_1", "2026-01-02T00:00:00.000000Z"),
            // Older than the comparison period, so it belongs to neither half.
            subscription("sub_ancient", "2025-06-01T00:00:00.000000Z"),
        ])
        let (provider, http) = paddle { _ in .ok(body) }
        let value = try await provider.fetch(
            liveKey, window: window("new_subscribers", comparePrevious: true), http: http)

        #expect(value.value == 1)
        #expect(value.previousValue == 3)
        #expect(value.points.count == 4)
    }
}

// MARK: - Verify

@Suite("paddle verify")
struct PaddleVerifyTests {
    private func reply(
        transactions: PaddleStub.Reply, subscriptions: PaddleStub.Reply
    ) -> @Sendable (URLRequest) -> PaddleStub.Reply {
        { request in
            let path = request.url?.path ?? ""
            if path == "/transactions" { return transactions }
            if path == "/subscriptions" { return subscriptions }
            return .ok(#"{"data":[]}"#)
        }
    }

    /// Paddle has no endpoint that reports the seller's currency, so the
    /// newest transaction is the only thing that knows it.
    @Test("a key that reads everything offers everything, and names the currency")
    func healthy() async throws {
        let (provider, http) = paddle(
            reply(
                transactions: .ok(
                    #"{"data":[{"id":"txn_1","status":"completed","currency_code":"gbp","created_at":"2026-01-01T00:00:00.000000Z"}]}"#),
                subscriptions: .ok(#"{"data":[]}"#)))
        let account = try await provider.verify(liveKey, http: http)

        #expect(account.currency == "GBP")
        #expect(account.unavailableMetrics.isEmpty)
        #expect(account.label == "Paddle")
        // The free call first, so a key on the wrong host fails in one
        // request rather than twice over below.
        #expect(PaddleStub.requests().first?.url?.path == "/event-types")
    }

    /// Narrowing what is offered beats refusing the connection and telling
    /// somebody their deliberately scoped-down key is broken.
    @Test("a key without subscriptions still gets revenue, with MRR withheld")
    func scopedDown() async throws {
        let (provider, http) = paddle(
            reply(
                transactions: .ok(#"{"data":[]}"#),
                subscriptions: PaddleStub.Reply(
                    status: 403, body: #"{"error":{"code":"forbidden"}}"#)))
        let account = try await provider.verify(liveKey, http: http)

        #expect(account.unavailableMetrics == PaddleProvider.subscriptionMetrics)
        #expect(account.currency == nil)
    }

    @Test("a key that reads neither list is refused, and says what to grant")
    func readsNothing() async throws {
        let (provider, http) = paddle(
            reply(
                transactions: PaddleStub.Reply(status: 403, body: ""),
                subscriptions: PaddleStub.Reply(status: 403, body: "")))

        await #expect(throws: ProviderFailure.self) { try await provider.verify(liveKey, http: http) }
    }

    /// Only a permission problem is tolerated. An outage during verify must
    /// not be stored as a key that cannot read subscriptions, because nothing
    /// re-probes afterwards and the metrics stay hidden until the connection
    /// is remade.
    @Test("an outage during a probe is not mistaken for a missing permission")
    func outage() async throws {
        let (provider, http) = paddle(
            reply(
                transactions: PaddleStub.Reply(status: 503, body: ""),
                subscriptions: .ok(#"{"data":[]}"#)))

        await #expect(throws: ProviderFailure.self) { try await provider.verify(liveKey, http: http) }
    }

    /// The environment is the only thing that tells two Paddle connections
    /// apart, so it has to reach the label.
    @Test("a sandbox connection is labelled as one")
    func sandboxLabel() async throws {
        let (provider, http) = paddle { _ in .ok(#"{"data":[]}"#) }
        let account = try await provider.verify(
            ["api_key": "pdl_sdbx_apikey_0123456789", "mode": "sandbox"], http: http)

        #expect(account.label == "Paddle Sandbox")
    }
}
}
