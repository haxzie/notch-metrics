import Foundation
import MetricsCore
import Testing

@testable import Providers

// MARK: - A stubbed Amplitude

/// Answers whatever the adapter asks for, and records that it asked.
///
/// A `URLProtocol` rather than a fake `ProviderHTTP`, so the allowlist and
/// the manual redirect handling are still in the path — which host a request
/// went to is one of the things these tests pin, and the region is the whole
/// reason that matters here.
final class AmplitudeStub: URLProtocol {
    struct Reply {
        let status: Int
        let body: String
        var headers: [String: String] = [:]

        static func ok(_ body: String) -> Reply { Reply(status: 200, body: body) }
    }

    nonisolated(unsafe) static var reply: @Sendable (URLRequest) -> Reply = { _ in .ok("{}") }
    nonisolated(unsafe) static var seen: [URLRequest] = []

    static func requests() -> [URLRequest] { seen }

    static func session(_ reply: @escaping @Sendable (URLRequest) -> Reply) -> URLSession {
        Self.reply = reply
        Self.seen = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AmplitudeStub.self]
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

/// Amplitude, pointed at the stub. The allowlist is the adapter's own.
private func amplitude(
    _ reply: @escaping @Sendable (URLRequest) -> AmplitudeStub.Reply
) -> (AmplitudeProvider, ProviderHTTP) {
    let provider = AmplitudeProvider()
    return (
        provider,
        ProviderHTTP(allowedHosts: provider.allowedHosts, session: AmplitudeStub.session(reply))
    )
}

private func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: iso)!
}

private let utc = TimeZone(identifier: "UTC")!

private func window(
    _ metric: String, from: String = "2026-03-01T00:00:00Z", to: String = "2026-03-04T00:00:00Z",
    granularity: Granularity = .day, wantSeries: Bool = true, comparePrevious: Bool = false,
    timeZone: TimeZone = utc
) -> MetricWindow {
    MetricWindow(
        metric: metric, from: date(from), to: date(to), granularity: granularity,
        wantSeries: wantSeries, comparePrevious: comparePrevious, timeZone: timeZone)
}

private let usKeys = [
    "api_key": "abcdef0123456789", "secret_key": "fedcba9876543210", "region": "us",
]

/// `start`, `end`, `m`, `i` and `e` of a recorded request, whichever it carried.
private func query(_ request: URLRequest) -> [String: String] {
    let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return items.reduce(into: [:]) { out, item in out[item.name] = item.value }
}

// MARK: - Failures

/// Amplitude's statuses, in the buckets the caller acts differently on.
///
/// Tested through `failure(for:region:)` rather than over the network: what
/// is worth pinning is which bucket each status lands in, and above all that
/// the message names the region./// Amplitude's suites, nested under one serialized parent.
///
/// `AmplitudeStub` is a `URLProtocol` holding its routes in static state, and Swift
/// Testing runs top-level suites in parallel. Marking the stub-using suites
/// `.serialized` individually orders each one internally but does nothing
/// between them, so they still read each other's queued responses — which
/// surfaces as "no stub" on a test whose own routes were installed correctly.
/// `.serialized` on a parent orders its children, which is the level the
/// guarantee is actually needed at.
@Suite(.serialized)
struct AmplitudeTests {
@Suite("amplitude failures")
struct AmplitudeFailureTests {
    private func response(_ status: Int, body: String = "", headers: [String: String] = [:])
        -> ProviderHTTP.Response
    {
        ProviderHTTP.Response(status: status, headers: headers, body: Data(body.utf8))
    }

    /// The region is in the message because the commonest cause of a 401 is a
    /// project's keys sent to the other deployment, and "rejected the
    /// credentials" sends somebody off to issue a key they already have.
    @Test("a rejected pair is an auth failure and names the region")
    func badKeys() {
        #expect(
            AmplitudeProvider.failure(for: response(401), region: .eu)
                == .authFailed(
                    "Amplitude rejected these keys. Check they are the EU project's pair "
                        + "— the other region answers 401 too."))
    }

