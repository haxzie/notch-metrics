import Foundation

/// GitHub, read from this Mac with the user's own personal access token.
///
/// Ported from `packages/integrations/src/providers/github`. Two things about
/// this connector are different from the payment ones and both are easy to
/// lose in a rewrite:
///
/// - The connection is an *account*, not a repository. `verify` asks `/user`,
///   so the label stays stable when a tile is pointed somewhere else, and one
///   token serves a tile per repository — including repositories the account
///   does not own.
/// - The repository is a widget parameter, read in `fetch`. A connection made
///   before that move still carries one in its credentials, which is why
///   `repositoryFor` falls back to it.
public struct GitHubProvider: LocalProvider {
    public let id = "github"
    public let allowedHosts = ["api.github.com"]
    static let base = "https://api.github.com"

    public init() {}

    /// The authorising account. Nested rather than at file scope: `Account` is
    /// a name every connector in this module wants, and at the top level the
    /// second one to be written fails to compile in a file its author never
    /// touched.
    struct Account: Decodable {
        let login: String
        let followers: Int
    }

    /// `/user` rather than a repository.
    ///
    /// There is no repository at this point to prove anything about — the
    /// widget supplies it later — and a login is what names the connection
    /// stably. No `unavailableMetrics`: a token's reach is per repository
    /// rather than per metric here, so a 404 on one tile says nothing about
    /// what the others can answer.
    public func verify(
        _ credentials: [String: String], http: ProviderHTTP
    ) async throws -> ProviderAccount {
        let token = try requiredCredential(credentials, "access_token")
        let account = try await Self.get(Account.self, "/user", token: token, http: http)
        // Nil currency: GitHub is not about money, and claiming a currency
        // would have a count formatted as an amount.
        return ProviderAccount(label: account.login, currency: nil)
    }

    // MARK: - Requests

    static func get<T: Decodable>(
        _ type: T.Type, _ path: String, token: String, http: ProviderHTTP
    ) async throws -> T {
        let response = try await http.get(
            base + path,
            headers: [
                "authorization": "Bearer \(token)",
                "accept": "application/vnd.github+json",
                // Pinned, so a future default on GitHub's side cannot change a
                // field under an installed app that has no way to be updated
                // for it.
                "x-github-api-version": "2022-11-28",
                // Mandatory. Without it GitHub answers 403 for every request,
                // which reads exactly like a bad token.
                "user-agent": "notch-metrics",
            ])
        guard response.ok else { throw failure(for: response) }
        return try response.json(type)
    }

    // MARK: - Failures

    /// GitHub's status codes, in the buckets the caller acts differently on.
    ///
    /// The two unusual ones are the whole reason this is not the shared
    /// mapping, and both were learned the hard way:
    ///
    /// **403, not 429, for a spent quota.** Read as `authFailed` that marks the
    /// connection broken and stops polling it, so a user whose token is fine
    /// has to reconnect to recover from being briefly over quota. The cases are
    /// told apart by the headers: the primary limit leaves
    /// `x-ratelimit-remaining: 0` with a reset timestamp, and a secondary limit
    /// sends `retry-after`.
    ///
    /// **404 is `unsupported`, never `authFailed`.** It is a statement about
    /// one widget's repository — the same token is answering for every other
    /// tile in the notch — and a reconnect cannot fix a repository that was
    /// renamed.
    ///
    /// `now` is injected so the reset arithmetic can be pinned by a test
    /// rather than drifting with the clock.
    static func failure(
        for response: ProviderHTTP.Response, now: Date = Date()
    ) -> ProviderFailure {
        if response.status == 403 || response.status == 429 {
            if let raw = response.header("retry-after"),
               let retryAfter = TimeInterval(raw.trimmingCharacters(in: .whitespaces)),
               retryAfter > 0 {
                return .rateLimited("GitHub asked us to wait.", retryAfter: retryAfter)
            }
            if response.header("x-ratelimit-remaining") == "0" {
                // Rounded up and floored at a second: a reset that has just
                // passed would otherwise schedule a retry in zero seconds,
                // which the refresh loop runs immediately and spends again.
                let seconds: TimeInterval
                if let raw = response.header("x-ratelimit-reset"),
                   let reset = TimeInterval(raw.trimmingCharacters(in: .whitespaces)) {
                    seconds = max(1, (reset - now.timeIntervalSince1970).rounded(.up))
                } else {
                    seconds = 60
                }
                return .rateLimited("GitHub's rate limit is spent.", retryAfter: seconds)
            }
        }

        if response.status == 404 {
            // A repository that does not exist and one the token cannot see
            // are the same 404 — GitHub will not confirm a private repository
            // to a caller without access — so the message has to cover both.
            //
            // Except for one case worth naming outright. A `public_repo` token
            // keeps working for public repositories, so nothing announces that
            // it is the reason a private one 404s. A classic token's granted
            // scopes come back on every response, so the token can say so
            // itself rather than leaving somebody to re-check a repository
            // name that was right all along.
            //
            // A fine-grained token sends no such header, which is why the
            // empty case falls through: its permissions cannot be read off a
            // response, and guessing would blame the scope for a renamed
            // repository, which is the more common fault and the one a user
            // can actually fix.
            let granted = response.header("x-oauth-scopes") ?? ""
            if !granted.isEmpty {
                let scopes = granted.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if !scopes.contains("repo") {
                    return .unsupported(
                        "This token reads public repositories only. "
                            + "Give it repo access to read private ones.")
                }
            }
            return .unsupported(
                "That repository could not be read. "
                    + "Check the name, and that this account can see it.")
        }

        let detail = message(in: response.body)
        switch response.status {
        case 401, 403:
            // The status is part of the message on purpose, as it is in the
            // Worker's `errorForStatus`. A 403 from a host that normally says
            // 401 is how a WAF in front of the provider shows up, and that is
            // a different afternoon from a mistyped token.
            return .authFailed(
                "GitHub rejected the credentials (\(response.status))"
                    + (detail.map { ": \($0)" } ?? "."))
        case 429:
            // Only reached by a 429 that named neither a wait nor a spent
            // quota. A minute, as the Worker defaults to: a nil wait means the
            // refresh loop retries on its own tick, which here is immediately.
            return .rateLimited("GitHub asked us to wait.", retryAfter: 60)
        case 500...599:
            // No body. A GitHub 5xx is usually an HTML error page, and a stack
            // trace in a notch tile is worse than the bare status it replaces.
            return .providerDown("GitHub is having trouble.")
        default:
            // The body almost always names the wrong part of the request.
            // Throwing it away leaves "GitHub returned 422" on screen and the
            // cause to be guessed from outside the system.
            return .badResponse(detail ?? "GitHub returned \(response.status).")
        }
    }

