import Foundation
import MetricsCore
import Testing

@testable import Providers

// MARK: - A stubbed Anthropic

/// Answers whatever the adapter asks for, and records that it asked.
///
/// A `URLProtocol` rather than a fake `ProviderHTTP`, so the allowlist and the
/// pinned headers are still in the path — which query a request actually
/// carried is one of the things these tests pin, and a stub above
/// `ProviderHTTP` could not see it.
final class AnthropicStub: URLProtocol {
    struct Reply {
        let status: Int
        let body: String
        var headers: [String: String] = [:]

        static func ok(_ body: String) -> Reply { Reply(status: 200, body: body) }
    }

    nonisolated(unsafe) static var reply: @Sendable (URLRequest) -> Reply = { _ in .ok("{}") }
    nonisolated(unsafe) static var seen: [URLRequest] = []

    static func session(_ reply: @escaping @Sendable (URLRequest) -> Reply) -> URLSession {
        Self.reply = reply
        Self.seen = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnthropicStub.self]
        return URLSession(configuration: configuration)
    }

    /// Every request made since the session was built, oldest first.
    static func requests() -> [URLRequest] { seen }

    /// One request's query, percent-decoding undone, as the adapter meant it.
    static func query(_ index: Int = 0) -> [(name: String, value: String)] {
        guard index < seen.count, let url = seen[index].url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return [] }
        return items.map { (name: $0.name, value: $0.value ?? "") }
    }

    static func value(_ name: String, in index: Int = 0) -> String? {
        query(index).first { $0.name == name }?.value
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

/// Claude, pointed at the stub. The allowlist is the adapter's own.
private func claude(
    _ reply: @escaping @Sendable (URLRequest) -> AnthropicStub.Reply
) -> (AnthropicProvider, ProviderHTTP) {
    let provider = AnthropicProvider()
    return (
        provider,
        ProviderHTTP(
            allowedHosts: provider.allowedHosts, session: AnthropicStub.session(reply))
    )
}

private let utc = TimeZone(identifier: "UTC")!

private func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: iso)!
}

private func window(
    _ metric: String, from: String = "2026-01-01T00:00:00Z", to: String = "2026-01-04T00:00:00Z",
    granularity: Granularity = .day, wantSeries: Bool = true, compare: Bool = false,
    currency: String = "USD"
) -> MetricWindow {
    MetricWindow(
        metric: metric, from: date(from), to: date(to), granularity: granularity,
        wantSeries: wantSeries, comparePrevious: compare, timeZone: utc,
        preferredCurrency: currency)
}

private let orgKey = ["admin_key": "sk-ant-admin01-0123456789abcdefghij"]
private let scopedKey = [
    "admin_key": "sk-ant-admin01-0123456789abcdefghij", "workspace_id": "wrkspc_1",
]

/// One day of usage, with every cache tier populated.
///
/// 100 uncached + 900 cache reads + 10 five-minute writes + 5 one-hour writes
/// is 1015 input tokens; 50 output makes 1065 in total.
private func usageBody(
    at: String = "2026-01-02T00:00:00Z", uncached: Int = 100, read: Int = 900,
    fiveMinute: Int = 10, oneHour: Int = 5, output: Int = 50
) -> String {
    """
    {"data":[{"starting_at":"\(at)","ending_at":"\(at)","results":[
      {"uncached_input_tokens":\(uncached),"cache_read_input_tokens":\(read),
       "cache_creation":{"ephemeral_5m_input_tokens":\(fiveMinute),
                         "ephemeral_1h_input_tokens":\(oneHour)},
       "output_tokens":\(output)}]}],"has_more":false,"next_page":null}
    """
}

// MARK: - Failures

/// Anthropic's statuses, in the buckets the caller acts differently on.
///
/// Tested through `failure(for:)` rather than over a stubbed session: what is
/// worth pinning is which bucket each status lands in.
@Suite("claude failures")
struct AnthropicFailureTests {
    private func response(_ status: Int, body: String = "", headers: [String: String] = [:])
        -> ProviderHTTP.Response
    {
        ProviderHTTP.Response(status: status, headers: headers, body: Data(body.utf8))
    }

