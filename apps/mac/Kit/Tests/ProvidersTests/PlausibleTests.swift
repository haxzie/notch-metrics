import Foundation
import MetricsCore
import Testing

@testable import Providers

/// Plausible's statuses, in the buckets the caller acts differently on.
///
/// Tested through `failure(for:)` rather than over a stubbed session: what is
/// worth pinning is which bucket each status lands in, and that a 404 about
/// one site does not mark the whole connection broken./// Plausible's suites, nested under one serialized parent.
///
/// `PlausibleStub` is a `URLProtocol` holding its routes in static state, and Swift
/// Testing runs top-level suites in parallel. Marking the stub-using suites
/// `.serialized` individually orders each one internally but does nothing
/// between them, so they still read each other's queued responses — which
/// surfaces as "no stub" on a test whose own routes were installed correctly.
/// `.serialized` on a parent orders its children, which is the level the
/// guarantee is actually needed at.
@Suite(.serialized)
struct PlausibleTests {
@Suite("plausible failures")
struct PlausibleFailureTests {
    private func response(_ status: Int, body: String = "", headers: [String: String] = [:])
        -> ProviderHTTP.Response
    {
        ProviderHTTP.Response(status: status, headers: headers, body: Data(body.utf8))
    }

    @Test("a rejected key is an auth failure, and carries Plausible's own words")
    func badKey() {
        let failure = PlausibleProvider.failure(
            for: response(401, body: #"{"error":"Invalid API key or site ID"}"#))
        #expect(failure == .authFailed("Invalid API key or site ID"))
    }

    /// The status survives into the fallback on purpose: a 403 from a host
    /// that normally answers 401 is a WAF in front of Plausible, and that is a
    /// different afternoon from a mistyped key.
    @Test("and names the status when it sent no words")
    func badKeyUnexplained() {
        #expect(
            PlausibleProvider.failure(for: response(403))
                == .authFailed("Plausible rejected that API key (403)."))
    }

    /// The one worth being deliberate about. A 404 is a statement about one
    /// site or one metric — "metric is not available on your plan" arrives
    /// this way — so calling it an auth failure would ask the user to replace
    /// a key that reads everything else.
    @Test("a 404 is unsupported, not an auth failure, and quotes Plausible")
    func missingSite() {
        let failure = PlausibleProvider.failure(
            for: response(404, body: #"{"error":"Site could not be found"}"#))
        #expect(failure == .unsupported("Plausible: Site could not be found"))
    }

    /// Classified on the status, not on whether a body turned up. A connector
    /// that only says "no such site" when Plausible bothers to explain says
    /// the wrong thing at the worst moment.
    @Test("a 404 with no body is still unsupported")
    func missingSiteUnexplained() {
        #expect(
            PlausibleProvider.failure(for: response(404))
                == .unsupported("Plausible has no such site or metric."))
    }

    /// A malformed query is ours to fix, and Plausible names the part of the
    /// body it could not read. Throwing that away leaves "returned 400" on
    /// screen and the cause to be guessed from outside the system.
    @Test("a 400 keeps the explanation and stays a bad response")
    func badQuery() {
        let failure = PlausibleProvider.failure(
            for: response(400, body: #"{"error":"metrics/0: value is not allowed"}"#))
        #expect(failure == .badResponse("Plausible: metrics/0: value is not allowed"))
    }

    @Test("a spent quota carries the wait Plausible asked for")
    func rateLimited() {
        #expect(
            PlausibleProvider.failure(for: response(429, headers: ["Retry-After": "30"]))
                == .rateLimited("Plausible's rate limit is spent.", retryAfter: 30))
    }

    /// A nil wait would have the refresh loop retry on its own tick, which on
    /// a spent quota is immediately.
    @Test("and a minute when it asked for nothing")
    func rateLimitedSilently() {
        #expect(
            PlausibleProvider.failure(for: response(429))
                == .rateLimited("Plausible's rate limit is spent.", retryAfter: 60))
    }

    @Test("a 5xx is their outage, retried rather than reported as a bad key")
    func down() {
        #expect(
            PlausibleProvider.failure(for: response(503))
                == .providerDown("Plausible is having trouble."))
    }

    @Test("any other status says so")
    func unexplained() {
        #expect(
            PlausibleProvider.failure(for: response(418)) == .badResponse("Plausible returned 418."))
    }

