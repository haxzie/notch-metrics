import Foundation
import MetricsCore

/// GitHub's metrics, read on this Mac.
///
/// Ported from `packages/integrations/src/providers/github`, one case per file
/// there. The arithmetic is deliberately the same arithmetic — a widget must
/// not change its number because the fetch moved off the Worker — and that is
/// mostly a statement about open issues, which has to be counted through
/// search rather than read off the repository object.
extension GitHubProvider {
    /// Ten rows, the same as a payments feed and for the same reason.
    static let ciRunsLimit = 10

    public func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let token = try requiredCredential(credentials, "access_token")

        switch window.metric {
        case "stars":
            let repo = try await repository(credentials, window: window, token: token, http: http)
            return Self.snapshot(Double(repo.stargazersCount))
        case "forks":
            let repo = try await repository(credentials, window: window, token: token, http: http)
            return Self.snapshot(Double(repo.forksCount))
        case "open_issues":
            // Not `open_issues_count`. That field is issues *and* pull
            // requests, so an issue count taken from it reads high by exactly
            // the number of open PRs — the single most common way to get this
            // number wrong, and invisible until somebody counts by hand.
            return Self.snapshot(
                try await searchCount(
                    credentials, window: window, token: token, http: http, qualifier: "is:issue"))
        case "open_pull_requests":
            return Self.snapshot(
                try await searchCount(
                    credentials, window: window, token: token, http: http, qualifier: "is:pr"))
        case "ci_runs":
            return try await ciRuns(credentials, window: window, token: token, http: http)
        case "followers":
            // No repository at all. This one is about the account that
            // authorised, which is why params are declared per metric rather
            // than per connector — and why it must not reach `repositoryFor`
            // and demand a repository a followers tile never asked for.
            let account = try await Self.get(Account.self, "/user", token: token, http: http)
            return Self.snapshot(Double(account.followers))
        default:
            // Not a bug: the catalogue is the Worker's and lists metrics this
            // build has not been taught yet. The caller falls back to the API.
            throw ProviderFailure.unsupported("This build cannot read GitHub's \(window.metric) yet.")
        }
    }

    // MARK: - Metrics

    private func repository(
        _ credentials: [String: String], window: MetricWindow, token: String, http: ProviderHTTP
    ) async throws -> Repository {
        let name = try Self.repositoryFor(credentials, window: window)
        return try await Self.get(
            Repository.self, Self.repoPath(name), token: token, http: http)
    }

    /// Open issues, or open pull requests, counted through search.
    private func searchCount(
        _ credentials: [String: String], window: MetricWindow, token: String,
        http: ProviderHTTP, qualifier: String
    ) async throws -> Double {
        let name = try Self.repositoryFor(credentials, window: window)
        let query = Self.encoded("repo:\(name) \(qualifier) is:open")
        // `per_page=1` because only `total_count` is read; the page itself is
        // thrown away and a default page of 30 issue bodies is not free.
        let body = try await Self.get(
            SearchResult.self, "/search/issues?q=\(query)&per_page=1", token: token, http: http)
        return Double(body.totalCount)
    }

    /// The ten most recent Actions runs, newest first, as rows.
    ///
    /// The rows are the widget; the headline figure is the count behind them,
    /// which is what a tile too short for rows falls back to.
    private func ciRuns(
        _ credentials: [String: String], window: MetricWindow, token: String, http: ProviderHTTP
    ) async throws -> MetricValue {
        let name = try Self.repositoryFor(credentials, window: window)
        let branch = try Self.branchFor(window)

        var path = "\(Self.repoPath(name))/actions/runs?per_page=\(Self.ciRunsLimit)"
        if let branch { path += "&branch=\(Self.encoded(branch))" }
        let body = try await Self.get(WorkflowRuns.self, path, token: token, http: http)

        let items = Self.rows(from: body.workflowRuns ?? [], branch: branch)
        return MetricValue(
            // The count is derived rather than asked for, so the number and
            // the rows cannot disagree.
            value: Double(items.count),
            points: [MetricPoint(t: ISO8601.string(from: Date()), v: Double(items.count))],
            items: items,
            note: items.isEmpty
                ? (branch.map { "No Actions runs on \($0)." } ?? "No Actions runs on this repository.")
                : nil)
    }

    /// One reading, timestamped now.
    ///
    /// The `scalar()` factory's rule on the Worker, which is where this used to
    /// happen: one point, at this instant. A provider that exposes no history
    /// has none, and a flat line invented from a single reading looks like
    /// data. `window.comparePrevious` is deliberately ignored — no GitHub
    /// descriptor sets `compare`, because there is no earlier reading of a
    /// star count to compare against.
    static func snapshot(_ value: Double) -> MetricValue {
        MetricValue(value: value, points: [MetricPoint(t: ISO8601.string(from: Date()), v: value)])
    }

    // MARK: - Rows

    static func rows(from runs: [WorkflowRun], branch: String?) -> [MetricListItem] {
        runs.prefix(ciRunsLimit).map { run in
            let (state, status) = runState(run)
            // When it last moved, not when it was queued: a run that has been
            // going for an hour should not read as an hour old the moment it
            // finishes.
            let stamp = nonEmpty(run.updatedAt) ?? nonEmpty(run.createdAt) ?? ""
            let detail = [
                nonEmpty(run.displayTitle),
                // Dropped when the widget already filters to one branch:
                // repeating it on every row spends the only line a narrow tile
                // has on something the user chose.
                branch == nil ? nonEmpty(run.headBranch) : nil,
            ].compactMap { $0 }.joined(separator: " · ")
            return MetricListItem(
                id: String(run.id),
                t: ISO8601.parse(stamp).map { ISO8601.string(from: $0) } ?? stamp,
                // The *workflow*, not the commit subject.
                //
                // One push starts every workflow that watches the branch, and
                // all of them carry the same `display_title` — so a list
                // labelled by the commit is five rows of the same sentence, at
                // the same age, which reads as the tile having failed to load
                // rather than as four jobs. The workflow names are what
                // differ, and they are short enough for a narrow tile; the
                // commit goes to `detail`, which a wide tile shows.
                label: nonEmpty(run.name) ?? nonEmpty(run.displayTitle) ?? "Run \(run.id)",
                detail: detail.isEmpty ? nil : detail,
                amount: nil,
                currency: nil,
                // GitHub's own word, kept beside the drawable state: a tooltip
                // says `cancelled`, not "neutral".
                status: status,
                state: state)
        }
    }

    /// GitHub's nine conclusions and six statuses, collapsed to the four states
    /// a tile can draw.
    ///
    /// Done here rather than in the view: these are GitHub's words, GitHub adds
    /// to them, and a view matching on them would need a release every time it
    /// did. `action_required` is a failure on purpose — it is a run that has
    /// stopped and is waiting for a human, which is the same thing to anyone
    /// glancing at a notch.
    static func runState(_ run: WorkflowRun) -> (state: MetricListItemState, status: String) {
        let status = (nonEmpty(run.conclusion) ?? nonEmpty(run.status) ?? "unknown").lowercased()
        switch status {
        case "success":
            return (.succeeded, status)
        case "failure", "timed_out", "startup_failure", "action_required":
            return (.failed, status)
        case "queued", "in_progress", "requested", "waiting", "pending":
            return (.running, status)
        default:
            // `cancelled`, `skipped`, `neutral`, `stale` — and anything GitHub
            // adds later, which is grey rather than wrong.
            return (.neutral, status)
        }
    }

    // MARK: - Parameters

    /// Which repository this request is about.
    ///
    /// The widget's own parameter, falling back to the connection's for
    /// anything made before the repository moved off the connection. Without
    /// that fallback every GitHub tile in an existing notch would blank on the
    /// release that shipped this.
    static func repositoryFor(
        _ credentials: [String: String], window: MetricWindow
    ) throws -> String {
        let repository = (window.params["repository"] ?? credentials["repository"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repository.isEmpty else {
            throw ProviderFailure.unsupported("Pick a repository for this widget.")
        }
        // Re-checked here rather than trusted from the manifest's `pattern`:
        // that is a hint the app renders over what somebody types, and this
        // value reaches a request path.
        //
        // The class is spelled out rather than written `\w`, which is ASCII in
        // the Worker's regex and Unicode-aware in a Swift one — so `\w` here
        // would quietly accept names the server refuses.
        guard repository.wholeMatch(of: /[A-Za-z0-9_.\-]+\/[A-Za-z0-9_.\-]+/) != nil else {
            throw ProviderFailure.unsupported("\"\(repository)\" is not an owner/name repository.")
        }
        return repository
    }

    /// Each segment encoded separately, so the slash between them survives.
    static func repoPath(_ repository: String) -> String {
        let parts = repository.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let owner = parts.first.map(String.init) ?? ""
        let name = parts.count > 1 ? String(parts[1]) : ""
        return "/repos/\(encoded(owner))/\(encoded(name))"
    }

    /// The branch filter for a CI tile, or nothing.
    ///
    /// Validated as well as encoded, because this reaches a query string: a
    /// value carrying its own `&` would append parameters to GitHub's request
    /// rather than name a branch. A slash is legal in a branch name and
    /// `feature/x` must stay askable, so only what would change the request is
    /// refused.
    static func branchFor(_ window: MetricWindow) throws -> String? {
        let branch = (window.params["branch"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if branch.isEmpty { return nil }
        if branch.contains(where: { $0.isWhitespace || "?&#".contains($0) }) {
            throw ProviderFailure.unsupported("\"\(branch)\" is not a branch name.")
        }
        return branch
    }

    /// `encodeURIComponent`, as far as this adapter needs it.
    ///
    /// The same unreserved set, so a slash in a branch name becomes `%2F`
    /// rather than another path segment, and a space in a search query becomes
    /// `%20` rather than ending the URL.
    static func encoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Nil for a field GitHub sent as an empty string.
    ///
    /// The Worker's `||` chains fall through an empty string; `??` would stop
    /// at one and label a row with nothing.
    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// GitHub's wire shapes, nested under the adapter that reads them.
///
/// Nested rather than at file scope because `Repository`, `Account` and
/// `SearchResult` are names more than one connector in this module wants. At
/// the top level the second one to be written fails to compile, and the error
/// names a file its author never touched.
extension GitHubProvider {
    struct Repository: Decodable {
        let fullName: String
        let stargazersCount: Int
        let forksCount: Int
        /// Issues *and* pull requests. Read by nothing here on purpose; see
        /// `open_issues` above.
        let openIssuesCount: Int
        let isPrivate: Bool

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case stargazersCount = "stargazers_count"
            case forksCount = "forks_count"
            case openIssuesCount = "open_issues_count"
            case isPrivate = "private"
        }
    }

    struct SearchResult: Decodable {
        let totalCount: Int

        enum CodingKeys: String, CodingKey {
            case totalCount = "total_count"
        }
    }

    /// One GitHub Actions run, as much of it as a row needs.
    struct WorkflowRun: Decodable {
        let id: Int
        /// The workflow's name — "CI", "Deploy the API".
        let name: String?
        /// The commit's subject, or the title of the PR the run is for.
        let displayTitle: String?
        let headBranch: String?
        let event: String?
        /// `queued`, `in_progress`, `completed`, and others GitHub may add.
        let status: String?
        /// Null until `status` is `completed`.
        let conclusion: String?
        let createdAt: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case displayTitle = "display_title"
            case headBranch = "head_branch"
            case event
            case status
            case conclusion
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    struct WorkflowRuns: Decodable {
        /// Optional, because a repository with Actions disabled answers with
        /// the envelope and no array, and a decode failure there would read as
        /// a broken connection rather than an empty feed.
        let workflowRuns: [WorkflowRun]?

        enum CodingKeys: String, CodingKey {
            case workflowRuns = "workflow_runs"
        }
    }
}
