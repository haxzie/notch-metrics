import Foundation
import MetricsCore
import Testing

@testable import Providers

// MARK: - A stubbed Shopify

/// Answers whatever the adapter asks for, and records that it asked.
///
/// A `URLProtocol` rather than a fake `ProviderHTTP`, so the allowlist, the
/// manual redirect handling and the byte cap are all still in the path — the
/// host a request actually went to is one of the things these tests pin, and
/// a stub above `ProviderHTTP` could not see it.
///
/// Every Shopify call is the same POST to the same URL, so replies are chosen
/// by call index and by what the query body asked for rather than by path.
final class ShopifyStub: URLProtocol {
    struct Call: Sendable {
        let request: URLRequest
        /// The GraphQL request body, which is the only thing distinguishing
        /// one call from the next.
        let body: String
        /// 0 for the first call since the session was built.
        let index: Int
    }

    struct Reply: Sendable {
        let status: Int
        let body: String
        var headers: [String: String] = [:]

        static func ok(_ body: String) -> Reply { Reply(status: 200, body: body) }
    }

    nonisolated(unsafe) static var reply: @Sendable (Call) -> Reply = { _ in .ok(#"{"data":{}}"#) }
    nonisolated(unsafe) static var calls: [Call] = []

    static func session(_ reply: @escaping @Sendable (Call) -> Reply) -> URLSession {
        Self.reply = reply
        Self.calls = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ShopifyStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // `URLProtocol` is handed the body as a stream rather than as
        // `httpBody`, so reading the obvious property would make every
        // assertion about the query silently vacuous.
        let data = request.httpBody ?? ShopifyStub.drain(request.httpBodyStream)
        let call = Call(
            request: request, body: String(decoding: data, as: UTF8.self),
            index: ShopifyStub.calls.count)
        ShopifyStub.calls.append(call)

        let reply = ShopifyStub.reply(call)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(contentsOf: buffer[0..<read])
        }
        return data
    }
}

/// Shopify, pointed at the stub. The allowlist is the adapter's own.
private func shopify(
    _ reply: @escaping @Sendable (ShopifyStub.Call) -> ShopifyStub.Reply
) -> (ShopifyProvider, ProviderHTTP) {
    let provider = ShopifyProvider()
    return (
        provider,
        ProviderHTTP(allowedHosts: provider.allowedHosts, session: ShopifyStub.session(reply))
    )
}

private let credentials = [
    "shop_domain": "my-store.myshopify.com",
    "access_token": "shpat_0123456789abcdef",
]

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

// MARK: - Bodies

private func quoted(_ value: String?) -> String {
    guard let value else { return "null" }
    return "\"\(value)\""
}

private func order(
    _ id: String, _ createdAt: String, total: String = "10.00", currency: String = "USD",
    refunded: String? = nil, status: String? = "PAID", test: Bool = false,
    name: String? = "#1001", customer: String? = "Ada Lovelace", email: String? = nil,
    product: String? = "Pro plan"
) -> String {
    let refundedSet =
        refunded.map { #"{"shopMoney":{"amount":"\#($0)","currencyCode":"\#(currency)"}}"# }
        ?? "null"
    return """
        {"id":"\(id)","name":\(quoted(name)),"createdAt":"\(createdAt)","test":\(test),
         "displayFinancialStatus":\(quoted(status)),
         "totalPriceSet":{"shopMoney":{"amount":"\(total)","currencyCode":"\(currency)"}},
         "totalRefundedSet":\(refundedSet),
         "customer":{"displayName":\(quoted(customer)),"email":\(quoted(email))},
         "lineItems":{"nodes":[{"title":\(quoted(product))}]}}
        """
}

private func ordersPage(
    _ nodes: [String], hasNextPage: Bool = false, cursor: String? = "cursor-1"
) -> String {
    """
    {"data":{"orders":{"nodes":[\(nodes.joined(separator: ","))],
     "pageInfo":{"hasNextPage":\(hasNextPage),"endCursor":\(quoted(cursor))}}}}
    """
}

private func recentOrders(_ nodes: [String]) -> String {
    #"{"data":{"orders":{"nodes":[\#(nodes.joined(separator: ","))]}}}"#
}

private func customersPage(
    _ createdAt: [String], hasNextPage: Bool = false, cursor: String? = "cursor-1"
) -> String {
    let nodes = createdAt.enumerated()
        .map { #"{"id":"gid://shopify/Customer/\#($0.offset)","createdAt":"\#($0.element)"}"# }
    return """
        {"data":{"customers":{"nodes":[\(nodes.joined(separator: ","))],
         "pageInfo":{"hasNextPage":\(hasNextPage),"endCursor":\(quoted(cursor))}}}}
        """
}

/// A GraphQL error, which Shopify sends with a 200 beside a null `data`.
private func graphQLError(_ code: String?, _ message: String) -> String {
    let extensions = code.map { #","extensions":{"code":"\#($0)"}"# } ?? ""
    return #"{"data":null,"errors":[{"message":"\#(message)"\#(extensions)}]}"#
}

// MARK: - The shop domain

/// The transform with no Swift equivalent until now, and the one place a
/// mistake costs a store rather than a tile: a domain that is wrong in a way
/// Shopify answers 404 to reads as a deleted store.
@Suite("shopify shop domain")
struct ShopifyDomainTests {
    @Test("every form somebody pastes is the same store")
    func forms() {
        for input in [
            "my-store.myshopify.com",
            "My-Store.myshopify.com",
            "https://my-store.myshopify.com",
            "https://My-Store.myshopify.com/admin",
            "https://my-store.myshopify.com/admin/",
            "http://my-store.myshopify.com",
            "  my-store.myshopify.com  ",
            "my-store",
            "My-Store",
        ] {
            #expect(ShopifyProvider.normaliseShopDomain(input) == "my-store.myshopify.com")
        }
    }

    /// The property that matters, because the same normalisation runs on the
    /// blob coming *back out* of storage on every fetch. One that appended a
    /// suffix twice would break a connection that worked when it was made.
    @Test("normalising an already normalised domain changes nothing")
    func idempotent() {
        for input in ["my-store", "https://my-store.myshopify.com/admin", "shop.example.com"] {
            let once = ShopifyProvider.normaliseShopDomain(input)
            #expect(ShopifyProvider.normaliseShopDomain(once) == once)
        }
    }

    /// Silently rewriting `shop.example.com` into
    /// `shop.example.com.myshopify.com` would fail later as a 404 that reads
    /// like a deleted store, so a host with a dot is left alone and rejected
    /// by name.
    @Test("a custom storefront domain is left alone, then refused by name")
    func customDomain() {
        #expect(ShopifyProvider.normaliseShopDomain("shop.example.com") == "shop.example.com")
        #expect(throws: ProviderFailure.self) {
            try ShopifyProvider.credentials([
                "shop_domain": "shop.example.com", "access_token": "shpat_abc123",
            ])
        }
    }

    /// A deeper host is what the allowlist's one-label wildcard exists to
    /// stop; refusing it here means it never reaches `ProviderHTTP` at all.
    @Test("a host pretending to be a store is refused")
    func lookalike() {
        for domain in [
            "store.myshopify.com.attacker.net", "evil.store.myshopify.com",
            "-store.myshopify.com", "myshopify.com",
        ] {
            #expect(throws: ProviderFailure.self) {
                try ShopifyProvider.credentials([
                    "shop_domain": domain, "access_token": "shpat_abc123",
                ])
            }
        }
    }

    @Test("a store domain and token that are both well formed are accepted")
    func accepted() throws {
        let creds = try ShopifyProvider.credentials([
            "shop_domain": "https://My-Store.myshopify.com/admin",
            "access_token": "shpca_collaborator123",
        ])
        #expect(creds.shopDomain == "my-store.myshopify.com")
        #expect(creds.handle == "my-store")
        #expect(
            creds.endpoint == "https://my-store.myshopify.com/admin/api/2026-10/graphql.json")
    }

    /// The form will not submit an empty required field, so this is a bug
    /// rather than user error — but it reaches a live API either way, and an
    /// empty token reads back as a revoked one.
    @Test("a missing or malformed credential is refused before any request")
    func refused() {
        #expect(throws: ProviderFailure.self) { try ShopifyProvider.credentials([:]) }
        #expect(throws: ProviderFailure.self) {
            try ShopifyProvider.credentials(["shop_domain": "my-store", "access_token": "   "])
        }
        // A Storefront or Partner token is not an Admin token, and sending
        // one answers 401 — which reads as a revoked key rather than as the
        // wrong kind of key.
        #expect(throws: ProviderFailure.self) {
            try ShopifyProvider.credentials([
                "shop_domain": "my-store", "access_token": "shpss_0123456789",
            ])
        }
    }
}