    /// GitHub's own explanation, when it sent one.
    ///
    /// `message` is the shape that matters and `errors` is the one that carries
    /// the useful half of a 422, but the candidate order is the Worker's
    /// `providerMessage` so the two read the same side by side.
    static func message(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }

        // Each candidate is taken only when it is a string. Pasting a raw
        // array or an HTML page into a notch tile is worse than the status.
        var candidates: [Any?] = []
        if let nested = object["error"] as? [String: Any] {
            candidates.append(nested["message"])
        } else {
            candidates.append(object["error"])
        }
        candidates.append(object["message"])
        candidates.append(object["detail"])
        candidates.append(object["error_description"])
        // GitHub's validation errors: `[{ "message": "..." }]`, sometimes
        // bare strings. Joined, because a 422 usually names one field per
        // entry and the first alone does not say what is wrong.
        if let errors = object["errors"] as? [Any] {
            let joined = errors.compactMap { entry -> String? in
                if let text = entry as? String { return text }
                return (entry as? [String: Any])?["message"] as? String
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
            candidates.append(joined.isEmpty ? nil : joined)
        } else {
            candidates.append(object["errors"] as? String)
        }

        guard let raw = candidates.compactMap({ $0 as? String })
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { return nil }

        // Any token GitHub quoted back at us goes before this reaches a
        // screen, and from there a screenshot in a support thread. Stripe
        // truncates the key it echoes; nothing promises GitHub does.
        let redacted = raw
            .replacing(/gh[pousr]_[A-Za-z0-9_]+/, with: "ghp_…")
            .replacing(/github_pat_[A-Za-z0-9_]+/, with: "github_pat_…")

        // Whole sentences go, rather than the URL being cut out of them.
        // GitHub appends a `documentation_url`-style link to most messages,
        // and removing just the link leaves "See the docs at ." behind. Where
        // to click is `setupSteps`' job to say.
        //
        // The boundary is punctuation *followed by a space*, marked before the
        // split so the sentence keeps its full stop and a URL's own dots do not
        // cut it into pieces that no longer look like a link. The Worker uses a
        // lookbehind for this; Swift's regex engine has none, hence the marker.
        let cleaned = redacted.replacing(/\s+/, with: " ")
            .replacing(/([.!?])\s/) { "\($0.1)\u{0}" }
            .split(separator: "\u{0}")
            .filter { !$0.lowercased().contains("http://") && !$0.lowercased().contains("https://") }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return nil }

        // Bounded, but generously: 200 cut a permission message off before the
        // part that named the permission.
        return cleaned.count > 400 ? String(cleaned.prefix(397)) + "..." : cleaned
    }
}