    /// An HTML error page from a proxy in a notch tile is worse than the bare
    /// status it would replace.
    @Test("a body that is not Plausible's shape is dropped rather than rendered raw")
    func unreadableBody() {
        #expect(PlausibleProvider.message(in: Data("<html>502 Bad Gateway</html>".utf8)) == nil)
        #expect(PlausibleProvider.message(in: Data(#"{"error":"   "}"#.utf8)) == nil)
        #expect(PlausibleProvider.message(in: Data(#"{"message":"gateway"}"#.utf8)) == "gateway")
    }
}

@Suite("plausible credentials")
struct PlausibleCredentialTests {
    /// The failure this prevents is the one the Worker's Zod transform exists
    /// for: Plausible matches the domain exactly, and a pasted `"Example.com "`
    /// is a 404 that reads as a missing site.
    @Test("a site is trimmed and lower-cased")
    func normalisation() {
        #expect(PlausibleProvider.normalisedSiteID(" Example.com ") == "example.com")
        #expect(PlausibleProvider.normalisedSiteID("EXAMPLE.COM\n") == "example.com")
        #expect(PlausibleProvider.normalisedSiteID("example.com") == "example.com")
    }

    /// It runs on a value read back out of the keychain as well as on a fresh
    /// paste, so applying it twice has to be applying it once.
    @Test("and normalising a normalised site changes nothing")
    func idempotent() {
        for raw in [" Example.com ", "EXAMPLE.COM", "example.com", "  ", "Sub.Domain.Example.COM"] {
            let once = PlausibleProvider.normalisedSiteID(raw)
            #expect(PlausibleProvider.normalisedSiteID(once) == once)
        }
    }

    @Test("the stored site reaches the request normalised, not as pasted")
    func credentialsNormalise() throws {
        let creds = try PlausibleProvider.credentials(
            ["api_key": "plausible-key-123456", "site_id": " Example.com "])
        #expect(creds.siteID == "example.com")
    }

    /// The form will not submit an empty required field, so these are bugs
    /// rather than user error — but they reach a live API either way, and an
    /// empty bearer token reads back as a revoked key.
    @Test("a missing key or site is refused before any request is made")
    func missing() {
        #expect(throws: ProviderFailure.self) { try PlausibleProvider.credentials([:]) }
        #expect(throws: ProviderFailure.self) {
            try PlausibleProvider.credentials(["api_key": "plausible-key-123456"])
        }
        #expect(throws: ProviderFailure.self) {
            try PlausibleProvider.credentials(["api_key": "plausible-key-123456", "site_id": "   "])
        }
    }

    /// Eight characters of a real key is a 401, which reads as a revoked key
    /// and sends somebody to generate another one that fails the same way.
    @Test("a half-selected key is caught here rather than by Plausible")
    func truncatedKey() {
        #expect(throws: ProviderFailure.self) {
            try PlausibleProvider.credentials(["api_key": "abc", "site_id": "example.com"])
        }
    }

    /// Cloud only. Self-hosted Plausible speaks the same API on the
    /// operator's own domain, which an allowlist fixed at build time cannot
    /// admit.
    @Test("only plausible.io is reachable")
    func allowlist() {
        let hosts = PlausibleProvider().allowedHosts
        #expect(ProviderHTTP.hostAllowed("plausible.io", in: hosts))
        #expect(!ProviderHTTP.hostAllowed("analytics.example.com", in: hosts))
        #expect(!ProviderHTTP.hostAllowed("plausible.io.attacker.net", in: hosts))
    }

    /// The default suits a REST read that aggregates server-side, and the
    /// Worker's adapter overrides nothing either.
    @Test("the request timeout is the default eight seconds")
    func timeout() {
        #expect(PlausibleProvider().requestTimeout == ProviderHTTP.defaultTimeout)
    }
}