    /// A nil wait would mean polling again on the next tick into the same
    /// wall. Sixty is the Worker's fallback.
    @Test("a spent quota carries the wait Claude asked for, or a minute")
    func rateLimited() {
        #expect(
            AnthropicProvider.failure(for: response(429, headers: ["Retry-After": "30"]))
                == .rateLimited("Claude asked us to wait.", retryAfter: 30))
        #expect(
            AnthropicProvider.failure(for: response(429))
                == .rateLimited("Claude asked us to wait.", retryAfter: 60))
    }

    @Test("a 5xx is their outage, retried rather than reported as a bad key")
    func down() {
        #expect(
            AnthropicProvider.failure(for: response(503))
                == .providerDown("Claude is having trouble."))
    }

    /// Throwing the body away leaves "Claude returned 400" on screen, and a
    /// bad query parameter then survives a release.
    @Test("any other 4xx keeps the explanation Claude sent, and names the status when it sent none")
    func explained() {
        // The 400 the cost report answers an unaligned start with, which is
        // the one this connector was unconnectable on.
        let body = #"{"error":{"message":"ending date must be after starting date"}}"#
        #expect(
            AnthropicProvider.failure(for: response(400, body: body))
                == .badResponse("ending date must be after starting date"))
        #expect(
            AnthropicProvider.failure(for: response(418)) == .badResponse("Claude returned 418."))
    }
}

// MARK: - Credentials

@Suite("claude credentials")
struct AnthropicCredentialTests {
    /// The form will not submit an empty required field, so this is a bug
    /// rather than user error — but an empty key reaches a live API either way
    /// and reads back as a revoked one.
    @Test("a missing admin key is refused before any request is made")
    func missingKey() {
        #expect(throws: ProviderFailure.self) { try AnthropicProvider.credentials([:]) }
    }

    /// The field is optional and means "total every workspace". Empty-string
    /// and absent have to behave the same: a user who typed a workspace id and
    /// then cleared it would otherwise be scoped to `""` and see nothing.
    @Test("an absent, empty or blank workspace is the whole organisation")
    func noWorkspace() throws {
        #expect(try AnthropicProvider.credentials(orgKey).workspaceId == nil)
        var blank = orgKey
        blank["workspace_id"] = ""
        #expect(try AnthropicProvider.credentials(blank).workspaceId == nil)
        blank["workspace_id"] = "   "
        #expect(try AnthropicProvider.credentials(blank).workspaceId == nil)
    }

    @Test("a workspace is kept when one was named")
    func workspace() throws {
        #expect(try AnthropicProvider.credentials(scopedKey).workspaceId == "wrkspc_1")
    }
}

// MARK: - The window plan

/// How far back the walk reaches, and when it refuses.
///
/// These metrics default to `hour` granularity, and an hourly walk reaches 28
/// days against the daily report's 124. A 90-day tile at hour width is a walk
/// that could never finish, which is what the refusal is for.
@Suite("claude window plan")
struct AnthropicPlanTests {
    @Test("a comparison widens the window backwards by its own length")
    func widens() throws {
        let plan = try AnthropicProvider.plan(
            window: window("tokens", from: "2026-01-08T00:00:00Z", to: "2026-01-15T00:00:00Z",
                           compare: true),
            bucket: .day)
        #expect(plan.comparePrevious)
        #expect(plan.start == date("2026-01-01T00:00:00Z"))
    }

    /// Dropped rather than paged for. The comparison doubles the buckets, and
    /// half an answer is worse than a number with no delta on it.
    @Test("a comparison that would not fit is dropped, and the window still answers")
    func comparisonDropped() throws {
        let plan = try AnthropicProvider.plan(
            window: window("tokens", from: "2026-01-01T00:00:00Z", to: "2026-01-21T00:00:00Z",
                           granularity: .hour, compare: true),
            bucket: .hour)
        #expect(!plan.comparePrevious)
        #expect(plan.start == date("2026-01-01T00:00:00Z"))
    }

