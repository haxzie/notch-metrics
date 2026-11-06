import Foundation
import MetricsCore
import Testing

@testable import Providers

/// GitHub's statuses, in the buckets the caller acts differently on.
///
/// Tested through `failure(for:)` rather than over the network: what is worth
/// pinning is which bucket each status lands in, and this connector has the
/// two mappings most easily lost in a port — a spent quota that arrives as a
/// 403, and a 404 that is about one repository rather than about the token.
@Suite("github failures")
struct GitHubFailureTests {
    private func response(_ status: Int, body: String = "", headers: [String: String] = [:])
        -> ProviderHTTP.Response
    {
        ProviderHTTP.Response(status: status, headers: headers, body: Data(body.utf8))
    }

    /// The one this connector exists to get right. Read as `authFailed` a
    /// spent quota marks the integration broken and stops polling it, so a
    /// user whose token is fine has to reconnect to recover from being briefly
    /// over quota.
    @Test("a spent quota is rate limiting, not a bad token, even as a 403")
    func quotaSpent() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let failure = GitHubProvider.failure(
            for: response(
                403,
                headers: [
                    "x-ratelimit-remaining": "0",
                    "x-ratelimit-reset": "1000120",
                ]),
            now: now)
        #expect(failure == .rateLimited("GitHub's rate limit is spent.", retryAfter: 120))
    }

    /// A reset that has already passed would otherwise schedule a retry in
    /// zero seconds, which the refresh loop runs immediately and spends again.
    @Test("a reset in the past still waits a second")
    func quotaResetPassed() {
        let failure = GitHubProvider.failure(
            for: response(403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1"]),
            now: Date(timeIntervalSince1970: 1_000_000))
        #expect(failure == .rateLimited("GitHub's rate limit is spent.", retryAfter: 1))
    }

    @Test("a reset GitHub did not send is a minute")
    func quotaNoReset() {
        let failure = GitHubProvider.failure(for: response(403, headers: ["x-ratelimit-remaining": "0"]))
        #expect(failure == .rateLimited("GitHub's rate limit is spent.", retryAfter: 60))
    }

    /// The secondary limit, which sends `retry-after` and leaves the primary
    /// counter alone.
    @Test("a secondary limit carries the wait GitHub asked for")
    func secondaryLimit() {
        let failure = GitHubProvider.failure(
            for: response(403, headers: ["Retry-After": "45", "x-ratelimit-remaining": "4999"]))
        #expect(failure == .rateLimited("GitHub asked us to wait.", retryAfter: 45))
    }

    @Test("a 403 with quota left is still a credentials problem")
    func forbiddenWithQuota() {
        let failure = GitHubProvider.failure(
            for: response(403, headers: ["x-ratelimit-remaining": "4999"]))
        #expect(failure == .authFailed("GitHub rejected the credentials (403)."))
    }

    /// The status stays in the message: a 403 from a host that normally says
    /// 401 is a WAF in front of the provider, which is a different afternoon
    /// from a mistyped token.
    @Test("a rejected token is an auth failure, and carries GitHub's own words")
    func badToken() {
        let failure = GitHubProvider.failure(
            for: response(401, body: #"{"message":"Bad credentials"}"#))
        #expect(failure == .authFailed("GitHub rejected the credentials (401): Bad credentials"))
    }

    /// The code matters more than the message. `authFailed` marks the whole
    /// connection broken and asks for a reconnect that cannot fix a renamed
    /// repository — while the same token is answering for every other tile in
    /// the notch.
    @Test("a 404 blames the repository, not the connection")
    func notFound() {
        let failure = GitHubProvider.failure(for: response(404, body: #"{"message":"Not Found"}"#))
        #expect(
            failure
                == .unsupported(
                    "That repository could not be read. "
                        + "Check the name, and that this account can see it."))
    }

    /// A `public_repo` token keeps working for public repositories, so a
    /// private one 404s with nothing to say why and the repository name looks
    /// like the fault. A classic token's granted scopes come back on every
    /// response, so the token can say so itself.
    @Test("a classic token that cannot reach private repositories says so")
    func narrowScope() {
        let failure = GitHubProvider.failure(
            for: response(404, headers: ["x-oauth-scopes": "public_repo, read:user"]))
        #expect(failure.message.contains("public repositories only"))
        #expect(failure == .unsupported(failure.message))
    }

    @Test("a token that already has repo is not blamed for the 404")
    func wideScope() {
        let failure = GitHubProvider.failure(
            for: response(404, headers: ["x-oauth-scopes": "repo, read:user"]))
        #expect(failure.message.contains("could not be read"))
    }

    /// A fine-grained token sends no `x-oauth-scopes` at all. Guessing from its
    /// absence would blame the permissions for a repository that was simply
    /// renamed, which is the more common fault and the one a user can fix.
    @Test("a token whose permissions cannot be read is not blamed either")
    func unreadableScope() {
        let failure = GitHubProvider.failure(for: response(404))
        #expect(failure.message.contains("could not be read"))
        #expect(!failure.message.contains("public repositories only"))
    }

    @Test("a 5xx is their outage, retried rather than reported as a bad token")
    func down() {
        #expect(GitHubProvider.failure(for: response(503)) == .providerDown("GitHub is having trouble."))
    }

    @Test("any other 4xx keeps the explanation GitHub sent")
    func explained() {
        let failure = GitHubProvider.failure(
            for: response(
                422,
                body: #"{"message":"Validation Failed","errors":[{"message":"q is too long"}]}"#))
        #expect(failure == .badResponse("Validation Failed"))
    }

    @Test("and says the status when it sent none")
    func unexplained() {
        #expect(GitHubProvider.failure(for: response(418)) == .badResponse("GitHub returned 418."))
    }

    /// A 429 that named neither a wait nor a spent quota. A nil wait would have
    /// the refresh loop retry on its own tick, which on a spent quota is
    /// immediately.
    @Test("a bare 429 waits a minute")
    func bareRateLimit() {
        #expect(
            GitHubProvider.failure(for: response(429))
                == .rateLimited("GitHub asked us to wait.", retryAfter: 60))
    }

    /// The failure this prevents is a user's own token ending up on screen, and
    /// from there in a screenshot in a support thread.
    @Test("a token GitHub quoted back at us is redacted before it reaches a tile")
    func redaction() {
        let body = #"{"message":"Token ghp_11ABCDEFGHIJKLMNOP is not valid"}"#
        #expect(GitHubProvider.message(in: Data(body.utf8)) == "Token ghp_… is not valid")
    }

    /// GitHub appends a documentation link to most messages. Removing just the
    /// URL would leave "See the docs at ." behind.
    @Test("a sentence carrying a URL goes whole")
    func links() {
        let body = #"{"message":"Bad credentials. See https://docs.github.com/rest for help."}"#
        #expect(GitHubProvider.message(in: Data(body.utf8)) == "Bad credentials.")
    }

    @Test("an unreadable body is dropped rather than rendered raw")
    func unreadable() {
        #expect(GitHubProvider.message(in: Data("<html>502 Bad Gateway</html>".utf8)) == nil)
    }
}

/// The widget's parameters, which reach a request path and a query string.
@Suite("github parameters")
struct GitHubParameterTests {
    private let legacy = ["access_token": "gho_11ABCDEFGHIJKLMNOP", "repository": "haxzie/notch-metrics"]

    private func window(_ params: [String: String], metric: String = "stars") -> MetricWindow {
        MetricWindow(
            metric: metric, from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 1),
            granularity: .day, wantSeries: false, params: params)
    }

    @Test("the repository comes from the widget, not the connection")
    func fromWidget() throws {
        let name = try GitHubProvider.repositoryFor(legacy, window: window(["repository": "vercel/next.js"]))
        #expect(name == "vercel/next.js")
    }

    /// Widgets made before the repository moved onto the widget carry no param.
    /// Without this fallback every one of them would blank on the release that
    /// shipped the move.
    @Test("a pre-existing connection's repository is still honoured")
    func legacyFallback() throws {
        #expect(try GitHubProvider.repositoryFor(legacy, window: window([:])) == "haxzie/notch-metrics")
    }

    @Test("a widget with no repository anywhere says which widget needs attention")
    func missing() {
        #expect(throws: ProviderFailure.unsupported("Pick a repository for this widget.")) {
            _ = try GitHubProvider.repositoryFor(["access_token": "ghp_x"], window: window([:]))
        }
    }

    /// The value reaches a request path, so it is re-checked here rather than
    /// trusted from the manifest's `pattern`, which is only a hint the app
    /// renders over what somebody types.
    @Test("a repository that is not owner/name is refused rather than built into a URL")
    func malformed() {
        for bad in ["../../user", "haxzie", "haxzie/notch/metrics", "haxzie/not ch", ""] {
            #expect(throws: ProviderFailure.self) {
                _ = try GitHubProvider.repositoryFor(
                    ["access_token": "ghp_x"], window: window(["repository": bad]))
            }
        }
    }

    @Test("each segment is encoded separately, so the slash between them survives")
    func path() {
        #expect(GitHubProvider.repoPath("haxzie/notch-metrics") == "/repos/haxzie/notch-metrics")
    }

    @Test("an empty branch means every branch")
    func noBranch() throws {
        #expect(try GitHubProvider.branchFor(window([:], metric: "ci_runs")) == nil)
        #expect(try GitHubProvider.branchFor(window(["branch": "  "], metric: "ci_runs")) == nil)
    }

    /// A slash is legal in a branch name and `feature/x` must stay askable.
    @Test("a branch with a slash is kept")
    func slashBranch() throws {
        #expect(try GitHubProvider.branchFor(window(["branch": "feature/thing"])) == "feature/thing")
    }

    /// The failure this prevents: a value carrying its own `&` appends
    /// parameters to GitHub's request rather than naming a branch.
    @Test("a branch that would add query parameters of its own is refused")
    func injectedBranch() {
        for bad in ["main&per_page=100", "main?x=1", "main#frag", "ma in"] {
            #expect(throws: ProviderFailure.self) {
                _ = try GitHubProvider.branchFor(window(["branch": bad], metric: "ci_runs"))
            }
        }
    }
}