    /// Unlike Stripe's or Paddle's, a 403 here is not a statement about one
    /// resource: the Dashboard API has no scopes to be missing, so a 403
    /// means the same thing a 401 does and is reported the same way. The
    /// status is carried through because a 403 from a host that normally says
    /// 401 is how a WAF in front of the provider shows up.
    @Test("a 403 is the same rejection, with its own status in the message")
    func forbidden() {
        #expect(
            AmplitudeProvider.failure(for: response(403), region: .us)
                == .authFailed(
                    "Amplitude rejected these keys. Check they are the US project's pair "
                        + "— the other region answers 403 too."))
    }

    @Test("a spent quota carries the wait Amplitude asked for")
    func rateLimited() {
        #expect(
            AmplitudeProvider.failure(
                for: response(429, headers: ["Retry-After": "15"]), region: .us)
                == .rateLimited("amplitude.com asked us to wait.", retryAfter: 15))
    }

    /// A nil wait would have the refresh loop retry on its own tick, which on
    /// a spent quota is immediately.
    @Test("and a minute when it asked for nothing")
    func rateLimitedSilently() {
        #expect(
            AmplitudeProvider.failure(for: response(429), region: .us)
                == .rateLimited("amplitude.com asked us to wait.", retryAfter: 60))
    }

    @Test("a 5xx is their outage, retried rather than reported as bad keys")
    func down() {
        #expect(
            AmplitudeProvider.failure(for: response(503), region: .eu)
                == .providerDown("analytics.eu.amplitude.com returned 503."))
    }

    /// Three shapes because this API has used all three, and throwing the
    /// body away leaves a bare status on screen with the cause to be guessed
    /// from outside the system.
    @Test("any other 4xx keeps the explanation Amplitude sent, in each shape")
    func explained() {
        let bodies = [
            #"{"error":"start must be before end"}"#,
            #"{"error":{"message":"start must be before end"}}"#,
            #"{"message":"start must be before end"}"#,
        ]
        for body in bodies {
            #expect(
                AmplitudeProvider.failure(for: response(400, body: body), region: .us)
                    == .badResponse("start must be before end"))
        }
    }

    /// An HTML error page in a notch tile is worse than the bare status it
    /// would replace.
    @Test("an unreadable body falls back to the status")
    func unexplained() {
        #expect(
            AmplitudeProvider.failure(for: response(418, body: "<html>no</html>"), region: .us)
                == .badResponse("amplitude.com returned 418."))
    }
}

// MARK: - Credentials and region

@Suite("amplitude credentials")
struct AmplitudeCredentialTests {
    @Test("the id matches the catalogue's so one table routes both")
    func identifier() {
        #expect(AmplitudeProvider().id == "amplitude")
    }

    /// Both hosts, because the region is per connection while the allowlist
    /// is per adapter — and nothing else, including the bare EU apex.
    @Test("both regions are reachable and nothing else is")
    func allowlist() {
        let hosts = AmplitudeProvider().allowedHosts
        #expect(ProviderHTTP.hostAllowed("amplitude.com", in: hosts))
        #expect(ProviderHTTP.hostAllowed("analytics.eu.amplitude.com", in: hosts))
        #expect(!ProviderHTTP.hostAllowed("eu.amplitude.com", in: hosts))
        #expect(!ProviderHTTP.hostAllowed("amplitude.com.attacker.net", in: hosts))
    }

    @Test("the region picks the host")
    func hosts() {
        #expect(AmplitudeProvider.Region.us.host == "amplitude.com")
        #expect(AmplitudeProvider.Region.eu.host == "analytics.eu.amplitude.com")
    }