    @Test("a window longer than the page budget is a sentence, not a truncated number")
    func tooLong() {
        #expect(throws: ProviderFailure.self) {
            try AnthropicProvider.plan(
                window: window("tokens", from: "2026-01-01T00:00:00Z", to: "2026-04-01T00:00:00Z",
                               granularity: .hour),
                bucket: .hour)
        }

        do {
            _ = try AnthropicProvider.plan(
                window: window("tokens", from: "2026-01-01T00:00:00Z", to: "2026-04-01T00:00:00Z",
                               granularity: .hour),
                bucket: .hour)
            Issue.record("expected the range to be refused")
        } catch let failure as ProviderFailure {
            // 168 buckets × 4 pages × one hour.
            #expect(failure.message.contains("28 days"))
        } catch {
            Issue.record("expected a ProviderFailure, got \(error)")
        }
    }

    /// 124 days at day width, so a 90-day tile answers where the same tile at
    /// hour width cannot.
    @Test("ninety days fits at day width")
    func ninetyDays() throws {
        let plan = try AnthropicProvider.plan(
            window: window("tokens", from: "2026-01-01T00:00:00Z", to: "2026-04-01T00:00:00Z"),
            bucket: .day)
        #expect(plan.start == date("2026-01-01T00:00:00Z"))
    }
}

// MARK: - Over the wire

/// Everything that goes through the stubbed session, in one serialised tree.
///
/// Nested inside a single suite rather than left as four siblings, because
/// `.serialized` orders a suite and its children and nothing else: a
/// `URLProtocol` is instantiated by `URLSession` with nowhere to hand
/// per-test state, so its reply and its record of what was asked are static.
/// Four sibling suites ran in parallel and each one read another's requests —
/// twenty-one failures that had nothing to do with the adapter.
@Suite("claude over the wire", .serialized)
struct AnthropicWireTests {
    /// Both answers Anthropic gives for "this key cannot read the Admin API"
    /// are the same status, so the message has to name all three causes: a bad
    /// key, a workspace-scoped key, and an individual account with no Admin
    /// API at all.
    @Test("a rejected admin key names the three things it could be")
    func rejected() async throws {
        for status in [401, 403] {
            let (provider, http) = claude { _ in AnthropicStub.Reply(status: status, body: "{}") }
            do {
                _ = try await provider.fetch(orgKey, window: window("tokens"), http: http)
                Issue.record("expected \(status) to be refused")
            } catch let failure as ProviderFailure {
                #expect(failure.message.contains("organisation Admin key"))
                #expect(failure.message.contains("individual accounts"))
                if case .authFailed = failure {} else { Issue.record("expected authFailed") }
            } catch {
                Issue.record("expected a ProviderFailure, got \(error)")
            }
        }
    }

    // MARK: - Tokens

    /// The arithmetic, which is the part a port silently gets wrong.
    @Suite("claude tokens", .serialized)
    struct AnthropicTokenTests {
        /// The one most easily got wrong. A cache-heavy workload reads most of its
        /// context rather than sending it, so `uncached_input_tokens` alone can be
        /// a tenth of the real volume.
        @Test("input is all four tiers added together")
        func input() async throws {
            let (provider, http) = claude { _ in .ok(usageBody()) }
            let value = try await provider.fetch(orgKey, window: window("input_tokens"), http: http)
            #expect(value.value == 1015)
            #expect(value.value != 100)
            // A count, not money: claiming a currency would have it formatted as one.
            #expect(value.currency == nil)
        }

        @Test("tokens is input plus output, and output is output alone")
        func totals() async throws {
            let (provider, http) = claude { _ in .ok(usageBody()) }
            #expect(
                try await provider.fetch(orgKey, window: window("tokens"), http: http).value
                    == 1065)