// MARK: - Failures

/// Shopify's statuses, in the buckets the caller acts differently on.
///
/// Tested through `failure(for:shop:)` rather than over the network: what is
/// worth pinning is which bucket each status lands in, and that a frozen
/// store does not send the user off to make a new token.
@Suite("shopify failures")
struct ShopifyFailureTests {
    private func response(_ status: Int, body: String = "", headers: [String: String] = [:])
        -> ProviderHTTP.Response
    {
        ProviderHTTP.Response(status: status, headers: headers, body: Data(body.utf8))
    }

    private func failure(_ status: Int, body: String = "", headers: [String: String] = [:])
        -> ProviderFailure
    {
        ShopifyProvider.failure(
            for: response(status, body: body, headers: headers), shop: "my-store.myshopify.com")
    }

    /// The three the generic mapping gets wrong. A frozen or locked store
    /// reads as "rejected the credentials" through it, which sends the user
    /// looking for a key problem they do not have.
    @Test("an unpaid bill and a locked store are about the store, not the token")
    func notTheToken() {
        #expect(
            failure(402)
                == .unsupported(
                    "my-store.myshopify.com is frozen or on a plan without Admin API access."))
        #expect(failure(423) == .unsupported("my-store.myshopify.com is locked."))
    }

    /// The one case that really is the credential: either the domain names no
    /// store, or the app that issued the token is gone from it.
    @Test("a 404 is an auth failure rather than a bad request")
    func gone() {
        #expect(
            failure(404)
                == .authFailed(
                    "my-store.myshopify.com does not exist, or the app has been uninstalled "
                        + "from it."))
    }

    /// The status is part of the message on purpose: a 403 from a host that
    /// normally says 401 is how a WAF in front of Shopify shows up, and that
    /// is a different afternoon from a revoked token.
    @Test("a rejected token carries the status and Shopify's own words")
    func rejected() {
        #expect(
            failure(401, body: #"{"errors":"[API] Invalid API key or access token"}"#)
                == .authFailed(
                    "my-store.myshopify.com rejected the credentials (401): "
                        + "[API] Invalid API key or access token"))
        #expect(
            failure(403)
                == .authFailed("my-store.myshopify.com rejected the credentials (403)"))
    }

    /// A nil wait would have the refresh loop retry on its own tick, which on
    /// a spent quota is immediately.
    @Test("a spent quota carries the wait, or a minute when none was sent")
    func rateLimited() {
        #expect(
            failure(429, headers: ["Retry-After": "12"])
                == .rateLimited("my-store.myshopify.com asked us to wait", retryAfter: 12))
        #expect(
            failure(429) == .rateLimited("my-store.myshopify.com asked us to wait", retryAfter: 60))
    }

    @Test("a 5xx is their outage, retried rather than reported as a bad token")
    func down() {
        #expect(failure(503) == .providerDown("my-store.myshopify.com returned 503"))
    }

    /// Throwing the body away leaves "returned 400" on screen, and the cause
    /// then has to be guessed from outside the system.
    @Test("any other 4xx keeps the explanation Shopify sent")
    func explained() {
        #expect(
            failure(400, body: #"{"errors":[{"message":"Field 'orders' doesn't exist"}]}"#)
                == .badResponse(
                    "my-store.myshopify.com returned 400: Field 'orders' doesn't exist"))
        #expect(failure(418) == .badResponse("my-store.myshopify.com returned 418"))
    }

    /// `errors` arrives both ways: a bare string from the auth layer, an array
    /// of objects from GraphQL. Reading only one of them would replace a
    /// sentence naming the problem with the bare status.
    @Test("both shapes of Shopify's errors field are read")
    func shapes() {
        #expect(
            ShopifyProvider.message(in: Data(#"{"errors":"Not Found"}"#.utf8)) == "Not Found")
        #expect(
            ShopifyProvider.message(
                in: Data(#"{"errors":[{"message":"one"},{"message":"two"}]}"#.utf8)) == "one two")
        #expect(ShopifyProvider.message(in: Data(#"{"message":"flat"}"#.utf8)) == "flat")
        #expect(ShopifyProvider.message(in: Data("<html>502</html>".utf8)) == nil)
    }

    /// The failure this prevents is a store's own Admin token ending up on
    /// screen, and from there in a screenshot in a support thread.
    @Test("a token Shopify quoted back is redacted")
    func redacted() {
        let body = #"{"errors":"Token shpat_AbC123def is not valid"}"#
        #expect(ShopifyProvider.message(in: Data(body.utf8)) == "Token shpat_… is not valid")
    }

    /// Admin deep links run to a couple of hundred characters of shop handle
    /// and query string, and cutting out just the URL leaves "Fix this at ."
    @Test("a sentence containing a link goes whole")
    func links() {
        let body =
            #"{"errors":"Required access: read_orders. Grant it at https://admin.shopify.com/x."}"#
        #expect(
            ShopifyProvider.message(in: Data(body.utf8)) == "Required access: read_orders.")
    }

    /// Shopify's budget is points per second, so the wait is arithmetic
    /// rather than a guess — and a guess is what a throttled store backs off
    /// by when this is wrong.
    @Test("the backoff is read off Shopify's own cost accounting")
    func backoff() {
        #expect(
            ShopifyProvider.retryAfter(
                ShopifyProvider.Cost(
                    requestedQueryCost: 1000,
                    throttleStatus: .init(currentlyAvailable: 100, restoreRate: 50))) == 18)
        // Clamped at both ends: never zero, because a zero wait is no wait,
        // and never longer than a minute, because nothing in a notch is.
        #expect(
            ShopifyProvider.retryAfter(
                ShopifyProvider.Cost(
                    requestedQueryCost: 10,
                    throttleStatus: .init(currentlyAvailable: 900, restoreRate: 50))) == 1)
        #expect(
            ShopifyProvider.retryAfter(
                ShopifyProvider.Cost(
                    requestedQueryCost: 100_000,
                    throttleStatus: .init(currentlyAvailable: 0, restoreRate: 50))) == 60)
        // No cost block at all still has to produce a wait.
        #expect(ShopifyProvider.retryAfter(nil) == 1)
    }
}

