import Foundation
import MetricsCore
import Testing

@testable import Providers

/// Polar's statuses, in the buckets the caller acts differently on.
///
/// Tested through `failure(for:)` rather than over the network: what is worth
/// pinning is which bucket each status lands in, and that a token missing one
/// scope does not mark the whole connection broken./// Polar's suites, nested under one serialized parent.
///
/// `PolarStub` is a `URLProtocol` holding its routes in static state, and Swift
/// Testing runs top-level suites in parallel. Marking the stub-using suites
/// `.serialized` individually orders each one internally but does nothing
/// between them, so they still read each other's queued responses — which
/// surfaces as "no stub" on a test whose own routes were installed correctly.
/// `.serialized` on a parent orders its children, which is the level the
/// guarantee is actually needed at.
@Suite(.serialized)
struct PolarTests {
@Suite("polar failures")
struct PolarFailureTests {
    private func response(_ status: Int, body: String = "", headers: [String: String] = [:])
        -> ProviderHTTP.Response
    {
        ProviderHTTP.Response(status: status, headers: headers, body: Data(body.utf8))
    }

    @Test("a rejected token is an auth failure, and carries Polar's own words")
    func badToken() {
        let failure = PolarProvider.failure(
            for: response(401, body: #"{"detail":"Invalid token"}"#))
        #expect(failure == .authFailed("Invalid token"))
    }

    /// The one worth being deliberate about. A Polar token carries any subset
    /// of the scopes, so a 403 is a statement about one endpoint; calling it an
    /// auth failure would ask the user to replace a token that answers
    /// everything else.
    @Test("a missing scope is unsupported, not an auth failure")
    func missingScope() {
        let failure = PolarProvider.failure(
            for: response(403, body: #"{"detail":"Missing required scope: orders:read"}"#))
        #expect(failure == .unsupported("Missing required scope: orders:read"))
    }

    @Test("a spent quota carries the wait Polar asked for")
    func rateLimited() {
        let failure = PolarProvider.failure(for: response(429, headers: ["Retry-After": "30"]))
        #expect(failure == .rateLimited("Polar's rate limit is spent.", retryAfter: 30))
    }

    /// A nil wait would have the refresh loop retry on its own tick, which on
    /// a spent quota is immediately.
    @Test("and a minute when it asked for nothing")
    func rateLimitedSilently() {
        let failure = PolarProvider.failure(for: response(429))
        #expect(failure == .rateLimited("Polar's rate limit is spent.", retryAfter: 60))
    }

    @Test("a 5xx is their outage, retried rather than reported as a bad token")
    func down() {
        #expect(PolarProvider.failure(for: response(503)) == .providerDown("Polar is having trouble."))
    }

    /// Polar is FastAPI, so a bad parameter comes back as a 422 that names it.
    @Test("any other 4xx keeps the explanation Polar sent")
    func explained() {
        let failure = PolarProvider.failure(
            for: response(422, body: #"{"detail":"interval: value is not a valid enumeration member"}"#))
        #expect(
            failure == .badResponse("interval: value is not a valid enumeration member"))
    }

    @Test("and says the status when it sent none")
    func unexplained() {
        #expect(PolarProvider.failure(for: response(418)) == .badResponse("Polar returned 418."))
    }

    /// A FastAPI validation error puts an array of objects in `detail`. Pasting
    /// that into a notch tile is worse than the bare status it replaces.
    @Test("a detail that is not a string is dropped rather than rendered raw")
    func structuredDetail() {
        let body = #"{"detail":[{"loc":["query","interval"],"msg":"field required"}]}"#
        #expect(PolarProvider.failure(for: response(400, body: body)) == .badResponse("Polar returned 400."))
    }

    @Test("other error shapes are read in the Worker's order")
    func shapes() {
        #expect(
            PolarProvider.message(in: Data(#"{"error":{"message":"nested"}}"#.utf8)) == "nested")
        #expect(PolarProvider.message(in: Data(#"{"message":"flat"}"#.utf8)) == "flat")
        #expect(
            PolarProvider.message(in: Data(#"{"error_description":"oauth"}"#.utf8)) == "oauth")
        #expect(PolarProvider.message(in: Data("not json at all".utf8)) == nil)
    }

    /// The failure this prevents is a user's own access token ending up on
    /// screen, and from there in a screenshot in a support thread.
    @Test("a token Polar quoted back is redacted")
    func redacted() {
        let body = #"{"detail":"Token polar_oat_AbC123-xyz is revoked"}"#
        #expect(PolarProvider.message(in: Data(body.utf8)) == "Token polar_… is revoked")
    }

    /// Console deep links run to a couple of hundred characters of account id
    /// and query string, and cutting out just the URL leaves "Fix this at ."
    @Test("a sentence containing a link goes whole")
    func links() {
        let body = #"{"detail":"Missing scope. Grant it at https://polar.sh/dashboard/settings."}"#
        #expect(PolarProvider.message(in: Data(body.utf8)) == "Missing scope.")
    }
}

@Suite("polar credentials")
struct PolarCredentialTests {
    /// The form will not submit an empty required field, so this is a bug
    /// rather than user error — but it reaches a live API either way, and an
    /// empty bearer token reads back as a revoked key.
    @Test("a missing access token is refused before any request is made")
    func missing() {
        #expect(throws: ProviderFailure.self) { try PolarProvider.credentials([:]) }
        #expect(throws: ProviderFailure.self) {
            try PolarProvider.credentials(["access_token": "   "])
        }
    }

    /// Both environments issue `polar_oat_` tokens, so the host cannot be
    /// inferred from the token: a production token sent to the sandbox answers
    /// 401, which reads as a revoked key.
    @Test("the host follows the stored mode, not the token")
    func mode() throws {
        let token = "polar_oat_abcdefghijklmnopqrst"
        #expect(try PolarProvider.credentials(["access_token": token]).host == "api.polar.sh")
        #expect(
            try PolarProvider.credentials(["access_token": token, "mode": "production"]).host
                == "api.polar.sh")
        #expect(
            try PolarProvider.credentials(["access_token": token, "mode": "sandbox"]).host
                == "sandbox-api.polar.sh")
        // An unrecognised mode is production, matching the manifest's default.
        #expect(
            try PolarProvider.credentials(["access_token": token, "mode": "staging"]).host
                == "api.polar.sh")
    }

    @Test("both of the manifest's hosts are reachable and nothing else is")
    func allowlist() {
        let hosts = PolarProvider().allowedHosts
        #expect(ProviderHTTP.hostAllowed("api.polar.sh", in: hosts))
        #expect(ProviderHTTP.hostAllowed("sandbox-api.polar.sh", in: hosts))
        #expect(!ProviderHTTP.hostAllowed("polar.sh", in: hosts))
    }

    @Test("the organization's currency is the one Polar reports metrics in")
    func currency() throws {
        let decode = { (json: String) in
            try JSONDecoder().decode(PolarProvider.Organization.self, from: Data(json.utf8))
        }
        #expect(
            PolarProvider.currency(
                of: try decode(
                    #"{"id":"org_1","name":"Acme","default_presentment_currency":"eur"}"#)) == "EUR")
        // Polar omits the field on an organization that has taken no money.
        #expect(
            PolarProvider.currency(of: try decode(#"{"id":"org_1","name":"Acme"}"#)) == "USD")
    }
}

@Suite("polar helpers")
struct PolarHelperTests {
    private let utc = TimeZone(identifier: "UTC")!

    @Test("a day is formatted in the zone the request names")
    func isoDay() {
        // 23:00 UTC is already the next day in Tokyo, and Polar buckets by the
        // zone it is given — so the two have to agree or the window is off by
        // a day at its edges.
        let instant = PolarProvider.instant("2026-01-01T23:00:00Z", timeZone: utc)!
        #expect(PolarProvider.isoDay(instant, timeZone: utc) == "2026-01-01")
        #expect(
            PolarProvider.isoDay(instant, timeZone: TimeZone(identifier: "Asia/Tokyo")!)
                == "2026-01-02")
    }

    /// Each of these is a shape Polar actually sends. `/orders/` carries
    /// FastAPI's microseconds; a period start can arrive with no zone at all.
    @Test("every timestamp shape Polar sends is read")
    func instants() {
        #expect(PolarProvider.instant("2026-01-01T00:00:00Z", timeZone: utc) != nil)
        #expect(PolarProvider.instant("2026-01-01T00:00:00+00:00", timeZone: utc) != nil)
        #expect(PolarProvider.instant("2026-01-01T00:00:00.123456Z", timeZone: utc) != nil)
        #expect(PolarProvider.instant("2026-01-01T00:00:00.123456", timeZone: utc) != nil)
        #expect(PolarProvider.instant("2026-01-01T00:00:00", timeZone: utc) != nil)
        #expect(PolarProvider.instant("2026-01-01", timeZone: utc) != nil)
        #expect(PolarProvider.instant("whenever", timeZone: utc) == nil)

        // A zone-less period start is read in the zone the request asked Polar
        // to bucket in, which is the zone those starts are expressed in.
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(
            PolarProvider.instant("2026-01-01T00:00:00", timeZone: tokyo)
                == PolarProvider.instant("2025-12-31T15:00:00Z", timeZone: utc))
    }

    @Test("a status is read as words, and only its first underscore goes")
    func status() {
        #expect(PolarProvider.humanStatus("paid") == "paid")
        #expect(PolarProvider.humanStatus("partially_refunded") == "partially refunded")
    }

    /// The Worker's `||` chain falls through an empty string; `??` would stop
    /// at it and label a row with nothing.
    @Test("an empty string is a missing field, not a label")
    func empties() {
        #expect(PolarProvider.nonEmpty("") == nil)
        #expect(PolarProvider.nonEmpty("  ") == nil)
        #expect(PolarProvider.nonEmpty(nil) == nil)
        #expect(PolarProvider.nonEmpty("Ada") == "Ada")
    }
}

/// The arithmetic, over a stubbed session.
///
/// Serialised because the stub's routing table is static: `URLProtocol` is
/// instantiated by `URLSession` and there is nowhere to hand per-test state.
@Suite("polar metrics", .serialized)
struct PolarMetricTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ iso: String) -> Date {
        PolarProvider.instant(iso, timeZone: TimeZone(identifier: "UTC")!)!
    }

    private func window(
        _ metric: String, from: String = "2026-01-08T00:00:00Z", to: String = "2026-01-15T00:00:00Z",
        granularity: Granularity = .day, wantSeries: Bool = true, compare: Bool = true,
        currency: String = "USD"
    ) -> MetricWindow {
        MetricWindow(
            metric: metric, from: date(from), to: date(to), granularity: granularity,
            wantSeries: wantSeries, comparePrevious: compare, timeZone: utc,
            preferredCurrency: currency)
    }

    private func fetch(
        _ window: MetricWindow, mode: String = "production"
    ) async throws -> MetricValue {
        try await PolarProvider().fetch(
            ["access_token": "polar_oat_abcdefghijklmnopqrst", "mode": mode],
            window: window, http: ProviderHTTP(allowedHosts: PolarProvider().allowedHosts,
                                               session: PolarStub.session()))
    }

    private static let organization = #"""
        {"items":[{"id":"org_1","name":"Acme","default_presentment_currency":"eur"}]}
        """#

    /// A window and its previous one come back in one call, split here by
    /// timestamp. Halving the calls matters on an endpoint with a per-minute
    /// budget, and getting the boundary wrong moves a day's revenue into the
    /// comparison.
    @Test("one call covers the window and the one before it")
    func revenueSplit() async throws {
        PolarStub.reset(
            routes: [
                "/v1/organizations/": (200, Self.organization),
                "/v1/metrics/": (
                    200,
                    #"""
                    {"periods":[
                      {"timestamp":"2026-01-06T00:00:00Z","revenue":100},
                      {"timestamp":"2026-01-07T00:00:00Z","revenue":200},
                      {"timestamp":"2026-01-08T00:00:00Z","revenue":1000},
                      {"timestamp":"2026-01-09T00:00:00Z","revenue":2000},
                      {"timestamp":"2026-01-10T00:00:00Z","revenue":null}
                    ]}
                    """#
                ),
            ])

        let value = try await fetch(window("revenue"))

        #expect(value.value == 3000)
        #expect(value.previousValue == 300)
        // The organization's currency, which the metrics response does not
        // carry. Not the user's preferred one: Polar reports in its own.
        #expect(value.currency == "EUR")
        // Polar's own buckets, including the null one as a zero, so a chart
        // does not draw a line straight over a day with no revenue.
        #expect(value.points.count == 3)
        #expect(value.points.map(\.v) == [1000, 2000, 0])

        // The span asked for starts a window earlier than the widget's.
        let query = PolarStub.query(for: "/v1/metrics/")
        #expect(query["start_date"] == "2026-01-01")
        #expect(query["end_date"] == "2026-01-15")
        #expect(query["interval"] == "day")
        // The zone as `TimeZone` names it, which for UTC is "GMT". Both are
        // IANA zones Polar accepts; what matters is that the zone the window
        // was resolved in is the zone Polar buckets in.
        #expect(query["timezone"] == utc.identifier)
        // One metric per call, on an endpoint that would otherwise compute
        // fifty-odd figures.
        #expect(query["metrics"] == "revenue")
    }

    /// The other side of the flag, and the reason `previousValue` is nil
    /// rather than zero: a tile handed zero draws "down 100%" against a window
    /// the fetch never looked at. The narrower span is the point too — Polar
    /// would otherwise compute twice the periods for a figure nobody reads.
    @Test("a tile with no delta asks only for its own window")
    func noComparison() async throws {
        PolarStub.reset(
            routes: [
                "/v1/organizations/": (200, Self.organization),
                "/v1/metrics/": (
                    200,
                    #"""
                    {"periods":[
                      {"timestamp":"2026-01-08T00:00:00Z","revenue":1000},
                      {"timestamp":"2026-01-09T00:00:00Z","revenue":2000}
                    ]}
                    """#
                ),
            ])

        let value = try await fetch(window("revenue", compare: false))

        #expect(value.value == 3000)
        #expect(value.previousValue == nil)
        #expect(PolarStub.query(for: "/v1/metrics/")["start_date"] == "2026-01-08")
    }

    /// `start_date` is a day, so a window opening mid-afternoon comes back
    /// with that morning's period attached whether a comparison was asked for
    /// or not. Counting it would overstate the figure by whatever happened
    /// before the window opened.
    @Test("a period before the window is left out either way")
    func beforeTheWindow() async throws {
        let periods = #"""
            {"periods":[
              {"timestamp":"2026-01-08T00:00:00Z","revenue":400},
              {"timestamp":"2026-01-08T12:00:00Z","revenue":1000}
            ]}
            """#
        let afternoon = window(
            "revenue", from: "2026-01-08T12:00:00Z", to: "2026-01-08T18:00:00Z",
            granularity: .hour, compare: false)

        PolarStub.reset(
            routes: ["/v1/organizations/": (200, Self.organization), "/v1/metrics/": (200, periods)])
        var value = try await fetch(afternoon)
        #expect(value.value == 1000)
        #expect(value.previousValue == nil)

        // The same row, now that there is a previous window for it to land in.
        PolarStub.reset(
            routes: ["/v1/organizations/": (200, Self.organization), "/v1/metrics/": (200, periods)])
        value = try await fetch(
            window(
                "revenue", from: "2026-01-08T12:00:00Z", to: "2026-01-08T18:00:00Z",
                granularity: .hour, compare: true))
        #expect(value.value == 1000)
        #expect(value.previousValue == 400)
    }

    @Test("a tile with no chart gets the figure without the points")
    func noSeries() async throws {
        PolarStub.reset(
            routes: [
                "/v1/organizations/": (200, Self.organization),
                "/v1/metrics/": (
                    200,
                    #"{"periods":[{"timestamp":"2026-01-09T00:00:00Z","revenue":2000}]}"#
                ),
            ])

        let value = try await fetch(window("revenue", wantSeries: false))
        #expect(value.value == 2000)
        #expect(value.points.isEmpty)
    }

    /// Polar's pipeline leaves the last few periods null while it catches up.
    /// Taking the last period rather than the last *valued* one shows zero MRR
    /// at midnight.
    @Test("a snapshot is the latest period Polar has a value for")
    func mrrSkipsNulls() async throws {
        PolarStub.reset(
            routes: [
                "/v1/organizations/": (200, Self.organization),
                "/v1/metrics/": (
                    200,
                    #"""
                    {"periods":[
                      {"timestamp":"2026-01-12T00:00:00Z","monthly_recurring_revenue":41000},
                      {"timestamp":"2026-01-13T00:00:00Z","monthly_recurring_revenue":42000},
                      {"timestamp":"2026-01-14T00:00:00Z","monthly_recurring_revenue":null},
                      {"timestamp":"2026-01-15T00:00:00Z","monthly_recurring_revenue":null}
                    ]}
                    """#
                ),
            ])

        let value = try await fetch(window("mrr", granularity: .month))
        #expect(value.value == 42000)
        #expect(value.currency == "EUR")
        // A snapshot has no window, so no comparison and no chart — and the
        // window above asks for a comparison, which a scalar has nowhere to
        // put. The descriptors agree: `mrr` declares no `compare`.
        #expect(value.previousValue == nil)
        #expect(value.points.isEmpty)
        // A week of days, whatever the widget's range says: the answer to
        // "what is MRR" is "now", not "this month so far".
        #expect(PolarStub.query(for: "/v1/metrics/")["interval"] == "day")
    }

    /// A count is not money. Asking for the organization would be a wasted
    /// call, and a currency on the answer would have the tile render 412 as
    /// €4.12.
    @Test("a count carries no currency and costs no extra call")
    func activeSubscribers() async throws {
        PolarStub.reset(
            routes: [
                "/v1/metrics/": (
                    200,
                    #"{"periods":[{"timestamp":"2026-01-14T00:00:00Z","active_subscriptions":412}]}"#
                )
            ])

        let value = try await fetch(window("active_subscribers"))
        #expect(value.value == 412)
        #expect(value.currency == nil)
        #expect(PolarStub.paths == ["/v1/metrics/"])
    }

    @Test("a metric this build does not read says so rather than failing obscurely")
    func notPorted() async {
        PolarStub.reset(routes: [:])
        await #expect(throws: ProviderFailure.self) { try await fetch(window("refunds")) }
    }

    /// The host follows the stored mode. A production token against the
    /// sandbox answers 401, which reads as a revoked key.
    @Test("the sandbox mode talks to the sandbox host")
    func sandbox() async throws {
        PolarStub.reset(
            routes: [
                "/v1/metrics/": (
                    200,
                    #"{"periods":[{"timestamp":"2026-01-14T00:00:00Z","new_subscriptions":3}]}"#
                )
            ])

        _ = try await fetch(window("new_subscribers"), mode: "sandbox")
        #expect(PolarStub.hosts == ["sandbox-api.polar.sh"])
    }

    // MARK: - The payments feed

    /// The shape nothing had exercised. Four things are being pinned at once
    /// because they are all ways the feed goes wrong quietly: an unpaid order
    /// counted, the rows in the wrong order, a mixed-currency book summed, and
    /// the headline reported as the row count.
    @Test("the feed is paid orders, newest first, totalled in one currency")
    func recentPayments() async throws {
        PolarStub.reset(
            routes: [
                "/v1/orders/": (
                    200,
                    #"""
                    {"items":[
                      {"id":"o1","created_at":"2026-01-10T09:00:00.123456Z","status":"paid",
                       "total_amount":2500,"currency":"usd",
                       "customer":{"name":"Ada Lovelace","email":"ada@example.com"},
                       "product":{"name":"Pro yearly"}},
                      {"id":"o2","created_at":"2026-01-12T09:00:00Z","status":"pending",
                       "total_amount":9900,"currency":"usd","customer":{"name":"Never Paid"}},
                      {"id":"o3","created_at":"2026-01-11T09:00:00Z","status":"partially_refunded",
                       "total_amount":1000,"currency":"usd","customer":{"name":"","email":"grace@example.com"},
                       "description":"Consulting"},
                      {"id":"o4","created_at":"2026-01-09T09:00:00Z","status":"refunded",
                       "total_amount":4200,"currency":"eur","customer":{},"product":{"name":"Pro monthly"}},
                      {"id":"o5","created_at":"2026-01-08T09:00:00Z","status":"void",
                       "total_amount":100,"currency":"usd"}
                    ]}
                    """#
                )
            ])

        let value = try await fetch(window("recent_payments"))
        let items = try #require(value.items)

        #expect(items.map(\.id) == ["o3", "o1", "o4"])
        // Minor units, never divided by 100.
        #expect(items.map(\.amount) == [1000, 2500, 4200])
        #expect(items.map(\.currency) == ["USD", "USD", "EUR"])
        #expect(items.map(\.status) == ["partially refunded", "paid", "refunded"])
        // The name, then the email, then a last resort. An empty name falls
        // through rather than labelling a row with nothing.
        #expect(items.map(\.label) == ["grace@example.com", "Ada Lovelace", "Customer"])
        #expect(items.map(\.detail) == ["Consulting", "Pro yearly", "Pro monthly"])
        // A payment is not pass or fail; it happened.
        #expect(items.allSatisfy { $0.state == nil })

        // The headline is the rows in the user's own currency: not the row
        // count, and not dollars added to euros.
        #expect(value.value == 3500)
        #expect(value.currency == "USD")
        // A feed has no window, so nothing to compare it against.
        #expect(value.previousValue == nil)
        #expect(value.points.map(\.v) == [3500])

        // Twice the limit, because the unpaid rows are filtered here rather
        // than by Polar: ten pending orders would otherwise empty the feed.
        let query = PolarStub.query(for: "/v1/orders/")
        #expect(query["limit"] == "20")
        #expect(query["sorting"] == "-created_at")
    }

    @Test("the feed is capped at ten rows whatever Polar returns")
    func capped() async throws {
        let orders = (1...14).map { index in
            #"{"id":"o\#(index)","created_at":"2026-01-\#(String(format: "%02d", index))T09:00:00Z","#
                + #""status":"paid","total_amount":100,"currency":"usd"}"#
        }
        PolarStub.reset(routes: ["/v1/orders/": (200, #"{"items":[\#(orders.joined(separator: ","))]}"#)])

        let value = try await fetch(window("recent_payments"))
        let items = try #require(value.items)
        #expect(items.count == 10)
        // The newest ten, not the first ten Polar listed.
        #expect(items.first?.id == "o14")
        #expect(items.last?.id == "o5")
        #expect(value.value == 1000)
    }

    @Test("an empty book is a feed with no rows rather than an error")
    func emptyFeed() async throws {
        PolarStub.reset(routes: ["/v1/orders/": (200, #"{"items":[]}"#)])
        let value = try await fetch(window("recent_payments"))
        #expect(value.items?.isEmpty == true)
        #expect(value.value == 0)
    }
}

@Suite("polar verify", .serialized)
struct PolarVerifyTests {
    private func verify(_ mode: String = "production") async throws -> ProviderAccount {
        try await PolarProvider().verify(
            ["access_token": "polar_oat_abcdefghijklmnopqrst", "mode": mode],
            http: ProviderHTTP(
                allowedHosts: PolarProvider().allowedHosts, session: PolarStub.session()))
    }

    private static let organization = #"""
        {"items":[{"id":"org_1","name":"Acme","default_presentment_currency":"usd"}]}
        """#

    @Test("a token with every scope offers every metric")
    func fullScopes() async throws {
        PolarStub.reset(
            routes: [
                "/v1/organizations/": (200, Self.organization),
                "/v1/metrics/limits": (200, "{}"),
                "/v1/orders/": (200, #"{"items":[]}"#),
            ])

        let account = try await verify()
        #expect(account.label == "Acme")
        #expect(account.currency == "USD")
        #expect(account.unavailableMetrics.isEmpty)
    }

    /// Narrowing what is offered beats refusing the connection and telling
    /// somebody their perfectly good token is broken. Offering the feed anyway
    /// would put a tile on the grid that fails on every poll.
    @Test("a token without orders:read keeps everything but the feed")
    func missingOrdersScope() async throws {
        PolarStub.reset(
            routes: [
                "/v1/organizations/": (200, Self.organization),
                "/v1/metrics/limits": (200, "{}"),
                "/v1/orders/": (403, #"{"detail":"Missing required scope: orders:read"}"#),
            ])

        let account = try await verify()
        #expect(account.unavailableMetrics == ["recent_payments"])
    }

    @Test("a token without metrics:read keeps only the feed")
    func missingMetricsScope() async throws {
        PolarStub.reset(
            routes: [
                "/v1/organizations/": (200, Self.organization),
                "/v1/metrics/limits": (403, #"{"detail":"Missing required scope: metrics:read"}"#),
                "/v1/orders/": (200, #"{"items":[]}"#),
            ])

        let account = try await verify()
        #expect(
            account.unavailableMetrics == [
                "mrr", "revenue", "active_subscribers", "new_subscribers", "churned_subscribers",
            ])
    }

    /// A connection that can answer nothing is worse than no connection: it
    /// stores a key, shows as connected, and every widget built on it fails.
    @Test("a token that can read neither is refused")
    func noScopes() async throws {
        PolarStub.reset(
            routes: [
                "/v1/organizations/": (200, Self.organization),
                "/v1/metrics/limits": (403, "{}"),
                "/v1/orders/": (403, "{}"),
            ])

        await #expect(throws: ProviderFailure.self) { _ = try await verify() }
    }

    /// Not an auth failure: the token works, it just belongs to nothing this
    /// adapter can read numbers out of.
    @Test("a token bound to no organization is unsupported")
    func noOrganization() async throws {
        PolarStub.reset(routes: ["/v1/organizations/": (200, #"{"items":[]}"#)])
        await #expect(throws: ProviderFailure.unsupported("This token can see no organization.")) {
            _ = try await verify()
        }
    }

    /// A 500 on a scope probe is not a scope answer. Swallowing it would store
    /// a connection with metrics permanently withheld because Polar had a bad
    /// minute during setup.
    @Test("an outage during a scope probe fails the check rather than narrowing it")
    func outageDuringProbe() async throws {
        PolarStub.reset(
            routes: [
                "/v1/organizations/": (200, Self.organization),
                "/v1/metrics/limits": (503, "{}"),
            ])

        await #expect(throws: ProviderFailure.providerDown("Polar is having trouble.")) {
            _ = try await verify()
        }
    }

    @Test("a rejected token stops the check at the first call")
    func rejected() async throws {
        PolarStub.reset(routes: ["/v1/organizations/": (401, #"{"detail":"Invalid token"}"#)])
        await #expect(throws: ProviderFailure.authFailed("Invalid token")) {
            _ = try await verify()
        }
    }
}

/// A stubbed HTTP layer, so the arithmetic can be tested without a network.
///
/// `URLProtocol` is instantiated by `URLSession` with no way to hand it
/// per-instance state, hence the static table — and hence `.serialized` on
/// every suite that uses it.
}
final class PolarStub: URLProtocol {
    nonisolated(unsafe) private static var routes: [String: (Int, String)] = [:]
    nonisolated(unsafe) private static var seen: [URL] = []

    static func reset(routes: [String: (Int, String)]) {
        self.routes = routes
        seen = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PolarStub.self]
        return URLSession(configuration: configuration)
    }

    /// `URL.path` drops a trailing slash, and the trailing slash is the whole
    /// point on Polar's list routes: without it the API 307s and
    /// `ProviderHTTP` refuses to carry a bearer token through a redirect. So
    /// routing is on the raw path, which keeps it, and a test can pin it.
    private static func path(of url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
    }

    static var paths: [String] { seen.map(path(of:)) }
    static var hosts: [String] { seen.compactMap(\.host) }

    /// The query of the last request to one path, so a test can pin what was
    /// asked for rather than only what came back.
    static func query(for path: String) -> [String: String] {
        guard let url = seen.last(where: { Self.path(of: $0) == path }),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return [:] }
        return items.reduce(into: [:]) { out, item in out[item.name] = item.value }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.seen.append(url)
        // An unrouted path is a 404 rather than a hang, so a test that asked
        // for a call it did not stub fails by name.
        let (status, body) = Self.routes[Self.path(of: url)] ?? (404, #"{"detail":"no stub"}"#)
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