            let (second, httpSecond) = claude { _ in .ok(usageBody()) }
            #expect(
                try await second
                    .fetch(orgKey, window: window("output_tokens"), http: httpSecond).value == 50)
        }

        /// An organisation that uses no prompt caching gets a null here, and a
        /// required field would fail the whole page for it.
        @Test("a null cache_creation counts as no cache writes rather than failing the page")
        func noCaching() async throws {
            let body = """
                {"data":[{"starting_at":"2026-01-02T00:00:00Z","results":[
                  {"uncached_input_tokens":40,"cache_read_input_tokens":0,
                   "cache_creation":null,"output_tokens":2}]}],"has_more":false}
                """
            let (provider, http) = claude { _ in .ok(body) }
            #expect(
                try await provider.fetch(orgKey, window: window("tokens"), http: http).value == 42)
        }

        /// The report is already bucketed, so the width has to follow the
        /// granularity the tile asked for — a daily request answered at hour width
        /// would page through 24 times the data for the same picture.
        @Test("the bucket width follows the granularity on the window")
        func bucketWidth() async throws {
            let (provider, http) = claude { _ in .ok(usageBody()) }
            _ = try await provider.fetch(
                orgKey, window: window("tokens", granularity: .hour), http: http)
            #expect(AnthropicStub.value("bucket_width") == "1h")
            #expect(AnthropicStub.value("limit") == "168")

            let (second, httpSecond) = claude { _ in .ok(usageBody()) }
            _ = try await second.fetch(
                orgKey, window: window("tokens", granularity: .week), http: httpSecond)
            #expect(AnthropicStub.value("bucket_width") == "1d")
            #expect(AnthropicStub.value("limit") == "31")
        }

        /// Pinned, so a future default version cannot rename a field under an
        /// installed app that has no way to be updated for it.
        @Test("the API version is pinned and the key travels as x-api-key")
        func headers() async throws {
            let (provider, http) = claude { _ in .ok(usageBody()) }
            _ = try await provider.fetch(scopedKey, window: window("tokens"), http: http)
            let request = try #require(AnthropicStub.requests().first)
            #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            #expect(request.value(forHTTPHeaderField: "x-api-key") == scopedKey["admin_key"])
            // Not an Authorization header: Anthropic's Admin API reads neither a
            // bearer token nor basic auth, and sending one gets a 401 that reads
            // as a bad key.
            #expect(request.value(forHTTPHeaderField: "authorization") == nil)
        }

        @Test("a named workspace scopes the usage report, and an empty one does not")
        func workspaceFilter() async throws {
            let (provider, http) = claude { _ in .ok(usageBody()) }
            _ = try await provider.fetch(scopedKey, window: window("tokens"), http: http)
            #expect(AnthropicStub.value("workspace_ids[]") == "wrkspc_1")

            let (second, httpSecond) = claude { _ in .ok(usageBody()) }
            _ = try await second.fetch(orgKey, window: window("tokens"), http: httpSecond)
            #expect(AnthropicStub.value("workspace_ids[]") == nil)
        }

        /// Both halves are summed from the rows, not from the drawn buckets: a
        /// window edge is an instant and a bucket is a whole day.
        @Test("a comparison reports the later half and keeps the earlier one apart")
        func comparison() async throws {
            let body = """
                {"data":[
                  {"starting_at":"2025-12-30T00:00:00Z","results":[
                    {"uncached_input_tokens":7,"cache_read_input_tokens":0,"cache_creation":null,
                     "output_tokens":0}]},
                  {"starting_at":"2026-01-02T00:00:00Z","results":[
                    {"uncached_input_tokens":11,"cache_read_input_tokens":0,"cache_creation":null,
                     "output_tokens":0}]}],
                 "has_more":false}
                """
            let (provider, http) = claude { _ in .ok(body) }
            let value = try await provider.fetch(
                orgKey, window: window("tokens", compare: true), http: http)

            #expect(value.value == 11)
            #expect(value.previousValue == 7)
            // The widened half is never drawn: a chart over three days must not
            // grow six points because the tile wanted a delta.
            #expect(value.points.count == 4)
            #expect(value.points.reduce(0) { $0 + $1.v } == 11)
        }

        /// Nil rather than zero. A tile reading zero would draw "down 100%"
        /// against a window this fetch never looked at.
        @Test("no comparison leaves the previous value absent, not zero")
        func noComparison() async throws {
            let (provider, http) = claude { _ in .ok(usageBody()) }
            let value = try await provider.fetch(orgKey, window: window("tokens"), http: http)
            #expect(value.previousValue == nil)
        }

        /// A chart that skips an empty day draws a line straight over it.
        @Test("every bucket in the window is drawn, including the empty ones")
        func emptyBuckets() async throws {
            let (provider, http) = claude { _ in .ok(usageBody()) }
            let value = try await provider.fetch(orgKey, window: window("tokens"), http: http)
            #expect(value.points.count == 4)
            #expect(value.points.filter { $0.v == 0 }.count == 3)
        }

        @Test("a tile with no chart is given no points, and still the right number")
        func noSeries() async throws {
            let (provider, http) = claude { _ in .ok(usageBody()) }
            let value = try await provider.fetch(
                orgKey, window: window("tokens", wantSeries: false), http: http)
            #expect(value.points.isEmpty)
            #expect(value.value == 1065)
        }

        @Test("a metric this build has not been taught says so rather than failing obscurely")
        func unknownMetric() async throws {
            let (provider, http) = claude { _ in .ok(usageBody()) }
            await #expect(throws: ProviderFailure.self) {
                _ = try await provider.fetch(orgKey, window: window("active_users"), http: http)
            }
        }
    }

    // MARK: - Paging

    @Suite("claude paging", .serialized)
    struct AnthropicPagingTests {
        @Test("the next page cursor is followed")
        func followsCursor() async throws {
            let (provider, http) = claude { request in
                let query = request.url?.query ?? ""
                if query.contains("page=p2") {
                    return .ok(
                        """
                        {"data":[{"starting_at":"2026-01-03T00:00:00Z","results":[
                          {"uncached_input_tokens":5,"cache_read_input_tokens":0,
                           "cache_creation":null,"output_tokens":0}]}],"has_more":false}
                        """)
                }
                return .ok(
                    """
                    {"data":[{"starting_at":"2026-01-02T00:00:00Z","results":[
                      {"uncached_input_tokens":3,"cache_read_input_tokens":0,
                       "cache_creation":null,"output_tokens":0}]}],
                     "has_more":true,"next_page":"p2"}
                    """)
            }

            let value = try await provider.fetch(orgKey, window: window("tokens"), http: http)
            #expect(value.value == 8)
            #expect(AnthropicStub.requests().count == 2)
            #expect(AnthropicStub.value("page", in: 1) == "p2")
        }

        /// A provider returning fewer buckets per page than documented must not
        /// turn four planned requests into a loop that outlives the fetch.
        @Test("a provider that always says there is more is cut off at four requests")
        func capped() async throws {
            let (provider, http) = claude { _ in
                .ok(
                    """
                    {"data":[{"starting_at":"2026-01-02T00:00:00Z","results":[
                      {"uncached_input_tokens":1,"cache_read_input_tokens":0,
                       "cache_creation":null,"output_tokens":0}]}],
                     "has_more":true,"next_page":"more"}
                    """)
            }
            _ = try await provider.fetch(orgKey, window: window("tokens"), http: http)
            #expect(AnthropicStub.requests().count == 4)
        }
    }

    // MARK: - Spend

    @Suite("claude spend", .serialized)
    struct AnthropicSpendTests {
        /// The one that costs money to get wrong. `amount` is a decimal string
        /// already in *minor* units: "123.78912" is $1.2379, not $123.79. Reading
        /// it as dollars overstates the bill by a hundred times and looks
        /// plausible enough to ship.
        @Test("a cost is minor units already, never multiplied by a hundred")
        func minorUnits() async throws {
            let body = """
                {"data":[{"starting_at":"2026-01-02T00:00:00Z","results":[
                  {"amount":"123.78912","currency":"USD","workspace_id":null}]}],"has_more":false}
                """
            let (provider, http) = claude { _ in .ok(body) }
            let value = try await provider.fetch(orgKey, window: window("api_spend"), http: http)

            #expect(value.value == 124)
            #expect(value.value != 12_379)
            // Integer minor units plus an ISO 4217 code, as everywhere else.
            #expect(value.currency == "USD")
            #expect(value.value == value.value.rounded())
        }

        /// The cost report has no workspace filter, only a grouping. Without the
        /// `group_by` every row comes back with a null workspace and a scoped
        /// connection would silently report the whole organisation's bill.
        @Test("a scoped connection asks for the grouping and discards the other workspaces")
        func scoped() async throws {
            let body = """
                {"data":[{"starting_at":"2026-01-02T00:00:00Z","results":[
                  {"amount":"100","currency":"USD","workspace_id":"wrkspc_1"},
                  {"amount":"900","currency":"USD","workspace_id":"wrkspc_2"}]}],"has_more":false}
                """
            let (provider, http) = claude { _ in .ok(body) }
            let value = try await provider.fetch(scopedKey, window: window("api_spend"), http: http)

            #expect(AnthropicStub.value("group_by[]") == "workspace_id")
            #expect(value.value == 100)
        }

        /// Without a workspace the grouping is not asked for, and every row counts
        /// — including the null-workspace rows an ungrouped report returns.
        @Test("an organisation-wide connection asks for no grouping and totals everything")
        func unscoped() async throws {
            let body = """
                {"data":[{"starting_at":"2026-01-02T00:00:00Z","results":[
                  {"amount":"100","currency":"USD","workspace_id":null},
                  {"amount":"900","currency":"USD","workspace_id":null}]}],"has_more":false}
                """
            let (provider, http) = claude { _ in .ok(body) }
            let value = try await provider.fetch(orgKey, window: window("api_spend"), http: http)

            #expect(AnthropicStub.value("group_by[]") == nil)
            #expect(value.value == 1000)
        }

        /// Dropped rather than converted: there is no rate to convert at, and a
        /// total that silently added euros to dollars is worse than one that says
        /// what it left out.
        @Test("a charge in another currency is excluded and said so")
        func foreignCurrency() async throws {
            let body = """
                {"data":[{"starting_at":"2026-01-02T00:00:00Z","results":[
                  {"amount":"100","currency":"USD","workspace_id":null},
                  {"amount":"900","currency":"EUR","workspace_id":null}]}],"has_more":false}
                """
            let (provider, http) = claude { _ in .ok(body) }
            let value = try await provider.fetch(orgKey, window: window("api_spend"), http: http)

            #expect(value.value == 100)
            #expect(value.note == "EUR charges were excluded rather than converted.")
        }

        /// An unaligned start is snapped *up* to the next midnight, which silently
        /// drops the first day of the window — so it is floored here first.
        @Test("the cost window starts at midnight UTC, not at the instant asked for")
        func flooredStart() async throws {
            let body = #"{"data":[],"has_more":false}"#
            let (provider, http) = claude { _ in .ok(body) }
            _ = try await provider.fetch(
                orgKey,
                window: window(
                    "api_spend", from: "2026-01-02T13:45:00Z", to: "2026-01-05T00:00:00Z"),
                http: http)

            let start = try #require(AnthropicStub.value("starting_at"))
            #expect(start.hasPrefix("2026-01-02T00:00:00"))
            #expect(!start.contains("13:45"))
        }

        /// Answering at day width instead would draw twenty-four identical bars
        /// and read as though the money arrived in a lump.
        @Test("an hourly range is refused rather than answered at day width")
        func hourlyRefused() async throws {
            let (provider, http) = claude { _ in .ok(#"{"data":[],"has_more":false}"#) }
            await #expect(
                throws: ProviderFailure.unsupported(
                    "Claude reports cost once a day. Pick a range of 7 days or longer.")
            ) {
                _ = try await provider.fetch(
                    orgKey, window: window("api_spend", granularity: .hour), http: http)
            }
            #expect(AnthropicStub.requests().isEmpty)
        }

        /// A number that cannot be read is refused rather than counted as nothing:
        /// a bill silently short by a day is worse than a tile saying it could not
        /// read the answer.
        @Test("an unreadable amount is a bad response, not a zero")
        func unreadableAmount() async throws {
            let body = """
                {"data":[{"starting_at":"2026-01-02T00:00:00Z","results":[
                  {"amount":"lots","currency":"USD","workspace_id":null}]}],"has_more":false}
                """
            let (provider, http) = claude { _ in .ok(body) }
            await #expect(throws: ProviderFailure.self) {
                _ = try await provider.fetch(orgKey, window: window("api_spend"), http: http)
            }
        }
    }

    // MARK: - Verify

    @Suite("claude verify", .serialized)
    struct AnthropicVerifyTests {
        private static let usage = #"{"data":[],"has_more":false}"#

        private func isCost(_ request: URLRequest) -> Bool {
            request.url?.path.contains("cost_report") == true
        }

        @Test("a good key reads usage and cost, and is labelled by its workspace")
        func both() async throws {
            let (provider, http) = claude { _ in .ok(Self.usage) }
            let account = try await provider.verify(scopedKey, http: http)

            #expect(account.label == "wrkspc_1")
            #expect(account.currency == "USD")
            #expect(account.unavailableMetrics.isEmpty)
            // Both reports are probed, in that order. The second is not a health
            // check: it is how a key that cannot read cost is detected.
            #expect(AnthropicStub.requests().count == 2)
            #expect(AnthropicStub.requests()[0].url?.path.contains("usage_report") == true)
            #expect(isCost(AnthropicStub.requests()[1]))
        }

        /// The Admin API exposes no organisation name, and the field is not
        /// optional here as it is on the Worker, so the provider's own name is
        /// what an organisation-wide key gets.
        @Test("an organisation-wide key is labelled Claude")
        func orgLabel() async throws {
            let (provider, http) = claude { _ in .ok(Self.usage) }
            #expect(try await provider.verify(orgKey, http: http).label == "Claude")
        }

        /// Narrowed rather than fatal: token volume is useful on its own, and the
        /// two reports are separately available on a scoped key.
        @Test("a key that cannot read cost keeps the token metrics and loses spend")
        func narrowsSpend() async throws {
            for status in [401, 403, 400, 404] {
                let (provider, http) = claude { request in
                    request.url?.path.contains("cost_report") == true
                        ? AnthropicStub.Reply(status: status, body: "{}")
                        : .ok(Self.usage)
                }
                let account = try await provider.verify(orgKey, http: http)
                #expect(account.unavailableMetrics == ["api_spend"])
            }
        }

        /// `unavailableMetrics` is written once at connect, so letting a 503 pass
        /// would hide spend until the user reconnected.
        @Test("an outage during the cost probe fails the check rather than narrowing it")
        func outageIsFatal() async throws {
            let (provider, http) = claude { request in
                request.url?.path.contains("cost_report") == true
                    ? AnthropicStub.Reply(status: 503, body: "{}") : .ok(Self.usage)
            }
            await #expect(throws: ProviderFailure.providerDown("Claude is having trouble.")) {
                _ = try await provider.verify(orgKey, http: http)
            }
        }

        @Test("a rejected key stops the check at the first call")
        func rejected() async throws {
            let (provider, http) = claude { _ in AnthropicStub.Reply(status: 401, body: "{}") }
            await #expect(throws: ProviderFailure.self) {
                _ = try await provider.verify(orgKey, http: http)
            }
            #expect(AnthropicStub.requests().count == 1)
        }

        @Test("a missing admin key is refused before any request is made")
        func missingKey() async throws {
            let (provider, http) = claude { _ in .ok(Self.usage) }
            await #expect(throws: ProviderFailure.self) {
                _ = try await provider.verify([:], http: http)
            }
            #expect(AnthropicStub.requests().isEmpty)
        }
    }
}