    /// A connection stored before the field existed, or with a hand-edited
    /// value, is US: that is the manifest's default, and the same
    /// unknown-falls-back rule every wire enum in this app decodes under.
    @Test("an absent or unrecognised region is the US")
    func defaulted() throws {
        let base = ["api_key": "k0000000", "secret_key": "s0000000"]
        #expect(try AmplitudeProvider.Credentials(base).region == .us)
        #expect(try AmplitudeProvider.Credentials(base.merging(["region": "apac"]) { _, b in b })
            .region == .us)
        #expect(try AmplitudeProvider.Credentials(base.merging(["region": " EU "]) { _, b in b })
            .region == .eu)
    }

    /// Both keys are required, and `credentials["x"] ?? ""` would send an
    /// empty secret to a live API and read back as a revoked pair.
    @Test("a missing key is named rather than sent as an empty string")
    func missing() {
        #expect(throws: ProviderFailure.authFailed("No secret_key was stored for this connection.")) {
            try AmplitudeProvider.Credentials(["api_key": "k0000000"])
        }
        #expect(throws: ProviderFailure.authFailed("No api_key was stored for this connection.")) {
            try AmplitudeProvider.Credentials(["secret_key": "s0000000"])
        }
    }

    /// Basic over the pair, not a bearer token: Amplitude answers a bearer
    /// with a 401 that reads exactly like a mistyped key.
    @Test("the pair is signed as HTTP Basic, api key then secret")
    func basic() throws {
        let creds = try AmplitudeProvider.Credentials(usKeys)
        let header = AmplitudeProvider.authorization(creds)
        #expect(header == "Basic " + Data("abcdef0123456789:fedcba9876543210".utf8)
            .base64EncodedString())
        // Decodes back to exactly the two keys and one colon, which is the
        // part a hand-rolled base64 gets wrong.
        let decoded = String(
            data: Data(base64Encoded: String(header.dropFirst("Basic ".count)))!, encoding: .utf8)
        #expect(decoded == "abcdef0123456789:fedcba9876543210")
    }
}

// MARK: - Dates

@Suite("amplitude dates")
struct AmplitudeDateTests {
    /// The window's zone, not the machine's: the figures have to match the
    /// project's own charts, and a user reading a US project from Berlin
    /// would otherwise ask for a day the dashboard does not show.
    @Test("a day is YYYYMMDD in the window's own zone")
    func day() {
        let at = date("2026-03-01T23:30:00Z")
        #expect(AmplitudeProvider.day(at, timeZone: utc) == "20260301")
        #expect(
            AmplitudeProvider.day(at, timeZone: TimeZone(identifier: "Europe/Berlin")!)
                == "20260302")
        #expect(
            AmplitudeProvider.day(at, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
                == "20260301")
    }

    /// Noon, not midnight. A midnight timestamp bucketed in Los Angeles falls
    /// into the previous day, which shifts every bar on the chart by one.
    @Test("a label parses to noon UTC of that calendar day, in either form")
    func dayAt() throws {
        let noon = date("2026-03-02T12:00:00Z")
        #expect(AmplitudeProvider.dayAt("20260302") == noon)
        #expect(AmplitudeProvider.dayAt("2026-03-02") == noon)
    }

    /// Dropped rather than bucketed at the epoch, which would put a bar on 1
    /// January 1970 and silently remove it from the window.
    @Test("a label this adapter cannot read is nil")
    func unreadable() {
        #expect(AmplitudeProvider.dayAt("") == nil)
        #expect(AmplitudeProvider.dayAt("2026-03") == nil)
    }
}

// MARK: - Headlines

/// Which figure is the headline, which is the part a port silently gets wrong.
@Suite("amplitude headlines")
struct AmplitudeHeadlineTests {
    private func result(_ amounts: [Double], collapsed: Double?) -> AmplitudeProvider.ChartResult {
        AmplitudeProvider.ChartResult(
            rows: amounts.enumerated().map {
                (at: date("2026-03-0\($0.offset + 1)T12:00:00Z"), amount: $0.element)
            },
            collapsed: collapsed)
    }

    /// The failure worth pinning. Summing daily uniques counts a person once
    /// per day they showed up, so active users over three days would come out
    /// as three times the truth.
    @Test("a de-duplicated metric takes Amplitude's own window figure, not the sum")
    func collapsed() throws {
        let spec = try #require(AmplitudeProvider.spec(for: "active_users"))
        #expect(spec.additive == false)
        #expect(AmplitudeProvider.headline(spec, result([10, 10, 10], collapsed: 14)) == 14)
    }