/// GitHub's nine conclusions and six statuses, collapsed to the four a tile can
/// draw. Matching on GitHub's words in a view would need a release every time
/// GitHub added one.
@Suite("github run states")
struct GitHubRunStateTests {
    private func run(status: String?, conclusion: String?) -> GitHubProvider.WorkflowRun {
        let json = """
            {"id":1,"name":"CI","display_title":"x","head_branch":"main","event":"push",
             "status":\(status.map { "\"\($0)\"" } ?? "null"),
             "conclusion":\(conclusion.map { "\"\($0)\"" } ?? "null"),
             "created_at":"2026-10-05T11:00:00Z","updated_at":"2026-10-05T11:04:00Z"}
            """
        return try! JSONDecoder().decode(GitHubProvider.WorkflowRun.self, from: Data(json.utf8))
    }

    @Test("a conclusion is read before a status, because a finished run has both")
    func conclusionWins() {
        let state = GitHubProvider.runState(run(status: "completed", conclusion: "success"))
        #expect(state.state == .succeeded)
        #expect(state.status == "success")
    }

    @Test("the four drawable states, and grey for anything else")
    func table() {
        let cases: [(String, MetricListItemState)] = [
            ("success", .succeeded),
            ("failure", .failed),
            ("timed_out", .failed),
            ("startup_failure", .failed),
            // A run that has stopped and is waiting for a human, which is the
            // same thing to anyone glancing at a notch.
            ("action_required", .failed),
            ("cancelled", .neutral),
            ("skipped", .neutral),
            ("neutral", .neutral),
            // Whatever GitHub adds next: grey rather than wrong.
            ("stale", .neutral),
        ]
        for (conclusion, expected) in cases {
            #expect(GitHubProvider.runState(run(status: "completed", conclusion: conclusion)).state == expected)
        }
    }