@Suite("plausible bucket labels")
struct PlausibleBucketLabelTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    /// Plausible labels a bucket with no offset, in the site's own reporting
    /// timezone. Reading it as UTC when the window is not UTC puts a bar in
    /// the wrong bucket, or outside the window entirely.
    @Test("a label is read in the window's zone, not the machine's")
    func zone() throws {
        #expect(
            try PlausibleProvider.instant(ofBucketLabel: "2026-10-05", timeZone: utc)
                == date("2026-10-05T00:00:00Z"))
        // Midnight in Tokyo is 15:00 UTC the day before.
        #expect(
            try PlausibleProvider.instant(
                ofBucketLabel: "2026-10-05", timeZone: TimeZone(identifier: "Asia/Tokyo")!)
                == date("2026-10-04T15:00:00Z"))
    }

    /// Both shapes Plausible sends: a date for day, week and month buckets,
    /// and a space-separated wall clock for hourly ones.
    @Test("an hourly label carries its hour")
    func hourly() throws {
        #expect(
            try PlausibleProvider.instant(ofBucketLabel: "2026-10-05 14:00:00", timeZone: utc)
                == date("2026-10-05T14:00:00Z"))
        #expect(
            try PlausibleProvider.instant(ofBucketLabel: "2026-10-05T14:30:00", timeZone: utc)
                == date("2026-10-05T14:30:00Z"))
    }

    /// An hour that does not exist in the zone, because the clocks went
    /// forward over it. Worth pinning only as "does not crash and does not
    /// land in the previous day".
    @Test("a label across a clock change still resolves")
    func daylightSaving() throws {
        let london = TimeZone(identifier: "Europe/London")!
        let instant = try PlausibleProvider.instant(
            ofBucketLabel: "2026-03-29 01:00:00", timeZone: london)
        #expect(instant >= date("2026-03-29T00:00:00Z"))
        #expect(instant <= date("2026-03-29T02:00:00Z"))
    }

    /// A shape Plausible does not currently send is a bad response rather
    /// than a bar at 1970.
    @Test("an unreadable label is a bad response")
    func unreadable() {
        #expect(throws: ProviderFailure.self) {
            try PlausibleProvider.instant(ofBucketLabel: "last week", timeZone: utc)
        }
        #expect(throws: ProviderFailure.self) {
            try PlausibleProvider.instant(ofBucketLabel: "", timeZone: utc)
        }
    }

    /// Plausible sends `null` for a bucket it has no rows for, and a nil that
    /// propagated would make the whole window's figure nil.
    @Test("a null figure is a zero")
    func nulls() {
        #expect(PlausibleProvider.number(nil) == 0)
        #expect(PlausibleProvider.number(.nan) == 0)
        #expect(PlausibleProvider.number(.infinity) == 0)
        #expect(PlausibleProvider.number(41) == 41)
    }
}

/// The arithmetic, over a stubbed session.
///
/// Serialised because the stub's routing table is static: `URLProtocol` is
/// instantiated by `URLSession` and there is nowhere to hand per-test state.
@Suite("plausible metrics", .serialized)
struct PlausibleMetricTests {
    private let utc = TimeZone(identifier: "UTC")!
    private static let query = "/api/v2/query"

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func window(
        _ metric: String, from: String = "2026-01-08T00:00:00Z", to: String = "2026-01-11T00:00:00Z",
        granularity: Granularity = .day, wantSeries: Bool = true, comparePrevious: Bool = false
    ) -> MetricWindow {
        MetricWindow(
            metric: metric, from: date(from), to: date(to), granularity: granularity,
            wantSeries: wantSeries, comparePrevious: comparePrevious, timeZone: utc)
    }

    private func fetch(_ window: MetricWindow) async throws -> MetricValue {
        try await PlausibleProvider().fetch(
            ["api_key": "plausible-key-123456", "site_id": " Example.com "],
            window: window,
            http: ProviderHTTP(
                allowedHosts: PlausibleProvider().allowedHosts, session: PlausibleStub.session()))
    }