// MARK: - Money

@Suite("shopify money")
struct ShopifyMoneyTests {
    /// Shopify reports money as a decimal string. Multiplying by 100 would
    /// make every yen figure a hundred times too large and every dinar a
    /// tenth of what it is.
    @Test("a decimal string becomes integer minor units for the right currency")
    func minorUnits() {
        #expect(ShopifyProvider.minorUnits(12.34, currency: "USD") == 1234)
        #expect(ShopifyProvider.minorUnits(1234, currency: "JPY") == 1234)
        #expect(ShopifyProvider.minorUnits(1.234, currency: "KWD") == 1234)
        // Rounded rather than truncated, so a half-cent from a tax or
        // discount split does not vanish.
        #expect(ShopifyProvider.minorUnits(0.005, currency: "USD") == 1)
    }

    @Test("a bag Shopify sent as null, or with an unreadable amount, is no money at all")
    func missing() {
        #expect(ShopifyProvider.money(nil) == nil)
        let bag = try? JSONDecoder().decode(
            ShopifyProvider.MoneyBag.self,
            from: Data(#"{"shopMoney":{"amount":"not a number","currencyCode":"usd"}}"#.utf8))
        #expect(ShopifyProvider.money(bag) == nil)
    }

    @Test("the currency code is upper case whatever Shopify sent")
    func upperCased() throws {
        let bag = try JSONDecoder().decode(
            ShopifyProvider.MoneyBag.self,
            from: Data(#"{"shopMoney":{"amount":"5.00","currencyCode":"eur"}}"#.utf8))
        let money = try #require(ShopifyProvider.money(bag))
        #expect(money.amount == 500)
        #expect(money.currency == "EUR")
    }
}

// MARK: - Over the wire

/// Everything that answers through the stub, serialised.
///
/// One outer suite rather than four, because `.serialized` applies to a
/// suite's descendants and not to its siblings — and the stub's routing table
/// is process-wide, since a `URLProtocol` subclass is registered on a session
/// configuration *by type*. Four sibling suites run in parallel, each
/// replacing the others' replies between calls, and the failures that
/// produces are attributed to whichever test was unlucky.
@Suite("shopify over the wire", .serialized)
struct ShopifyWireTests {

    // MARK: - The GraphQL error taxonomy

    @Suite("shopify graphql errors")
    struct ShopifyGraphQLTests {
        /// The whole reason the body is read at all: Shopify answers **200** for
        /// a missing scope, a throttle and a query that costs too much. Reading
        /// only the status would turn each of them into an empty tile.
        @Test("a missing scope is an auth failure, named")
        func accessDenied() async {
            let denied = "Access denied for orders field. Required access: `read_orders` scope."
            let (provider, http) = shopify { _ in .ok(graphQLError("ACCESS_DENIED", denied)) }
            await #expect(throws: ProviderFailure.authFailed(denied)) {
                try await provider.fetch(credentials, window: window("revenue"), http: http)
            }
        }

        /// A restricted token is a statement about one resource rather than about
        /// the connection — but Shopify says "access denied" without a code as
        /// often as with one, so the message is matched too.
        @Test("access denied without a code is still access denied")
        func accessDeniedUncoded() async {
            let (provider, http) = shopify { _ in .ok(graphQLError(nil, "Access denied")) }
            await #expect(throws: ProviderFailure.authFailed("Access denied")) {
                try await provider.fetch(credentials, window: window("revenue"), http: http)
            }
        }

        /// A throttle on the first page has nothing to report, so it is the error
        /// — and it carries the wait, because the refresh loop honours it.
        @Test("a throttle on the first page is a rate limit with Shopify's own wait")
        func throttledFirstPage() async {
            let (provider, http) = shopify { _ in
                .ok("""
                    {"data":null,"errors":[{"message":"Throttled","extensions":{"code":"THROTTLED"}}],
                     "extensions":{"cost":{"requestedQueryCost":600,
                     "throttleStatus":{"currentlyAvailable":100,"restoreRate":50}}}}
                    """)
            }
            await #expect(throws: ProviderFailure.rateLimited(
                "my-store.myshopify.com is rate limited", retryAfter: 10)) {
                try await provider.fetch(credentials, window: window("revenue"), http: http)
            }
        }

        /// A `Throttled` that escaped would be logged as an unhandled error and
        /// the tile would say "something went wrong", with the wait thrown away.
        @Test("a throttle anywhere else is still a rate limit, not a crash")
        func throttledElsewhere() async {
            let (provider, http) = shopify { _ in .ok(graphQLError("THROTTLED", "Throttled")) }
            await #expect(throws: ProviderFailure.rateLimited(
                "Shopify is rate limiting this store", retryAfter: 1)) {
                try await provider.fetch(credentials, window: window("customers"), http: http)
            }
        }

        @Test("a query Shopify refuses as too large is about the request, not the token")
        func tooLarge() async {
            let (provider, http) = shopify { _ in
                .ok(graphQLError("MAX_COST_EXCEEDED", "Query cost is 2000, maximum is 1000"))
            }
            await #expect(throws: ProviderFailure.unsupported(
                "Shopify refused the query as too large to run.")) {
                try await provider.fetch(credentials, window: window("revenue"), http: http)
            }
        }

        /// Shopify's `errors` is a bare string when the request never reached the
        /// GraphQL layer. Decoding only the array form would replace the sentence
        /// naming the problem with "the response could not be read".
        @Test("an errors field that is a string is read rather than dropped")
        func errorsAsString() async {
            let (provider, http) = shopify { _ in .ok(#"{"errors":"Bad Request"}"#) }
            await #expect(throws: ProviderFailure.badResponse("my-store.myshopify.com: Bad Request")) {
                try await provider.fetch(credentials, window: window("revenue"), http: http)
            }
        }

        @Test("a null data with nothing to explain it still says which store")
        func noData() async {
            let (provider, http) = shopify { _ in .ok(#"{"data":null}"#) }
            await #expect(throws: ProviderFailure.badResponse("my-store.myshopify.com: no data")) {
                try await provider.fetch(credentials, window: window("revenue"), http: http)
            }
        }

        /// The token must never reach a host the manifest did not name, and the
        /// URL is the store's own domain rather than a global API host — so the
        /// normalisation above is what decides where the key goes.
        @Test("the request goes to the store's own Admin endpoint, with the token in the header")
        func endpoint() async throws {
            let (provider, http) = shopify { _ in .ok(ordersPage([])) }
            _ = try await provider.fetch(credentials, window: window("revenue"), http: http)

            let call = try #require(ShopifyStub.calls.first)
            #expect(
                call.request.url?.absoluteString
                    == "https://my-store.myshopify.com/admin/api/2026-10/graphql.json")
            #expect(call.request.httpMethod == "POST")
            #expect(
                call.request.value(forHTTPHeaderField: "x-shopify-access-token")
                    == "shpat_0123456789abcdef")
        }

        /// The catalogue is the Worker's and lists metrics this build has not
        /// been taught. Saying so is the contract, not a failure mode.
        @Test("a metric this build does not know says so rather than failing obscurely")
        func unknownMetric() async {
            let (provider, http) = shopify { _ in .ok(ordersPage([])) }
            await #expect(throws: ProviderFailure.unsupported(
                "This build cannot read Shopify's sessions yet.")) {
                try await provider.fetch(credentials, window: window("sessions"), http: http)
            }
        }
    }

    // MARK: - Sales, orders, AOV and refunds

    @Suite("shopify orders")
    struct ShopifyOrderTests {
        @Test("sales are the order totals in the window, in minor units")
        func revenue() async throws {
            let body = ordersPage([
                order("gid://shopify/Order/1", "2026-01-01T10:00:00Z", total: "12.34"),
                order("gid://shopify/Order/2", "2026-01-03T10:00:00Z", total: "7.66"),
            ])
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(credentials, window: window("revenue"), http: http)

            #expect(value.value == 2000)
            #expect(value.currency == "USD")
            #expect(value.points.count == 4)
            #expect(value.points[0].v == 1234)
            #expect(value.points[1].v == 0)
            #expect(value.points[2].v == 766)
            #expect(value.note == nil)
        }

        /// An authorisation can expire and a pending bank transfer can never
        /// arrive. Counting either as a sale makes today's revenue drift
        /// *downwards* over the following week.
        @Test("an unpaid order and a test order are not sales")
        func onlyPaid() async throws {
            let body = ordersPage([
                order("gid://shopify/Order/1", "2026-01-01T10:00:00Z", total: "10.00"),
                order("gid://shopify/Order/2", "2026-01-01T11:00:00Z", status: "AUTHORIZED"),
                order("gid://shopify/Order/3", "2026-01-01T12:00:00Z", status: "PENDING"),
                order("gid://shopify/Order/4", "2026-01-01T13:00:00Z", status: "VOIDED"),
                order("gid://shopify/Order/5", "2026-01-01T14:00:00Z", test: true),
                order("gid://shopify/Order/6", "2026-01-01T15:00:00Z", status: nil),
            ])
            let (provider, http) = shopify { _ in .ok(body) }

            #expect(
                try await provider.fetch(credentials, window: window("revenue"), http: http).value
                    == 1000)
            #expect(
                try await provider.fetch(credentials, window: window("orders"), http: http).value == 1)
        }

        /// A refunded order is still a sale on the day it was placed — gross, as
        /// the methodology promises, with the Refunds widget as the other half.
        @Test("a refund does not remove the order from the day it was placed")
        func gross() async throws {
            let body = ordersPage([
                order(
                    "gid://shopify/Order/1", "2026-01-01T10:00:00Z", total: "10.00", refunded: "4.00",
                    status: "PARTIALLY_REFUNDED"),
                order(
                    "gid://shopify/Order/2", "2026-01-02T10:00:00Z", total: "20.00", refunded: "20.00",
                    status: "REFUNDED"),
            ])
            let (provider, http) = shopify { _ in .ok(body) }

            #expect(
                try await provider.fetch(credentials, window: window("revenue"), http: http).value
                    == 3000)
            // Bucketed by the order's date rather than the refund's, so the two
            // widgets are about the same orders.
            let refunds = try await provider.fetch(
                credentials, window: window("refunds"), http: http)
            #expect(refunds.value == 2400)
            #expect(refunds.points[0].v == 400)
            #expect(refunds.points[1].v == 2000)
            #expect(refunds.currency == "USD")
        }

        /// An order with no refund has a null bag, not a zero one, and reading it
        /// as anything but zero would make Refunds mirror Sales.
        @Test("an order never refunded contributes nothing to refunds")
        func noRefunds() async throws {
            let body = ordersPage([order("gid://shopify/Order/1", "2026-01-01T10:00:00Z")])
            let (provider, http) = shopify { _ in .ok(body) }
            #expect(
                try await provider.fetch(credentials, window: window("refunds"), http: http).value == 0)
        }

        /// Counting rows, not money: a count labelled in a currency would have
        /// the tile format 14 orders as $0.14.
        @Test("orders is a count with no currency on it")
        func orders() async throws {
            let body = ordersPage([
                order("gid://shopify/Order/1", "2026-01-01T10:00:00Z"),
                order("gid://shopify/Order/2", "2026-01-01T11:00:00Z"),
                order("gid://shopify/Order/3", "2026-01-03T11:00:00Z"),
            ])
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(credentials, window: window("orders"), http: http)

            #expect(value.value == 3)
            #expect(value.currency == nil)
            #expect(value.points[0].v == 2)
            #expect(value.points[2].v == 1)
        }

        /// The headline is the window's own ratio, not the mean of the points: a
        /// Tuesday with one order would otherwise weigh as much as a Black Friday
        /// with three.
        @Test("average order value is the window's ratio, not the average of the daily ones")
        func averageOrderValue() async throws {
            let body = ordersPage([
                order("gid://shopify/Order/1", "2026-01-01T10:00:00Z", total: "10.00"),
                order("gid://shopify/Order/2", "2026-01-02T10:00:00Z", total: "30.00"),
                order("gid://shopify/Order/3", "2026-01-02T11:00:00Z", total: "30.00"),
                order("gid://shopify/Order/4", "2026-01-02T12:00:00Z", total: "30.00"),
            ])
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(
                credentials, window: window("average_order_value"), http: http)

            // 10000 over four orders, not the mean of 1000 and 3000.
            #expect(value.value == 2500)
            #expect(value.points[0].v == 1000)
            #expect(value.points[1].v == 3000)
            // Zero rather than NaN: a day with no orders has no average, and 0
            // renders.
            #expect(value.points[2].v == 0)
            #expect(value.currency == "USD")
        }

        @Test("an empty window averages to zero rather than to a NaN that renders as nothing")
        func emptyAverage() async throws {
            let (provider, http) = shopify { _ in .ok(ordersPage([])) }
            let value = try await provider.fetch(
                credentials, window: window("average_order_value"), http: http)
            #expect(value.value == 0)
            #expect(value.points.allSatisfy { $0.v == 0 })
        }

        /// `comparePrevious` widens the window backwards by its own length. The
        /// earlier half is `previousValue` and only the later half is `value` —
        /// get that the wrong way round and every delta is inverted.
        @Test("a comparison widens the window backwards and reports only the later half")
        func comparison() async throws {
            let body = ordersPage([
                order("gid://shopify/Order/new", "2026-01-03T10:00:00Z", total: "10.00"),
                order("gid://shopify/Order/old", "2026-01-02T10:00:00Z", total: "40.00"),
            ])
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(
                credentials,
                window: window(
                    "revenue", from: "2026-01-03T00:00:00Z", to: "2026-01-04T00:00:00Z",
                    comparePrevious: true),
                http: http)

            #expect(value.value == 1000)
            #expect(value.previousValue == 4000)
            // And the query asked for the widened window, or the earlier half
            // would be an empty comparison against a real figure.
            let body0 = try #require(ShopifyStub.calls.first?.body)
            #expect(body0.contains("created_at:>='2026-01-02T00:00:00"))
            #expect(body0.contains("created_at:<='2026-01-04T00:00:00"))
        }

        /// Opt-in, because it doubles the orders read — and a tile with no delta
        /// on it would be paying that for nothing.
        @Test("without a comparison there is no previous figure and no widening")
        func noComparison() async throws {
            let body = ordersPage([
                order("gid://shopify/Order/new", "2026-01-03T10:00:00Z", total: "10.00"),
                order("gid://shopify/Order/old", "2026-01-02T10:00:00Z", total: "40.00"),
            ])
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(
                credentials,
                window: window("revenue", from: "2026-01-03T00:00:00Z", to: "2026-01-04T00:00:00Z"),
                http: http)

            #expect(value.previousValue == nil)
            #expect(try #require(ShopifyStub.calls.first?.body)
                .contains("created_at:>='2026-01-03T00:00:00"))
        }

        @Test("a comparison on a count and on an average reports the earlier half too")
        func comparisonElsewhere() async throws {
            let body = ordersPage([
                order("gid://shopify/Order/new", "2026-01-03T10:00:00Z", total: "10.00"),
                order("gid://shopify/Order/old1", "2026-01-02T10:00:00Z", total: "40.00"),
                order("gid://shopify/Order/old2", "2026-01-02T11:00:00Z", total: "20.00"),
            ])
            let (provider, http) = shopify { _ in .ok(body) }
            let compared = window(
                "orders", from: "2026-01-03T00:00:00Z", to: "2026-01-04T00:00:00Z",
                comparePrevious: true)

            let orders = try await provider.fetch(credentials, window: compared, http: http)
            #expect(orders.value == 1)
            #expect(orders.previousValue == 2)

            let aov = try await provider.fetch(
                credentials,
                window: window(
                    "average_order_value", from: "2026-01-03T00:00:00Z", to: "2026-01-04T00:00:00Z",
                    comparePrevious: true), http: http)
            #expect(aov.value == 1000)
            #expect(aov.previousValue == 3000)
        }

        /// A tile with no chart on it still wants the headline, and the points
        /// are what nobody looks at.
        @Test("a tile that wants no chart gets the number without the points")
        func noSeries() async throws {
            let body = ordersPage([order("gid://shopify/Order/1", "2026-01-01T10:00:00Z")])
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(
                credentials, window: window("revenue", wantSeries: false), http: http)

            #expect(value.value == 1000)
            #expect(value.points.isEmpty)
        }

        /// A tile labelled in EUR next to one labelled in USD is confusing only
        /// until somebody explains why. `shopMoney` is already one currency — the
        /// store's — so there is nothing to exclude, and inventing a rate would
        /// be the kind of wrong that looks right.
        @Test("a store selling in another currency reports in it, and says so")
        func foreignCurrency() async throws {
            let body = ordersPage([
                order("gid://shopify/Order/1", "2026-01-01T10:00:00Z", total: "10.00", currency: "EUR")
            ])
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(
                credentials, window: window("revenue", currency: "USD"), http: http)

            #expect(value.value == 1000)
            #expect(value.currency == "EUR")
            #expect(
                value.note == "Totals are in the store's own currency, EUR, not USD.")
            // Nothing to say when the store already sells in the user's currency.
            let (same, sameHttp) = shopify { _ in .ok(body) }
            let home = window("revenue", currency: "EUR")
            #expect(try await same.fetch(credentials, window: home, http: sameHttp).note == nil)
        }

        /// Shopify paginates the GraphQL connection with a cursor in the body
        /// rather than with a `Link` header, so the walk follows `endCursor`.
        @Test("the walk follows the body's cursor to the next page")
        func paging() async throws {
            let (provider, http) = shopify { call in
                if call.index == 0 {
                    return .ok(
                        ordersPage(
                            [order("gid://shopify/Order/1", "2026-01-01T10:00:00Z", total: "10.00")],
                            hasNextPage: true, cursor: "cursor-A"))
                }
                return .ok(
                    ordersPage([
                        order("gid://shopify/Order/2", "2026-01-02T10:00:00Z", total: "20.00")
                    ]))
            }
            let value = try await provider.fetch(credentials, window: window("revenue"), http: http)

            #expect(value.value == 3000)
            #expect(ShopifyStub.calls.count == 2)
            #expect(ShopifyStub.calls[1].body.contains("cursor-A"))
            #expect(value.note == nil)
        }

        /// `hasNextPage` with no cursor would otherwise re-request the first page
        /// until the cap, five times over, and count every order five times.
        @Test("a next page with no cursor ends the walk rather than looping on it")
        func cursorlessNextPage() async throws {
            let body = ordersPage(
                [order("gid://shopify/Order/1", "2026-01-01T10:00:00Z", total: "10.00")],
                hasNextPage: true, cursor: nil)
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(credentials, window: window("revenue"), http: http)

            #expect(value.value == 1000)
            #expect(ShopifyStub.calls.count == 1)
        }

        /// The walk is bounded, and it *says so* rather than quietly reporting a
        /// fraction of a busy month as though it were all of it.
        @Test("hitting the page cap is an undercount the note names")
        func truncated() async throws {
            let body = ordersPage(
                [order("gid://shopify/Order/1", "2026-01-01T10:00:00Z", total: "10.00")],
                hasNextPage: true, cursor: "more")
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(credentials, window: window("revenue"), http: http)

            #expect(ShopifyStub.calls.count == 5)
            #expect(value.value == 5000)
            #expect(
                value.note == "Only the 600 most recent orders in the window were read, "
                    + "so this is an undercount.")
        }

        /// A throttle partway through is a bounded undercount, and that beats
        /// blanking a tile that already has most of the month in it.
        @Test("a throttle partway through reports what it has, and says how much")
        func throttledMidWalk() async throws {
            let (provider, http) = shopify { call in
                if call.index == 0 {
                    return .ok(
                        ordersPage(
                            [
                                order("gid://shopify/Order/1", "2026-01-01T10:00:00Z", total: "10.00"),
                                order("gid://shopify/Order/2", "2026-01-02T10:00:00Z", total: "20.00"),
                            ], hasNextPage: true, cursor: "cursor-A"))
                }
                return .ok(graphQLError("THROTTLED", "Throttled"))
            }
            let value = try await provider.fetch(credentials, window: window("revenue"), http: http)

            #expect(value.value == 3000)
            #expect(
                value.note
                    == "Shopify rate limited the request after 2 orders, so this is an undercount.")
        }

        /// Both notes at once, because a throttled store in another currency has
        /// two things worth saying and the tile shows one string.
        @Test("a currency note and an undercount note are said together")
        func bothNotes() async throws {
            let body = ordersPage(
                [order("gid://shopify/Order/1", "2026-01-01T10:00:00Z", currency: "EUR")],
                hasNextPage: true, cursor: "more")
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(credentials, window: window("revenue"), http: http)

            let note = try #require(value.note)
            #expect(note.contains("EUR"))
            #expect(note.contains("undercount"))
        }
    }

    // MARK: - Customers

    @Suite("shopify customers")
    struct ShopifyCustomerTests {
        @Test("new customers are the records created in the window")
        func newCustomers() async throws {
            let body = customersPage(["2026-01-01T10:00:00Z", "2026-01-03T10:00:00Z"])
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(
                credentials, window: window("new_customers"), http: http)

            #expect(value.value == 2)
            #expect(value.currency == nil)
            #expect(value.points[0].v == 1)
            #expect(value.points[2].v == 1)
            #expect(value.note == nil)
        }

        @Test("a comparison splits the widened window into the two halves")
        func comparison() async throws {
            let body = customersPage(["2026-01-03T10:00:00Z", "2026-01-02T10:00:00Z"])
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(
                credentials,
                window: window(
                    "new_customers", from: "2026-01-03T00:00:00Z", to: "2026-01-04T00:00:00Z",
                    comparePrevious: true), http: http)

            #expect(value.value == 1)
            #expect(value.previousValue == 1)
            #expect(try #require(ShopifyStub.calls.first?.body)
                .contains("created_at:>='2026-01-02T00:00:00"))
        }

        /// A walk that runs the cap out never gets a page saying it was the last
        /// one, and a store with more customers than that would otherwise read as
        /// a complete figure.
        @Test("hitting the customer page cap is an undercount the note names")
        func truncated() async throws {
            let body = customersPage(
                ["2026-01-01T10:00:00Z"], hasNextPage: true, cursor: "more")
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(
                credentials, window: window("new_customers"), http: http)

            #expect(ShopifyStub.calls.count == 4)
            #expect(
                value.note == "Only the first 1000 customers in the window were read, "
                    + "so this is an undercount.")
        }

        @Test("the total is whatever Shopify counts right now")
        func total() async throws {
            let (provider, http) = shopify { _ in
                .ok(#"{"data":{"customersCount":{"count":4821,"precision":"EXACT"}}}"#)
            }
            let value = try await provider.fetch(credentials, window: window("customers"), http: http)

            #expect(value.value == 4821)
            #expect(value.note == nil)
            #expect(ShopifyStub.calls.count == 1)
        }

        /// Shopify stops counting at ten thousand. Passing that on matters: the
        /// tile is otherwise a store's growth flatlining at exactly 10,000 with
        /// no explanation.
        @Test("a count Shopify will only give as a floor says so")
        func atLeast() async throws {
            let (provider, http) = shopify { _ in
                .ok(#"{"data":{"customersCount":{"count":10000,"precision":"AT_LEAST"}}}"#)
            }
            let value = try await provider.fetch(credentials, window: window("customers"), http: http)

            #expect(value.value == 10000)
            #expect(
                value.note == "Shopify reports this as a floor rather than an exact count "
                    + "above ten thousand.")
        }

        @Test("a store Shopify counted as nothing is zero rather than an error")
        func none() async throws {
            let (provider, http) = shopify { _ in .ok(#"{"data":{"customersCount":null}}"#) }
            #expect(
                try await provider.fetch(credentials, window: window("customers"), http: http).value
                    == 0)
        }
    }

    // MARK: - The payments feed

    @Suite("shopify payments")
    struct ShopifyPaymentTests {
        @Test("rows carry the buyer, the first product and the amount in minor units")
        func rows() async throws {
            let body = recentOrders([
                order("gid://shopify/Order/1", "2026-01-03T10:00:00Z", total: "24.99")
            ])
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(
                credentials, window: window("recent_payments"), http: http)

            let items = try #require(value.items)
            #expect(items.count == 1)
            #expect(items[0].id == "gid://shopify/Order/1")
            #expect(items[0].label == "Ada Lovelace")
            #expect(items[0].detail == "Pro plan")
            #expect(items[0].amount == 2499)
            #expect(items[0].currency == "USD")
            #expect(items[0].status == "paid")
            // A payment is not pass or fail. It just happened.
            #expect(items[0].state == nil)
            #expect(items[0].date == date("2026-01-03T10:00:00Z"))
            // Twice the limit is asked for, because the unpaid rows are filtered
            // here rather than by Shopify.
            #expect(try #require(ShopifyStub.calls.first?.body).contains("\"first\":20"))
        }

        /// The order number is the fallback rather than "Customer": every Shopify
        /// order has one, it is what the merchant searches by, and a list of ten
        /// rows all reading "Customer" identifies nothing.
        @Test("the email stands in for a missing name, and the order number for both")
        func labels() async throws {
            let body = recentOrders([
                order(
                    "gid://shopify/Order/1", "2026-01-03T10:00:00Z", customer: nil,
                    email: "ada@example.com"),
                order("gid://shopify/Order/2", "2026-01-02T10:00:00Z", name: "#1002", customer: ""),
            ])
            let (provider, http) = shopify { _ in .ok(body) }
            let items = try #require(
                try await provider.fetch(credentials, window: window("recent_payments"), http: http)
                    .items)

            #expect(items[0].label == "ada@example.com")
            #expect(items[1].label == "#1002")
        }

        /// Ten is what the tallest tile shows, and the cap is applied after the
        /// paid filter rather than before it.
        @Test("newest first, ten at most, and never an unpaid row")
        func sortedAndCapped() async throws {
            var nodes = (1...12).map { index in
                order(
                    "gid://shopify/Order/\(index)",
                    String(format: "2026-01-02T%02d:00:00Z", index))
            }
            nodes.append(
                order("gid://shopify/Order/pending", "2026-01-03T23:00:00Z", status: "PENDING"))
            let body = recentOrders(nodes)
            let (provider, http) = shopify { _ in .ok(body) }
            let items = try #require(
                try await provider.fetch(credentials, window: window("recent_payments"), http: http)
                    .items)

            #expect(items.count == 10)
            #expect(items.first?.id == "gid://shopify/Order/12")
            #expect(items.map(\.id).contains("gid://shopify/Order/pending") == false)
            #expect(items.map(\.id).contains("gid://shopify/Order/1") == false)
        }

        /// A store sells in exactly one currency, and it is usually not the one
        /// the notch was told to prefer. Totalling in the user's filters every row
        /// out and the tile reads zero beside a list of ten sales.
        @Test("the headline is totalled in the store's currency, not the user's")
        func storeCurrency() async throws {
            let body = recentOrders([
                order("gid://shopify/Order/1", "2026-01-03T10:00:00Z", total: "15.00", currency: "EUR"),
                order("gid://shopify/Order/2", "2026-01-03T09:00:00Z", total: "7.00", currency: "EUR"),
            ])
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(
                credentials, window: window("recent_payments", currency: "USD"), http: http)

            #expect(value.value == 2200)
            #expect(value.currency == "EUR")
            #expect(value.note == "Totals are in the store's own currency, EUR, not USD.")
            #expect(try #require(value.items).count == 2)
            // One point, timestamped now: a feed has no window, so there is no
            // chart to draw.
            #expect(value.points.count == 1)
            #expect(value.points[0].v == 2200)
        }

        /// Rows in another currency are listed with their own code rather than
        /// dropped, because a list can show a currency where a sum cannot.
        @Test("a row in another currency is listed but not totalled")
        func mixed() async throws {
            let body = recentOrders([
                order("gid://shopify/Order/1", "2026-01-03T10:00:00Z", total: "15.00"),
                order("gid://shopify/Order/2", "2026-01-03T09:00:00Z", total: "90.00", currency: "JPY"),
            ])
            let (provider, http) = shopify { _ in .ok(body) }
            let value = try await provider.fetch(
                credentials, window: window("recent_payments"), http: http)

            #expect(value.value == 1500)
            #expect(try #require(value.items)[1].currency == "JPY")
            #expect(try #require(value.items)[1].amount == 90)
        }

        @Test("a store with no paid orders yet is an empty feed rather than an error")
        func empty() async throws {
            let (provider, http) = shopify { _ in .ok(recentOrders([])) }
            let value = try await provider.fetch(
                credentials, window: window("recent_payments"), http: http)

            #expect(value.value == 0)
            #expect(try #require(value.items).isEmpty)
            #expect(value.currency == "USD")
        }
    }

    // MARK: - Verify

    @Suite("shopify verify")
    struct ShopifyVerifyTests {
        @Test("a token that reads both offers everything, and names the shop and its currency")
        func everything() async throws {
            let (provider, http) = shopify { _ in
                .ok("""
                    {"data":{"shop":{"name":"Ada's Looms","currencyCode":"gbp",
                     "myshopifyDomain":"my-store.myshopify.com"},
                     "ordersCount":{"count":12},"customersCount":{"count":4}}}
                    """)
            }
            let account = try await provider.verify(credentials, http: http)

            #expect(account.label == "Ada's Looms")
            #expect(account.currency == "GBP")
            #expect(account.unavailableMetrics.isEmpty)
            // One round trip, which is the whole point of the combined query.
            #expect(ShopifyStub.calls.count == 1)
        }

        /// A token missing `read_customers` returns the shop and a null
        /// `customersCount` beside an ACCESS_DENIED. Narrowing what is offered
        /// beats rejecting a key that reads orders perfectly well.
        @Test("a token missing one scope keeps the connection and withholds those metrics")
        func partial() async throws {
            let (provider, http) = shopify { _ in
                .ok("""
                    {"data":{"shop":{"name":"Ada's Looms","currencyCode":"GBP",
                     "myshopifyDomain":"my-store.myshopify.com"},
                     "ordersCount":{"count":12},"customersCount":null},
                     "errors":[{"message":"Access denied for customersCount field.",
                     "extensions":{"code":"ACCESS_DENIED"}}]}
                    """)
            }
            let account = try await provider.verify(credentials, http: http)

            #expect(account.unavailableMetrics == ["customers", "new_customers"])
            #expect(account.label == "Ada's Looms")
        }

        @Test("and the other way round, where only the customer metrics survive")
        func ordersMissing() async throws {
            let (provider, http) = shopify { _ in
                .ok("""
                    {"data":{"shop":{"name":"Ada's Looms","currencyCode":"GBP",
                     "myshopifyDomain":"my-store.myshopify.com"},
                     "ordersCount":null,"customersCount":{"count":4}},
                     "errors":[{"message":"Access denied","extensions":{"code":"ACCESS_DENIED"}}]}
                    """)
            }
            let account = try await provider.verify(credentials, http: http)

            #expect(
                account.unavailableMetrics == [
                    "revenue", "orders", "average_order_value", "refunds", "recent_payments",
                ])
        }

        /// A token with neither scope would otherwise be stored as a connection
        /// that answers nothing, and every tile on it would fail at poll time.
        @Test("a token that reads neither is refused, and says which scopes to add")
        func neither() async {
            let (provider, http) = shopify { _ in
                .ok("""
                    {"data":{"shop":{"name":"Ada's Looms","currencyCode":"GBP",
                     "myshopifyDomain":"my-store.myshopify.com"},
                     "ordersCount":null,"customersCount":null},
                     "errors":[{"message":"Access denied","extensions":{"code":"ACCESS_DENIED"}}]}
                    """)
            }
            await #expect(throws: ProviderFailure.authFailed(
                "This token can read neither orders nor customers. Add the read_orders and "
                    + "read_customers scopes to the app, then reinstall it.")) {
                try await provider.verify(credentials, http: http)
            }
        }

        @Test("a shop Shopify would not even name is a rejected token")
        func noShop() async {
            let (provider, http) = shopify { _ in
                .ok(#"{"data":{"shop":null,"ordersCount":null,"customersCount":null}}"#)
            }
            await #expect(throws: ProviderFailure.authFailed(
                "my-store.myshopify.com rejected the token, or the app it belongs to "
                    + "has no API access.")) {
                try await provider.verify(credentials, http: http)
            }
        }

        /// The handle, not the whole domain: it is what the merchant calls the
        /// store, and a connection list reading "my-store.myshopify.com" is the
        /// URL rather than the name.
        @Test("a store with no name falls back to its handle")
        func unnamed() async throws {
            let (provider, http) = shopify { _ in
                .ok("""
                    {"data":{"shop":{"name":"","currencyCode":null,
                     "myshopifyDomain":"my-store.myshopify.com"},
                     "ordersCount":{"count":0},"customersCount":{"count":0}}}
                    """)
            }
            let account = try await provider.verify(credentials, http: http)

            #expect(account.label == "my-store")
            #expect(account.currency == nil)
        }

        @Test("a bad domain never reaches the network")
        func badDomain() async {
            let (provider, http) = shopify { _ in .ok(#"{"data":{}}"#) }
            await #expect(throws: ProviderFailure.self) {
                try await provider.verify(
                    ["shop_domain": "shop.example.com", "access_token": "shpat_abc"], http: http)
            }
            #expect(ShopifyStub.calls.isEmpty)
        }
    }
}