    @Test("a run still going reads from its status")
    func running() {
        for status in ["queued", "in_progress", "requested", "waiting", "pending"] {
            #expect(GitHubProvider.runState(run(status: status, conclusion: nil)).state == .running)
        }
    }

    @Test("a run with neither is unknown rather than a crash")
    func neither() {
        let state = GitHubProvider.runState(run(status: nil, conclusion: nil))
        #expect(state.status == "unknown")
        #expect(state.state == .neutral)
    }
}

/// The metrics, over a stubbed session.
///
/// Serialised because the stub's routing table is static: `URLProtocol` is
/// instantiated by `URLSession` and there is nowhere to hand per-test state.
@Suite("github metrics", .serialized)
struct GitHubMetricTests {
    private let creds = ["access_token": "ghp_11ABCDEFGHIJKLMNOP"]

    private func window(
        _ metric: String, params: [String: String] = ["repository": "haxzie/notch-metrics"]
    ) -> MetricWindow {
        MetricWindow(
            metric: metric,
            from: Date(timeIntervalSince1970: 1_757_030_400),
            to: Date(timeIntervalSince1970: 1_759_622_400),
            granularity: .day, wantSeries: true, params: params,
            timeZone: TimeZone(identifier: "UTC")!)
    }

    private func fetch(
        _ window: MetricWindow, credentials: [String: String]? = nil
    ) async throws -> MetricValue {
        let provider = GitHubProvider()
        return try await provider.fetch(
            credentials ?? creds, window: window,
            http: ProviderHTTP(allowedHosts: provider.allowedHosts, session: GitHubStub.session()))
    }

