import Foundation
import MetricsCore
import Testing

@testable import Providers

/// PostHog's statuses, in the buckets the caller acts differently on.
///
/// Tested through `failure(for:region:)` rather than over a stubbed session:
/// what is worth pinning is which bucket each status lands in, and this
/// connector has the two mappings most easily lost in a port — a 401 that is
/// as likely to be the wrong region as a bad key, and a spent *query budget*
/// that must not read as a broken key.
@Suite("posthog failures")
struct PostHogFailureTests {
    private func response(_ status: Int, body: String = "", headers: [String: String] = [:])
        -> ProviderHTTP.Response
    {
        ProviderHTTP.Response(status: status, headers: headers, body: Data(body.utf8))
    }

    /// The message names the region because US and EU are separate databases:
    /// a US key presented to the EU host is a key that does not exist there,
    /// and PostHog answers the same 401 as for a revoked one. Without this
    /// somebody rolls a key that was fine.
    @Test("a 401 names the region as well as the key")
    func badKey() {
        #expect(
            PostHogProvider.failure(for: response(401), region: .eu)
                == .authFailed(
                    "PostHog rejected this key. Check it is a EU Cloud key — the other region "
                        + "answers 401 too."))
        #expect(
            PostHogProvider.failure(for: response(401), region: .us).message.contains("US Cloud key"))
    }

    /// The one this connector exists to get right. PostHog bills `/query`
    /// against an hourly bytes-read budget, so a 429 is what a *working* key
    /// gets after a busy hour. Read as `authFailed` it would mark the
    /// integration broken and stop polling, and the user would have to
    /// reconnect to recover from being briefly over budget.
    @Test("a spent query budget is rate limiting, not a broken key")
    func quotaSpent() {
        let failure = PostHogProvider.failure(
            for: response(
                429, body: #"{"detail":"Query exceeds the bytes read limit."}"#,
                headers: ["Retry-After": "30"]),
            region: .us)
        #expect(failure == .rateLimited("Query exceeds the bytes read limit.", retryAfter: 30))
    }

    /// A nil wait means the refresh loop retries on its own tick, which on a
    /// spent quota is immediately — and spends it again.
    @Test("a quota with no Retry-After still waits a minute")
    func quotaNoHeader() {
        #expect(
            PostHogProvider.failure(for: response(429), region: .us)
                == .rateLimited("PostHog's query quota is spent.", retryAfter: 60))
    }

    /// The status stays in the message: a 403 from a host that normally says
    /// 401 is a WAF in front of the provider, which is a different afternoon
    /// from a key missing a scope.
    @Test("a 403 keeps its status and PostHog's words")
    func forbidden() {
        let failure = PostHogProvider.failure(
            for: response(403, body: #"{"detail":"Permission denied: query:read"}"#), region: .us)
        #expect(
            failure == .authFailed("PostHog rejected the credentials (403): Permission denied: query:read"))
    }

    @Test("a 5xx is their outage, retried rather than reported as a bad key")
    func down() {
        #expect(
            PostHogProvider.failure(for: response(503), region: .us)
                == .providerDown("PostHog is having trouble."))
    }

    /// Throwing the body away leaves "PostHog returned 400" on screen, and on
    /// this connector the body is the only thing that names the broken part
    /// of the query.
    @Test("a bad query keeps the explanation PostHog sent")
    func explained() {
        let failure = PostHogProvider.failure(
            for: response(400, body: #"{"detail":"Unable to resolve field: persn_id"}"#),
            region: .us)
        #expect(failure == .badResponse("Unable to resolve field: persn_id"))
    }

    @Test("and says the status when it sent none")
    func unexplained() {
        #expect(
            PostHogProvider.failure(for: response(418), region: .us)
                == .badResponse("PostHog returned 418."))
    }

    /// A console deep link would eat the whole message budget, and removing
    /// only the URL leaves "Fix it at ." behind.
    @Test("a sentence carrying a link is dropped whole")
    func links() {
        let failure = PostHogProvider.failure(
            for: response(
                400,
                body: #"{"detail":"That project is archived. See https://us.posthog.com/settings/x."}"#),
            region: .us)
        #expect(failure == .badResponse("That project is archived."))
    }
}

@Suite("posthog credentials")
struct PostHogCredentialTests {
    @Test("a missing key is refused before any request is made")
    func missingKey() {
        #expect(throws: ProviderFailure.self) { try PostHogProvider.credentials([:]) }
    }