    /// Falling back rather than reporting nothing: an endpoint that stops
    /// sending `seriesCollapsed` should overstate the number at worst, not
    /// blank the tile.
    @Test("and falls back to the sum when Amplitude sent no window figure")
    func collapsedMissing() throws {
        let spec = try #require(AmplitudeProvider.spec(for: "active_users"))
        #expect(AmplitudeProvider.headline(spec, result([10, 10, 10], collapsed: nil)) == 30)
    }

    /// A user is new on exactly one day, and an event happens once, so these
    /// bars do add up to their headline — and Amplitude's window figure, if
    /// it sends one, is ignored in favour of the days the chart draws.
    @Test("an additive metric sums its days even when a window figure arrives")
    func additive() throws {
        for metric in ["new_users", "events"] {
            let spec = try #require(AmplitudeProvider.spec(for: metric))
            #expect(spec.additive)
            #expect(AmplitudeProvider.headline(spec, result([1, 2, 3], collapsed: 99)) == 6)
        }
    }

    @Test("a metric this build has not been taught has no spec")
    func unknown() {
        #expect(AmplitudeProvider.spec(for: "sessions") == nil)
    }
}

// MARK: - Fetching

/// Serialised, because the stub answers through a `URLProtocol` and a
/// `URLProtocol` subclass is registered on a session configuration by type —
/// so its state is static, and two of these running at once would read each
/// other's replies.
@Suite("amplitude metrics", .serialized)
struct AmplitudeMetricTests {
    private func segmentation(_ values: [String], collapsed: String? = nil) -> String {
        let labels = (1...values.count).map { #""2026-03-0\#($0)""# }.joined(separator: ",")
        let collapsedJSON = collapsed.map { #","seriesCollapsed":[[{"value":\#($0)}]]"# } ?? ""
        return """
            {"data":{"series":[[\(values.joined(separator: ","))]],
             "xValues":[\(labels)]\(collapsedJSON)}}
            """
    }

    @Test("active users report Amplitude's window figure and still draw every day")
    func activeUsers() async throws {
        let (provider, http) = amplitude { _ in
            .ok(self.segmentation(["4", "5", "6"], collapsed: "11"))
        }
        let value = try await provider.fetch(
            usKeys, window: window("active_users"), http: http)

        #expect(value.value == 11)
        #expect(value.points.map(\.v) == [4, 5, 6, 0])
        // Deliberately not equal: one person active on three days is one user
        // and three bars, and the methodology string says so.
        #expect(value.points.reduce(0) { $0 + $1.v } != value.value)
        // A count, not money. A currency here would have the formatter put a
        // symbol in front of a user count.
        #expect(value.currency == nil)
        #expect(value.previousValue == nil)
    }

    @Test("new users sum their days")
    func newUsers() async throws {
        let (provider, http) = amplitude { _ in
            .ok(#"{"data":{"series":[[2,3,null,1]],"xValues":["20260301","20260302","20260303","20260304"]}}"#)
        }
        let value = try await provider.fetch(usKeys, window: window("new_users"), http: http)

        // The null is nothing happening, not a gap: 2 + 3 + 0 + 1.
        #expect(value.value == 6)
        #expect(value.points.map(\.v) == [2, 3, 0, 1])
    }

    /// The three specs differ only in endpoint and parameters, and getting
    /// one of those wrong gives a plausible number for the wrong question.
    @Test("each metric asks the endpoint the Worker asks")
    func requests() async throws {
        let (provider, http) = amplitude { _ in .ok(#"{"data":{"series":[[1]],"xValues":["20260301"]}}"#) }

        _ = try await provider.fetch(usKeys, window: window("active_users"), http: http)
        _ = try await provider.fetch(usKeys, window: window("new_users"), http: http)
        _ = try await provider.fetch(usKeys, window: window("events"), http: http)

        let seen = AmplitudeStub.requests()
        #expect(seen.count == 3)

        #expect(seen[0].url?.path == "/api/2/events/segmentation")
        #expect(query(seen[0])["e"] == #"{"event_type":"_active"}"#)
        #expect(query(seen[0])["m"] == "uniques")

        #expect(seen[1].url?.path == "/api/2/users")
        #expect(query(seen[1])["m"] == "new")
        #expect(query(seen[1])["e"] == nil)

        #expect(seen[2].url?.path == "/api/2/events/segmentation")
        #expect(query(seen[2])["e"] == #"{"event_type":"_all"}"#)
        #expect(query(seen[2])["m"] == "totals")

        for request in seen {
            // Always daily, never `i=7`: Amplitude's own weeks start on a
            // Sunday while every other series in the notch starts on a
            // Monday, so the roll-up happens locally.
            #expect(query(request)["i"] == "1")
            #expect(query(request)["start"] == "20260301")
            #expect(query(request)["end"] == "20260304")
            #expect(request.value(forHTTPHeaderField: "authorization")?.hasPrefix("Basic ") == true)
        }
    }

    /// The failure this guards is a request sent to the wrong deployment,
    /// which answers 401 and reads exactly like a bad secret.
    @Test("the stored region picks the host the keys are sent to")
    func regionHost() async throws {
        let (provider, http) = amplitude { _ in .ok(#"{"data":{"series":[[1]],"xValues":["20260301"]}}"#) }
        var euKeys = usKeys
        euKeys["region"] = "eu"

        _ = try await provider.fetch(usKeys, window: window("events"), http: http)
        _ = try await provider.fetch(euKeys, window: window("events"), http: http)

        #expect(AmplitudeStub.requests()[0].url?.host == "amplitude.com")
        #expect(AmplitudeStub.requests()[1].url?.host == "analytics.eu.amplitude.com")
    }

    /// The earlier window is a second call, and must not overlap the
    /// requested one: Amplitude's range is inclusive at both ends, so a
    /// shared boundary day would be counted in both halves.
    @Test("a comparison fetches the window before, up to the day before it starts")
    func comparison() async throws {
        let (provider, http) = amplitude { request in
            query(request)["end"] == "20260228"
                ? .ok(self.segmentation(["1", "1", "1"]))
                : .ok(self.segmentation(["5", "5", "5"]))
        }
        let value = try await provider.fetch(
            usKeys, window: window("events", comparePrevious: true), http: http)

        #expect(value.value == 15)
        #expect(value.previousValue == 3)
        // Only the requested window reaches the chart, so the earlier half's
        // days are never drawn.
        #expect(value.points.count == 4)

        let seen = AmplitudeStub.requests()
        #expect(seen.count == 2)
        #expect(query(seen[1])["start"] == "20260226")
        #expect(query(seen[1])["end"] == "20260228")
    }

    /// `previousValue` stays nil rather than zero, which would draw "down
    /// 100%" against a window nobody fetched.
    @Test("no comparison means one call and no previous figure")
    func noComparison() async throws {
        let (provider, http) = amplitude { _ in .ok(self.segmentation(["5", "5", "5"])) }
        let value = try await provider.fetch(usKeys, window: window("events"), http: http)

        #expect(value.previousValue == nil)
        #expect(AmplitudeStub.requests().count == 1)
    }

    /// A tile with no chart still needs its headline, which is the whole
    /// point of the flag.
    @Test("a tile with no chart keeps its number and drops the points")
    func withoutSeries() async throws {
        let (provider, http) = amplitude { _ in
            .ok(self.segmentation(["4", "5", "6"], collapsed: "11"))
        }
        let value = try await provider.fetch(
            usKeys, window: window("active_users", wantSeries: false), http: http)

        #expect(value.value == 11)
        #expect(value.points.isEmpty)
    }

    /// Rolled up locally from daily rows. Asking Amplitude for weeks would
    /// start them on a Sunday, which no other tile in the notch does.
    @Test("a weekly window rolls the daily rows up here")
    func weekly() async throws {
        let (provider, http) = amplitude { _ in
            .ok(
                #"{"data":{"series":[[1,2,3,4]],"#
                    + #""xValues":["20260301","20260302","20260303","20260304"]}}"#)
        }
        let value = try await provider.fetch(
            usKeys,
            window: window("events", from: "2026-03-01T00:00:00Z", to: "2026-03-04T00:00:00Z",
                           granularity: .week),
            http: http)

        // The headline is the whole window either way; what the granularity
        // changes is the bars, which are fewer than the days behind them.
        // Where a week begins is `bucketSum`'s business, not this adapter's.
        #expect(value.value == 10)
        #expect(value.points.count < 4)
        #expect(value.points.reduce(0) { $0 + $1.v } == 10)
        // Still asked for daily rows, whatever the chart draws.
        #expect(query(try #require(AmplitudeStub.requests().first))["i"] == "1")
    }

    /// Not a bug: the catalogue is the Worker's and lists metrics this build
    /// has not been taught yet. The caller falls back to the API.
    @Test("a metric this build cannot read says so rather than guessing")
    func unsupported() async throws {
        let (provider, http) = amplitude { _ in .ok("{}") }
        await #expect(throws: ProviderFailure.unsupported(
            "This build cannot read Amplitude's sessions yet.")) {
            try await provider.fetch(usKeys, window: window("sessions"), http: http)
        }
        // And nothing was asked of Amplitude for it.
        #expect(AmplitudeStub.requests().isEmpty)
    }

    /// An empty body is zero rather than a crash: a brand-new project has no
    /// events, and `{}` is what this API answers with.
    @Test("an empty payload is zero and a chart of zeroes")
    func empty() async throws {
        let (provider, http) = amplitude { _ in .ok("{}") }
        let value = try await provider.fetch(usKeys, window: window("events"), http: http)

        #expect(value.value == 0)
        #expect(value.points.map(\.v) == [0, 0, 0, 0])
    }

    @Test("a rejected pair reaches the caller as an auth failure naming the region")
    func rejected() async throws {
        let (provider, http) = amplitude { _ in .init(status: 401, body: "") }
        var euKeys = usKeys
        euKeys["region"] = "eu"

        await #expect(throws: ProviderFailure.authFailed(
            "Amplitude rejected these keys. Check they are the EU project's pair "
                + "— the other region answers 401 too.")) {
            try await provider.fetch(euKeys, window: window("events"), http: http)
        }
    }
}

// MARK: - Verify

@Suite("amplitude verify", .serialized)
struct AmplitudeVerifyTests {
    /// The smallest real query, because the Dashboard API has no identity
    /// endpoint to ask instead — and it proves the region as well, which no
    /// check on the shape of a key could.
    @Test("verify proves the pair with a one-day active-users query")
    func verify() async throws {
        let (provider, http) = amplitude { _ in .ok(#"{"data":{"series":[[0]],"xValues":["20260301"]}}"#) }
        let account = try await provider.verify(usKeys, http: http)

        let seen = try #require(AmplitudeStub.requests().first)
        #expect(seen.url?.path == "/api/2/users")
        #expect(query(seen)["m"] == "active")
        #expect(query(seen)["i"] == "1")
        // One day, both ends the same.
        #expect(query(seen)["start"] == query(seen)["end"])

        // Half the API key, because Amplitude never names the project over
        // this API and the key is not ours to print in full.
        #expect(account.label == "project abcdef…")
        #expect(account.currency == nil)
        // No subset to narrow to: all three metrics read the same two
        // endpoints behind the same pair the call above just proved.
        #expect(account.unavailableMetrics.isEmpty)
    }

    @Test("and reports a rejected pair rather than storing it")
    func rejected() async throws {
        let (provider, http) = amplitude { _ in .init(status: 403, body: "") }
        await #expect(throws: ProviderFailure.authFailed(
            "Amplitude rejected these keys. Check they are the US project's pair "
                + "— the other region answers 403 too.")) {
            try await provider.verify(usKeys, http: http)
        }
    }
}
}