    /// Deliberately an `open_issues_count` that is the sum of open issues and
    /// open PRs, which is what GitHub puts there.
    private static let repo = #"""
        {"full_name":"haxzie/notch-metrics","stargazers_count":412,"forks_count":37,
         "open_issues_count":23,"private":false}
        """#

    /// One of each outcome a tile has to draw, plus one GitHub has not invented
    /// yet — `stale` stands in for whatever it adds next.
    private static let runs = #"""
        {"total_count":5,"workflow_runs":[
          {"id":101,"name":"CI","display_title":"Tell people when something happened, in the notch",
           "head_branch":"main","event":"push","status":"completed","conclusion":"success",
           "created_at":"2026-10-05T11:00:00Z","updated_at":"2026-10-05T11:04:00Z"},
          {"id":102,"name":"CI","display_title":"Build the Mac app on the toolchain CI actually has",
           "head_branch":"main","event":"push","status":"completed","conclusion":"failure",
           "created_at":"2026-10-05T10:00:00Z","updated_at":"2026-10-05T10:06:00Z"},
          {"id":103,"name":"Release","display_title":"Cut 0.2.1","head_branch":"main",
           "event":"workflow_dispatch","status":"in_progress","conclusion":null,
           "created_at":"2026-10-05T09:00:00Z","updated_at":"2026-10-05T09:01:00Z"},
          {"id":104,"name":"CI","display_title":"Search the Integrations list",
           "head_branch":"haxzie/search","event":"pull_request","status":"completed",
           "conclusion":"cancelled","created_at":"2026-10-05T08:00:00Z",
           "updated_at":"2026-10-05T08:02:00Z"},
          {"id":105,"name":"CI","display_title":null,"head_branch":"main","event":"push",
           "status":"completed","conclusion":"stale","created_at":"2026-10-05T07:00:00Z",
           "updated_at":"2026-10-05T07:03:00Z"}
        ]}
        """#

    @Test("names the connection after the account, not a repository")
    func verifyLabel() async throws {
        GitHubStub.reset(routes: [("/user", 200, #"{"login":"haxzie","followers":128}"#, [:])])
        let provider = GitHubProvider()
        let account = try await provider.verify(
            creds, http: ProviderHTTP(allowedHosts: provider.allowedHosts, session: GitHubStub.session()))
        #expect(account.label == "haxzie")
        // Not money. A currency here would have a count formatted as an amount.
        #expect(account.currency == nil)
    }

    /// Mandatory, and its absence is the nastiest failure in this connector:
    /// without a user agent GitHub answers 403 for every request, which reads
    /// exactly like a bad token.
    @Test("every request carries a user agent and a pinned API version")
    func headers() async throws {
        GitHubStub.reset(routes: [("/repos/", 200, Self.repo, [:])])
        _ = try await fetch(window("stars"))
        #expect(GitHubStub.lastHeaders["user-agent"] == "notch-metrics")
        #expect(GitHubStub.lastHeaders["x-github-api-version"] == "2022-11-28")
        #expect(GitHubStub.lastHeaders["authorization"] == "Bearer ghp_11ABCDEFGHIJKLMNOP")
    }

    @Test("reads stars and forks from the repository")
    func starsAndForks() async throws {
        GitHubStub.reset(routes: [("/repos/haxzie/notch-metrics", 200, Self.repo, [:])])
        let stars = try await fetch(window("stars"))
        let forks = try await fetch(window("forks"))
        #expect(stars.value == 412)
        #expect(forks.value == 37)
        // No history exists for either, so one point at now and no comparison.
        #expect(stars.points.count == 1)
        #expect(stars.previousValue == nil)
    }

    /// The whole point of the repository moving onto the widget: two tiles, one
    /// connection, two repositories.
    @Test("asks a different repository per widget on one connection")
    func perWidget() async throws {
        GitHubStub.reset(routes: [("/repos/", 200, Self.repo, [:])])
        _ = try await fetch(window("stars", params: ["repository": "a/one"]))
        _ = try await fetch(window("stars", params: ["repository": "b/two"]))
        #expect(GitHubStub.paths == ["/repos/a/one", "/repos/b/two"])
    }

    @Test("falls back to a pre-existing connection's repository")
    func legacyRepository() async throws {
        GitHubStub.reset(routes: [("/repos/", 200, Self.repo, [:])])
        let value = try await fetch(
            window("stars", params: [:]),
            credentials: ["access_token": "gho_11ABCDEFGHIJKLMNOP", "repository": "haxzie/notch-metrics"])
        #expect(GitHubStub.paths == ["/repos/haxzie/notch-metrics"])
        #expect(value.value == 412)
    }

    @Test("a malformed repository is refused before a request is made")
    func noRequestForMalformed() async {
        GitHubStub.reset(routes: [])
        await #expect(throws: ProviderFailure.self) {
            _ = try await fetch(window("stars", params: ["repository": "../../user"]))
        }
        #expect(GitHubStub.paths.isEmpty)
    }

    /// The repository object would say 23. Only 15 of those are issues, and
    /// taking the number from `open_issues_count` reads high by exactly the
    /// number of open PRs — invisible until somebody counts by hand.
    @Test("counts open issues without the pull requests")
    func openIssues() async throws {
        GitHubStub.reset(routes: [
            ("is%3Aissue", 200, #"{"total_count":15}"#, [:]),
            ("is%3Apr", 200, #"{"total_count":8}"#, [:]),
        ])
        let issues = try await fetch(window("open_issues"))
        let prs = try await fetch(window("open_pull_requests"))
        #expect(issues.value == 15)
        #expect(prs.value == 8)
        // Only `total_count` is read, so a default page of 30 issue bodies is
        // not fetched and thrown away.
        #expect(GitHubStub.urls.allSatisfy { $0.contains("per_page=1") })
        #expect(GitHubStub.urls.allSatisfy { $0.contains("is%3Aopen") })
        #expect(GitHubStub.paths == ["/search/issues", "/search/issues"])
    }

    @Test("lists CI runs newest first, with a state a tile can draw")
    func ciRuns() async throws {
        GitHubStub.reset(routes: [("/actions/runs", 200, Self.runs, [:])])
        let value = try await fetch(window("ci_runs"))
        #expect(
            value.items?.map(\.state) == [
                .succeeded, .failed, .running,
                // Cancelled, and a conclusion that does not exist yet. Both
                // grey rather than either of them reading as a failure.
                .neutral, .neutral,
            ])
        // GitHub's own word is kept beside it: the tooltip says `cancelled`,
        // not "neutral".
        #expect(value.items?[3].status == "cancelled")
        // The count is derived from the rows, so the number and the rows
        // cannot disagree.
        #expect(value.value == 5)
        #expect(value.note == nil)
    }

    /// Labelled by the commit, the first two rows here are the same sentence at
    /// nearly the same age — which reads as a tile that failed to load.
    @Test("titles a row with the workflow, because one push starts several")
    func rowLabels() async throws {
        GitHubStub.reset(routes: [("/actions/runs", 200, Self.runs, [:])])
        let value = try await fetch(window("ci_runs"))
        #expect(value.items?.map(\.label) == ["CI", "CI", "Release", "CI", "CI"])
        // The commit is still there for a tile wide enough to show it, and so
        // is the branch while the widget filters to none.
        #expect(value.items?[0].detail == "Tell people when something happened, in the notch · main")
        #expect(value.items?[3].detail == "Search the Integrations list · haxzie/search")
    }

    /// A run that has been going an hour must not read as an hour old the
    /// moment it goes green.
    @Test("dates a row by when the run last moved, not when it was queued")
    func rowDates() async throws {
        GitHubStub.reset(routes: [("/actions/runs", 200, Self.runs, [:])])
        let value = try await fetch(window("ci_runs"))
        #expect(value.items?[0].date == ISO8601.parse("2026-10-05T11:04:00Z"))
    }

    @Test("asks GitHub for one branch when the widget names one")
    func branchFilter() async throws {
        GitHubStub.reset(routes: [("/actions/runs", 200, Self.runs, [:])])
        let value = try await fetch(
            window("ci_runs", params: ["repository": "haxzie/notch-metrics", "branch": "feature/thing"]))
        #expect(GitHubStub.urls.first?.contains("branch=feature%2Fthing") == true)
        // The branch is dropped from the rows: repeating what the user chose
        // spends the only line a narrow tile has.
        #expect(value.items?[0].detail == "Tell people when something happened, in the notch")
    }

    @Test("lists every branch when the widget names none")
    func everyBranch() async throws {
        GitHubStub.reset(routes: [("/actions/runs", 200, Self.runs, [:])])
        _ = try await fetch(window("ci_runs"))
        #expect(GitHubStub.urls.first?.contains("branch=") == false)
    }

    @Test("says so rather than showing an empty tile when there are no runs")
    func noRuns() async throws {
        GitHubStub.reset(routes: [("/actions/runs", 200, #"{"total_count":0,"workflow_runs":[]}"#, [:])])
        let value = try await fetch(
            window("ci_runs", params: ["repository": "haxzie/notch-metrics", "branch": "main"]))
        #expect(value.items?.isEmpty == true)
        #expect(value.note == "No Actions runs on main.")
        #expect(value.value == 0)
    }

    /// A repository with Actions disabled answers with the envelope and no
    /// array. A decode failure there would read as a broken connection rather
    /// than an empty feed.
    @Test("a response with no runs array is an empty feed, not a bad response")
    func actionsDisabled() async throws {
        GitHubStub.reset(routes: [("/actions/runs", 200, #"{"total_count":0}"#, [:])])
        let value = try await fetch(window("ci_runs"))
        #expect(value.items?.isEmpty == true)
        #expect(value.note == "No Actions runs on this repository.")
    }

    @Test("reads followers from the account, with no repository at all")
    func followers() async throws {
        GitHubStub.reset(routes: [("/user", 200, #"{"login":"haxzie","followers":128}"#, [:])])
        let value = try await fetch(window("followers", params: [:]))
        #expect(value.value == 128)
        #expect(GitHubStub.paths == ["/user"])
    }

    /// The catalogue is the Worker's and lists metrics this build has not been
    /// taught. Saying so is the contract; the caller falls back to the API.
    @Test("refuses a metric it does not provide")
    func unknownMetric() async {
        GitHubStub.reset(routes: [])
        await #expect(throws: ProviderFailure.unsupported("This build cannot read GitHub's mrr yet.")) {
            _ = try await fetch(window("mrr"))
        }
    }

    /// A 404 on a tile's repository must not mark the connection broken: the
    /// same token is answering every other tile, and a reconnect cannot fix a
    /// repository that was renamed.
    @Test("a repository the token cannot see is unsupported, not an auth failure")
    func unreadableRepository() async {
        GitHubStub.reset(routes: [("/repos/", 404, #"{"message":"Not Found"}"#, [:])])
        let outcome = await Result { try await fetch(window("stars")) }
        guard case .failure(let error) = outcome, let failure = error as? ProviderFailure else {
            Issue.record("a 404 should have failed the fetch")
            return
        }
        #expect(failure.message.contains("repository"))
        if case .authFailed = failure { Issue.record("a 404 must never be an auth failure") }
    }

    @Test("a missing token is refused before any request is made")
    func missingToken() async {
        GitHubStub.reset(routes: [])
        await #expect(throws: ProviderFailure.self) {
            _ = try await fetch(window("stars"), credentials: [:])
        }
        #expect(GitHubStub.paths.isEmpty)
    }
}

/// A stubbed HTTP layer, so the arithmetic can be tested without a network.
///
/// `URLProtocol` is instantiated by `URLSession` with no way to hand it
/// per-instance state, hence the static table — and hence `.serialized` on
/// every suite that uses it. Routes match on a substring of the whole URL
/// rather than on the path, because GitHub's search endpoint is told apart by
/// its query and nothing else.
final class GitHubStub: URLProtocol {
    typealias Route = (match: String, status: Int, body: String, headers: [String: String])

    nonisolated(unsafe) private static var routes: [Route] = []
    nonisolated(unsafe) private static var seen: [URLRequest] = []

    static func reset(routes: [Route]) {
        self.routes = routes
        seen = []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GitHubStub.self]
        return URLSession(configuration: configuration)
    }

    static var urls: [String] { seen.compactMap { $0.url?.absoluteString } }
    static var paths: [String] { seen.compactMap { $0.url?.path } }

    /// Lower-cased, because HTTP header names are and a dictionary is not.
    static var lastHeaders: [String: String] {
        (seen.last?.allHTTPHeaderFields ?? [:]).reduce(into: [:]) { out, pair in
            out[pair.key.lowercased()] = pair.value
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.seen.append(request)
        // An unrouted URL is a 404 rather than a hang, so a test that asked for
        // a call it did not stub fails by name.
        let route = Self.routes.first { url.absoluteString.contains($0.match) }
            ?? ("", 404, #"{"message":"no stub"}"#, [:])
        var headers = route.headers
        headers["content-type"] = "application/json"
        let response = HTTPURLResponse(
            url: url, statusCode: route.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(route.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