    /// Absent is US, matching the manifest field's default: a connection
    /// stored before the region field existed is a US one.
    @Test("an absent region is the United States")
    func defaultRegion() throws {
        let creds = try PostHogProvider.credentials(["api_key": "phx_abcdefgh"])
        #expect(creds.region == .us)
        #expect(creds.host == "us.posthog.com")
        #expect(creds.projectId == nil)
    }

    @Test("the EU region picks the EU host")
    func euRegion() throws {
        let creds = try PostHogProvider.credentials(["api_key": "phx_abcdefgh", "region": "EU"])
        #expect(creds.host == "eu.posthog.com")
    }

    /// Refused rather than defaulted to US: guessing would send an EU key to
    /// the US host, which answers the 401 a revoked key gets.
    @Test("an unreadable region is refused rather than guessed")
    func unknownRegion() {
        #expect(throws: ProviderFailure.self) {
            try PostHogProvider.credentials(["api_key": "phx_abcdefgh", "region": "uk"])
        }
    }

    /// The id is interpolated into a URL path, so anything that is not digits
    /// is refused here rather than sent.
    @Test("a project ID that is not a number is refused")
    func badProject() {
        #expect(throws: ProviderFailure.self) {
            try PostHogProvider.credentials(["api_key": "phx_abcdefgh", "project_id": "acme"])
        }
    }
}