    /// The figure is Plausible's own aggregate over the window, never the sum
    /// of the bars: a visitor active on three days is one unique visitor, and
    /// a headline built by adding the chart up would report three.
    @Test("the headline is the window's own aggregate, not the sum of the bars")
    func visitors() async throws {
        PlausibleStub.reset(
            routes: [
                Self.query: [
                    (200, #"{"results":[{"metrics":[410]}]}"#),
                    (
                        200,
                        #"""
                        {"results":[
                          {"metrics":[100],"dimensions":["2026-01-08"]},
                          {"metrics":[300],"dimensions":["2026-01-10"]}
                        ]}
                        """#
                    ),
                ]
            ])

        let value = try await fetch(window("visitors"))

        #expect(value.value == 410)
        #expect(value.value != 400)
        // Every bucket in the window, including the two Plausible omitted: a
        // chart that skips a quiet day draws a line straight over it.
        #expect(value.points.map(\.v) == [100, 0, 300, 0])
        // Not money. A currency here would render 410 visitors as $4.10.
        #expect(value.currency == nil)
        // No comparison was asked for, so none was fetched and none is
        // reported — nil, never zero, which would render as a rise from
        // nothing.
        #expect(value.previousValue == nil)
        #expect(PlausibleStub.requests.count == 2)
    }

    /// The window total and the chart are two different questions, and the
    /// second is the only one that carries a time dimension.
    @Test("the query names the site, the metric, the window and the buckets")
    func queryBody() async throws {
        // Two replies, because a fetch asks two questions: the window's own
        // total, then the chart. Queueing only the first let the chart read
        // an undimensioned row and throw "unreadable bucket" before any of
        // the assertions below ran — so the test failed on its fixture
        // rather than on the thing it is about.
        PlausibleStub.reset(
            routes: [
                Self.query: [
                    (200, #"{"results":[{"metrics":[1]}]}"#),
                    (200, #"{"results":[{"metrics":[1],"dimensions":["2026-01-08"]}]}"#),
                ]
            ])

        _ = try await fetch(window("visitors", granularity: .week))

        let total = PlausibleStub.body(at: 0)
        // Normalised on the way in, not sent as pasted.
        #expect(total?["site_id"] as? String == "example.com")
        #expect(total?["metrics"] as? [String] == ["visitors"])
        // Instants, not a `YYYY-MM-DD` pair and not one of Plausible's
        // shorthands: the window comes from the widget, and a day pair would
        // round an hourly widget's window out to whole calendar days.
        #expect(
            total?["date_range"] as? [String] == ["2026-01-08T00:00:00Z", "2026-01-11T00:00:00Z"])
        #expect(total?["dimensions"] == nil)

        // Plausible buckets at the granularity asked for, so a week is
        // weighted by its own sessions rather than being the mean of seven
        // daily rates.
        #expect(PlausibleStub.body(at: 1)?["dimensions"] as? [String] == ["time:week"])
    }

    /// Plausible says "visits" where every other connector here says sessions.
    @Test("sessions asks Plausible for visits")
    func sessions() async throws {
        PlausibleStub.reset(routes: [Self.query: [(200, #"{"results":[{"metrics":[62]}]}"#)]])

        let value = try await fetch(window("sessions", wantSeries: false))

        #expect(value.value == 62)
        #expect(PlausibleStub.body(at: 0)?["metrics"] as? [String] == ["visits"])
    }

    /// Plausible reports a percentage and the catalogue declares a ratio. A
    /// bounce rate left unscaled renders as 4100%.
    @Test("a bounce rate is a fraction, not a percentage")
    func bounceRate() async throws {
        PlausibleStub.reset(
            routes: [
                Self.query: [
                    (200, #"{"results":[{"metrics":[41]}]}"#),
                    (
                        200,
                        #"{"results":[{"metrics":[50],"dimensions":["2026-01-08"]}]}"#
                    ),
                ]
            ])

        let value = try await fetch(window("bounce_rate"))

        #expect(abs(value.value - 0.41) < 0.0001)
        #expect(abs(value.points[0].v - 0.5) < 0.0001)
        // A rate is not an addend, so the bars must not have been rolled up
        // into the headline.
        #expect(value.value != 0.5)
    }

    /// Asked for separately, and only when the tile wants a delta: it doubles
    /// the requests, and a tile with no delta on it would pay that for
    /// nothing.
    @Test("a comparison is the window before this one, reported separately")
    func comparePrevious() async throws {
        PlausibleStub.reset(
            routes: [
                Self.query: [
                    (200, #"{"results":[{"metrics":[410]}]}"#),
                    (200, #"{"results":[{"metrics":[300]}]}"#),
                ]
            ])

        let value = try await fetch(window("pageviews", wantSeries: false, comparePrevious: true))

        #expect(value.value == 410)
        #expect(value.previousValue == 300)
        // Widened backwards by the window's own length, and the earlier half
        // is never reported as the figure.
        #expect(
            PlausibleStub.body(at: 1)?["date_range"] as? [String]
                == ["2026-01-05T00:00:00Z", "2026-01-08T00:00:00Z"])
        // And the chart still covers the requested window only.
        #expect(value.points.isEmpty)
    }

    /// A tile with no chart pays for one request, not two.
    @Test("a tile with no chart gets the figure without the points")
    func noSeries() async throws {
        PlausibleStub.reset(routes: [Self.query: [(200, #"{"results":[{"metrics":[410]}]}"#)]])

        let value = try await fetch(window("visitors", wantSeries: false))

        #expect(value.value == 410)
        #expect(value.points.isEmpty)
        #expect(PlausibleStub.requests.count == 1)
    }

    /// Plausible answers a window with no traffic at all, and a nil that
    /// propagated would blank the tile instead of showing a zero.
    @Test("an empty window is a zero rather than nothing")
    func empty() async throws {
        PlausibleStub.reset(
            routes: [
                Self.query: [
                    (200, #"{"results":[]}"#),
                    (200, #"{"results":[{"metrics":[null],"dimensions":["2026-01-08"]}]}"#),
                ]
            ])

        let value = try await fetch(window("visitors"))

        #expect(value.value == 0)
        #expect(value.points.map(\.v) == [0, 0, 0, 0])
    }

    @Test("a metric this build does not read says so rather than failing obscurely")
    func notPorted() async {
        PlausibleStub.reset(routes: [:])
        await #expect(throws: ProviderFailure.self) { try await fetch(window("revenue")) }
        // And not by having asked Plausible first.
        #expect(PlausibleStub.requests.isEmpty)
    }

    /// A 404 mid-read is a statement about this metric on this plan, not a
    /// broken connection.
    @Test("a metric the plan does not include is unsupported")
    func planLimited() async {
        PlausibleStub.reset(
            routes: [
                Self.query: [(404, #"{"error":"metric is not available on your plan"}"#)]
            ])

        await #expect(
            throws: ProviderFailure.unsupported("Plausible: metric is not available on your plan")
        ) {
            try await fetch(window("visitors"))
        }
    }
}

@Suite("plausible verify", .serialized)
struct PlausibleVerifyTests {
    private static let site = "/api/v1/sites/example.com"

    private func verify() async throws -> ProviderAccount {
        try await PlausibleProvider().verify(
            ["api_key": "plausible-key-123456", "site_id": " Example.com "],
            http: ProviderHTTP(
                allowedHosts: PlausibleProvider().allowedHosts, session: PlausibleStub.session()))
    }

    /// The site endpoint rather than a stats query: it proves the key, proves
    /// the site is on the key's team, and costs nothing in stats quota.
    @Test("the connection is labelled with the domain Plausible reports")
    func labelled() async throws {
        PlausibleStub.reset(
            routes: [
                Self.site: [(200, #"{"domain":"example.com","timezone":"Europe/London"}"#)]
            ])

        let account = try await verify()

        #expect(account.label == "example.com")
        // Not a money connector.
        #expect(account.currency == nil)
        #expect(account.unavailableMetrics.isEmpty)
        // The normalised site is what was asked for, so a pasted
        // "Example.com " does not 404.
        #expect(PlausibleStub.paths == [Self.site])
    }

    @Test("a site Plausible will not name falls back to the stored one")
    func unnamed() async throws {
        PlausibleStub.reset(routes: [Self.site: [(200, #"{"domain":"  "}"#)]])
        #expect(try await verify().label == "example.com")
    }

    /// The one place a 404 is read as an auth problem. A key is scoped to one
    /// team, and a site owned by another answers exactly as a wrong domain
    /// does — so at setup time there is nothing else it can be, and
    /// `unsupported` would store a connection that can never answer anything.
    @Test("a site this key cannot see fails the check, and says why")
    func wrongTeam() async {
        PlausibleStub.reset(
            routes: [Self.site: [(404, #"{"error":"Site could not be found"}"#)]])

        // The message is the test, not only the case: it has to name the site
        // and say that a key is scoped to a team, or the user re-types a
        // domain that was already right.
        do {
            _ = try await verify()
            Issue.record("a site this key cannot see was accepted")
        } catch {
            guard case .authFailed(let message)? = error as? ProviderFailure else {
                Issue.record("a missing site at setup time is an auth failure")
                return
            }
            #expect(message.contains("example.com"))
            #expect(message.contains("team"))
        }
    }

    @Test("a rejected key is an auth failure in Plausible's own words")
    func rejected() async {
        PlausibleStub.reset(
            routes: [Self.site: [(401, #"{"error":"Invalid API key"}"#)]])
        await #expect(throws: ProviderFailure.authFailed("Invalid API key")) {
            _ = try await verify()
        }
    }

    /// Refused before anything is stored and before a request is made, so an
    /// empty bearer token never reaches a live API.
    @Test("an empty credential is refused before the first request")
    func emptyCredentials() async {
        PlausibleStub.reset(routes: [:])
        await #expect(throws: ProviderFailure.self) {
            _ = try await PlausibleProvider().verify(
                [:],
                http: ProviderHTTP(
                    allowedHosts: PlausibleProvider().allowedHosts,
                    session: PlausibleStub.session()))
        }
        #expect(PlausibleStub.paths.isEmpty)
    }
}

/// A stubbed HTTP layer, so the arithmetic can be tested without a network.
///
/// `URLProtocol` is instantiated by `URLSession` with no way to hand it
/// per-instance state, hence the static table — and hence `.serialized` on
/// every suite that uses it.
///
/// Routes hold a *queue* per path rather than one response, because every
/// Plausible query is a POST to the same path: the window total, its
/// comparison and the chart are three answers to one route, and a test that
/// could not tell them apart could not pin which was which.
}
final class PlausibleStub: URLProtocol {
    nonisolated(unsafe) private static var routes: [String: [(Int, String)]] = [:]
    nonisolated(unsafe) private static var seen: [(url: URL, body: Data)] = []

    static func reset(routes: [String: [(Int, String)]]) {
        self.routes = routes
        seen = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlausibleStub.self]
        return URLSession(configuration: configuration)
    }

    static var requests: [(url: URL, body: Data)] { seen }
    static var paths: [String] { seen.map { $0.url.path } }

    /// The JSON body of the nth request, so a test can pin what was asked for
    /// rather than only what came back.
    static func body(at index: Int) -> [String: Any]? {
        guard index < seen.count else { return nil }
        return try? JSONSerialization.jsonObject(with: seen[index].body) as? [String: Any]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.seen.append((url: url, body: Self.sentBody(of: request)))

        // The queue is consumed in order, and its last entry repeats: a test
        // that cares about only the first answer does not have to spell out
        // every later one. An unrouted path is a 404 rather than a hang, so a
        // test that asked for a call it did not stub fails by name.
        let queued = Self.routes[url.path] ?? []
        let index = min(Self.seen.filter { $0.url.path == url.path }.count - 1, queued.count - 1)
        let (status, body) =
            index >= 0 && !queued.isEmpty ? queued[index] : (404, #"{"error":"no stub"}"#)

        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// `URLSession` moves a request body into a stream before a `URLProtocol`
    /// sees it, so `httpBody` is nil here however it was set. Reading the
    /// stream is the only way a test can see what was sent.
    private static func sentBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