/// Serialised because the stub's routing table is static: `URLProtocol` is
/// instantiated by `URLSession` and there is nowhere to hand per-test state.
@Suite("posthog metrics", .serialized)
struct PostHogMetricTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: iso)!
    }

    private func unix(_ iso: String) -> Int { Int(date(iso).timeIntervalSince1970) }

    private func window(
        _ metric: String, from: String = "2026-01-08T00:00:00Z",
        to: String = "2026-01-15T00:00:00Z", granularity: Granularity = .day,
        wantSeries: Bool = true, compare: Bool = true
    ) -> MetricWindow {
        MetricWindow(
            metric: metric, from: date(from), to: date(to), granularity: granularity,
            wantSeries: wantSeries, comparePrevious: compare, timeZone: utc)
    }

    private func fetch(
        _ window: MetricWindow, credentials: [String: String] = [
            "api_key": "phx_abcdefgh", "project_id": "42", "region": "us",
        ]
    ) async throws -> MetricValue {
        try await PostHogProvider().fetch(
            credentials, window: window,
            http: ProviderHTTP(
                allowedHosts: PostHogProvider().allowedHosts, session: PostHogStub.session()))
    }

    private static let identity = #"""
        {"team":{"id":42,"name":"Website"},"organization":{"name":"Acme"}}
        """#

    /// One call covers the window and the one before it, split here by
    /// timestamp. Halving the calls matters on an endpoint billed by bytes
    /// read, and getting the boundary wrong moves a day's events into the
    /// comparison.
    @Test("a counted metric takes one query and splits it by the window edge")
    func eventsSplit() async throws {
        PostHogStub.reset(
            queries: [
                #"""
                {"results":[
                  [\#(unix("2026-01-05T00:00:00Z")), 5],
                  [\#(unix("2026-01-08T00:00:00Z")), 10],
                  [\#(unix("2026-01-09T00:00:00Z")), "20"]
                ]}
                """#
            ])

        let value = try await fetch(window("events"))

        #expect(value.value == 30)
        #expect(value.previousValue == 5)
        // One query, not two: `count()` sums, so the headline is the sum of
        // its own buckets and a second aggregate would be paid for nothing.
        #expect(PostHogStub.queries.count == 1)
        // The requested window only, so the chart does not draw the half that
        // exists solely to be the delta.
        #expect(value.points.count == 8)
        #expect(value.points[0].v == 10)
        #expect(value.points[1].v == 20)
        #expect(value.points.dropFirst(2).allSatisfy { $0.v == 0 })
    }

    /// The query is the contract. A reworded one is a different number, and
    /// nobody notices until the tile disagrees with PostHog's own dashboard.
    @Test("the bucket query is the one the Worker sends")
    func bucketQuery() async throws {
        PostHogStub.reset(queries: [#"{"results":[]}"#])
        _ = try await fetch(window("events"))

        // Bound to a name rather than written inside `#expect`: four
        // interpolated concatenations inside the macro's expansion defeat the
        // type checker.
        let expected =
            "SELECT toUnixTimestamp(toStartOfDay(timestamp)) AS bucket, count() AS value "
            + "FROM events WHERE timestamp >= toDateTime(\(unix("2026-01-01T00:00:00Z"))) "
            + "AND timestamp < toDateTime(\(unix("2026-01-15T00:00:00Z"))) "
            + "GROUP BY bucket ORDER BY bucket"
        #expect(PostHogStub.queries.first == expected)
        // The name lands in PostHog's own query_log, so a user looking at
        // what is hitting their project sees us by name.
        #expect(PostHogStub.names.first == "notch:events.series")
    }

    /// Hourly floors to the hour; a week is rolled up from days here rather
    /// than asked of ClickHouse, which keeps every timezone decision in one
    /// place.
    @Test("an hourly window floors to the hour, a weekly one to the day")
    func floors() async throws {
        PostHogStub.reset(queries: [#"{"results":[]}"#])
        _ = try await fetch(window("events", granularity: .hour))
        #expect(PostHogStub.queries.first?.contains("toStartOfHour(timestamp)") == true)

        PostHogStub.reset(queries: [#"{"results":[]}"#])
        _ = try await fetch(window("events", granularity: .week))
        #expect(PostHogStub.queries.first?.contains("toStartOfDay(timestamp)") == true)
    }

    /// Without the flag the query must not be widened: a row from before the
    /// window would become a delta nobody asked for, and the extra half is
    /// bytes somebody pays for.
    @Test("no comparison means no widening and no previous value")
    func noCompare() async throws {
        PostHogStub.reset(queries: [#"{"results":[[\#(unix("2026-01-08T00:00:00Z")), 10]]}"#])
        let value = try await fetch(window("events", compare: false))

        #expect(value.value == 10)
        // nil, never zero: zero renders as "down 100%".
        #expect(value.previousValue == nil)
        #expect(
            PostHogStub.queries.first?
                .contains("timestamp >= toDateTime(\(unix("2026-01-08T00:00:00Z")))") == true)
    }

    /// The headline is not the sum of its chart: one person active on three
    /// days is three bars and one user. That second query is the whole reason
    /// `Spec.distinct` exists.
    @Test("a distinct metric pays for a second query rather than summing its bars")
    func distinctTotals() async throws {
        PostHogStub.reset(
            queries: [
                #"""
                {"results":[
                  [\#(unix("2026-01-06T00:00:00Z")), 3],
                  [\#(unix("2026-01-08T00:00:00Z")), 4],
                  [\#(unix("2026-01-09T00:00:00Z")), 4]
                ]}
                """#,
                // ClickHouse serialises the boolean as 0/1.
                #"{"results":[[1, 5],[0, 3]]}"#,
            ])

        let value = try await fetch(window("active_users"))

        // Five, not the eight its own bars add up to.
        #expect(value.value == 5)
        #expect(value.previousValue == 3)
        #expect(value.points[0].v == 4)

        #expect(PostHogStub.queries.count == 2)
        let expected =
            "SELECT timestamp >= toDateTime(\(unix("2026-01-08T00:00:00Z"))) AS is_current, "
            + "count(DISTINCT person_id) AS value FROM events "
            + "WHERE timestamp >= toDateTime(\(unix("2026-01-01T00:00:00Z"))) "
            + "AND timestamp < toDateTime(\(unix("2026-01-15T00:00:00Z"))) "
            + "GROUP BY is_current"
        #expect(PostHogStub.queries[1] == expected)
        #expect(PostHogStub.names[1] == "notch:active_users.total")
    }

    /// A real boolean rather than 0/1 must land in the same half; nothing
    /// promises ClickHouse keeps serialising it as an integer.
    @Test("a boolean is_current is read as the current half")
    func booleanIsCurrent() async throws {
        PostHogStub.reset(
            queries: [#"{"results":[]}"#, #"{"results":[[true, 9],[false, 2]]}"#])
        let value = try await fetch(window("sessions"))
        #expect(value.value == 9)
        #expect(value.previousValue == 2)
    }

    /// Each metric's `WHERE` is part of its definition: pageviews without the
    /// event filter is every event there is.
    @Test("each metric carries its own table, aggregate and filter")
    func specs() async throws {
        PostHogStub.reset(queries: [#"{"results":[]}"#])
        _ = try await fetch(window("pageviews"))
        #expect(PostHogStub.queries.first?.contains("AND event = '$pageview'") == true)

        PostHogStub.reset(queries: [#"{"results":[]}"#])
        _ = try await fetch(window("new_users"))
        let query = PostHogStub.queries.first ?? ""
        // The persons table and its own time column — a new user is a profile
        // PostHog created, not an event.
        #expect(query.contains("FROM persons"))
        #expect(query.contains("toStartOfDay(created_at)"))

        PostHogStub.reset(queries: [#"{"results":[]}"#, #"{"results":[]}"#])
        _ = try await fetch(window("sessions"))
        #expect(
            PostHogStub.queries.first?
                .contains("count(DISTINCT properties.$session_id)") == true)
        #expect(
            PostHogStub.queries.first?
                .contains("AND properties.$session_id IS NOT NULL") == true)
    }

    /// A metric this build has not been taught is not a bug: the catalogue is
    /// the Worker's, and the caller falls back to the API.
    @Test("an unknown metric says so rather than querying for nothing")
    func unknownMetric() async {
        PostHogStub.reset(queries: [])
        let outcome = await Result { try await fetch(window("funnel_conversion")) }
        #expect(throws: ProviderFailure.self) { try outcome.get() }
        #expect(PostHogStub.paths.isEmpty)
    }

    // MARK: - The project, and the host

    /// A blank project is the documented default, resolved from the key's own
    /// identity — which is a plain CRUD call, not a `/query`, so it does not
    /// touch the hourly read budget.
    @Test("a blank project falls back to the key's own team")
    func projectFallback() async throws {
        PostHogStub.reset(
            routes: ["/api/users/@me/": (200, Self.identity)], queries: [#"{"results":[]}"#])

        _ = try await fetch(
            window("events"), credentials: ["api_key": "phx_abcdefgh", "region": "us"])

        #expect(PostHogStub.paths == ["/api/users/@me/", "/api/projects/42/query/"])
    }

    /// A typed id wins, so somebody with several projects can point two
    /// connections at two of them — and the identity call is skipped.
    @Test("a typed project is used without asking who the key belongs to")
    func projectTyped() async throws {
        PostHogStub.reset(queries: [#"{"results":[]}"#])
        _ = try await fetch(window("events"))
        #expect(PostHogStub.paths == ["/api/projects/42/query/"])
    }

    @Test("a key with no default project asks for one rather than guessing")
    func noDefaultProject() async {
        PostHogStub.reset(routes: ["/api/users/@me/": (200, #"{"team":null}"#)], queries: [])
        let outcome = await Result {
            try await fetch(window("events"), credentials: ["api_key": "phx_abcdefgh"])
        }
        #expect(throws: ProviderFailure.self) { try outcome.get() }
        if case .failure(let error as ProviderFailure) = outcome {
            #expect(error == .unsupported("This key has no default project. Enter a project ID."))
        }
    }

    /// The allowlist permits the pair; the stored region picks between them.
    /// A request to the wrong one is a 401 the user reads as a revoked key.
    @Test("the stored region chooses the host")
    func regionHost() async throws {
        PostHogStub.reset(queries: [#"{"results":[]}"#])
        _ = try await fetch(
            window("events"),
            credentials: ["api_key": "phx_abcdefgh", "project_id": "42", "region": "eu"])
        #expect(PostHogStub.hosts == ["eu.posthog.com"])
    }

    // MARK: - Verify

    /// Two calls in the Worker's order: the identity names the connection and
    /// proves `user:read`, and the literal proves `query:read` on this
    /// project without reading an event row off the budget.
    @Test("verify names the organisation and the project, in two calls")
    func verify() async throws {
        PostHogStub.reset(
            routes: ["/api/users/@me/": (200, Self.identity)], queries: [#"{"results":[[1]]}"#])

        let account = try await PostHogProvider().verify(
            ["api_key": "phx_abcdefgh", "region": "us"],
            http: ProviderHTTP(
                allowedHosts: PostHogProvider().allowedHosts, session: PostHogStub.session()))

        // "Acme — Website", so two projects in one org are told apart and two
        // orgs with a "Website" each are too.
        #expect(account.label == "Acme — Website")
        #expect(account.currency == nil)
        #expect(account.unavailableMetrics.isEmpty)
        #expect(PostHogStub.queries == ["SELECT 1"])
        #expect(PostHogStub.names == ["notch:verify"])
    }

    /// The project id is all there is to call it when PostHog named neither
    /// the team nor the organisation.
    @Test("an unnamed project falls back to its id")
    func verifyUnnamed() async throws {
        PostHogStub.reset(
            routes: ["/api/users/@me/": (200, #"{"team":{"id":42}}"#)],
            queries: [#"{"results":[[1]]}"#])
        let account = try await PostHogProvider().verify(
            ["api_key": "phx_abcdefgh"],
            http: ProviderHTTP(
                allowedHosts: PostHogProvider().allowedHosts, session: PostHogStub.session()))
        #expect(account.label == "Project 42")
    }

    /// The key already answered `/users/@me/`, so a refusal on the query is
    /// about the scope or the project. Repeating "your key was rejected"
    /// sends somebody off to make another key with the same scope missing.
    @Test("a key that cannot query names the scope rather than the key")
    func verifyScope() async {
        PostHogStub.reset(
            routes: [
                "/api/users/@me/": (200, Self.identity),
                "/api/projects/42/query/": (403, #"{"detail":"Permission denied"}"#),
            ], queries: [])

        let outcome = await Result {
            try await PostHogProvider().verify(
                ["api_key": "phx_abcdefgh"],
                http: ProviderHTTP(
                    allowedHosts: PostHogProvider().allowedHosts, session: PostHogStub.session()))
        }
        if case .failure(let error as ProviderFailure) = outcome {
            #expect(
                error
                    == .authFailed(
                        "This key cannot run queries on that project. Give it the Query Read "
                            + "scope, and check the project ID."))
        } else {
            Issue.record("a 403 on the query should not verify")
        }
    }

    /// A 429 on the probe is not a verdict on the key, so it must not be
    /// rewritten into one — the user would reconnect to fix a quota.
    @Test("a spent quota during verify stays a quota problem")
    func verifyQuota() async {
        PostHogStub.reset(
            routes: [
                "/api/users/@me/": (200, Self.identity),
                "/api/projects/42/query/": (429, ""),
            ], queries: [])

        let outcome = await Result {
            try await PostHogProvider().verify(
                ["api_key": "phx_abcdefgh"],
                http: ProviderHTTP(
                    allowedHosts: PostHogProvider().allowedHosts, session: PostHogStub.session()))
        }
        if case .failure(let error as ProviderFailure) = outcome {
            #expect(error == .rateLimited("PostHog's query quota is spent.", retryAfter: 60))
        } else {
            Issue.record("a 429 on the query should not verify")
        }
    }
}

/// Answers PostHog's two endpoints, and records what was asked.
///
/// `URLProtocol` is instantiated by `URLSession` with no way to hand it
/// per-instance state, hence the static tables — and hence `.serialized` on
/// the suite that uses it. Queries are served from a list in order, because
/// a distinct metric sends two to the same path and they are not the same
/// answer.
final class PostHogStub: URLProtocol {
    nonisolated(unsafe) private static var routes: [String: (Int, String)] = [:]
    nonisolated(unsafe) private static var pending: [String] = []
    nonisolated(unsafe) private static var seen: [URL] = []
    /// The HogQL text of each query, in the order it was sent.
    nonisolated(unsafe) static var queries: [String] = []
    /// Each query's `name`, which is what a user sees in their own query_log.
    nonisolated(unsafe) static var names: [String] = []

    static func reset(routes: [String: (Int, String)] = [:], queries sent: [String]) {
        self.routes = routes
        pending = sent
        seen = []
        queries = []
        names = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PostHogStub.self]
        return URLSession(configuration: configuration)
    }

    /// `URL.path` drops a trailing slash, and every PostHog route has one:
    /// without it the API 301s and `ProviderHTTP` refuses to carry a bearer
    /// token through a redirect. So routing is on the raw path, which keeps
    /// it, and a test can pin it.
    private static func path(of url: URL) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
    }

    static var paths: [String] { seen.map(path(of:)) }
    static var hosts: [String] { seen.compactMap(\.host) }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let path = Self.path(of: url)
        Self.seen.append(url)

        // `httpBody` is nil on a request that has been through URLSession, so
        // the stream is what carries it.
        if let body = request.httpBody ?? request.httpBodyStream.map(Self.drain),
           let sent = try? JSONDecoder().decode(Sent.self, from: body) {
            Self.queries.append(sent.query.query)
            Self.names.append(sent.name)
        }

        var status = 404
        var json = #"{"detail":"no stub"}"#
        if let routed = Self.routes[path] {
            (status, json) = routed
        } else if path.hasSuffix("/query/"), !Self.pending.isEmpty {
            status = 200
            json = Self.pending.removeFirst()
        }

        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private struct Sent: Decodable {
        struct Node: Decodable { let query: String }
        let query: Node
        let name: String
    }

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
