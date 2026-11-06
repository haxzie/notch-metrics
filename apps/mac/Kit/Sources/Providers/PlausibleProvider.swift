import Foundation

/// Plausible, read from this Mac with the user's own Stats API key.
///
/// Ported from `packages/integrations/src/providers/plausible`. Two things
/// about it differ from the payments connectors either side of it, and both
/// shape the code below:
///
/// The credential is a key *and* a site, and Plausible matches the site by
/// exact domain — so the stored value is normalised rather than trusted (see
/// `normalisedSiteID`).
///
/// Its Stats API aggregates server-side over a date range, so there is no list
/// to walk and no paging. One POST answers a window; a second, with a time
/// dimension, answers the chart.
public struct PlausibleProvider: LocalProvider {
    public let id = "plausible"
    /// Cloud only, as the manifest declares. Self-hosted Plausible speaks the
    /// same API on the operator's own domain, which an allowlist fixed at
    /// build time cannot admit.
    public let allowedHosts = ["plausible.io"]

    static let host = "plausible.io"
    static let base = "https://plausible.io"

    public init() {}

    // MARK: - Credentials

    struct Credentials: Sendable {
        let apiKey: String
        /// Already normalised, so no call site can send the raw paste.
        let siteID: String
    }

    /// Plausible matches the domain exactly.
    ///
    /// A pasted `"Example.com "` is a 404, and a 404 here reads as a missing
    /// site — so the user is sent to check their Plausible account over a
    /// trailing space. The Worker does this in a Zod transform on the way in;
    /// here it happens on every read instead, because a connection stored
    /// before this existed still has the raw paste in the keychain and would
    /// otherwise stay broken until it was re-entered.
    ///
    /// Idempotent for exactly that reason: it runs on a value that may
    /// already have been through it.
    static func normalisedSiteID(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The smallest key Plausible issues is far longer than eight characters.
    ///
    /// The floor matches the Worker's `credentialSchema`, and it is here to
    /// catch a half-selected paste: eight characters of a real key is a 401,
    /// which reads as a revoked key and sends somebody to generate another
    /// one that will fail the same way.
    static let minimumKeyLength = 8

    static func credentials(_ raw: [String: String]) throws -> Credentials {
        let key = try requiredCredential(raw, "api_key")
        guard key.count >= minimumKeyLength else {
            throw ProviderFailure.authFailed("That does not look like a full Plausible API key.")
        }
        let site = normalisedSiteID(try requiredCredential(raw, "site_id"))
        guard !site.isEmpty else {
            throw ProviderFailure.authFailed("No site_id was stored for this connection.")
        }
        return Credentials(apiKey: key, siteID: site)
    }

    // MARK: - Verify

    struct Site: Decodable {
        let domain: String?
        /// The site's reporting timezone. Read but not used: every date this
        /// adapter sends is an instant, so there is nothing to express in it.
        let timezone: String?
    }

    public func verify(
        _ credentials: [String: String], http: ProviderHTTP
    ) async throws -> ProviderAccount {
        let creds = try Self.credentials(credentials)

        // The site endpoint rather than a stats query, as the Worker does: it
        // proves the key, proves this site is on the key's team, and costs
        // nothing in stats quota.
        let path = "/api/v1/sites/\(Self.escape(creds.siteID))"
        let site: Site
        do {
            site = try await Self.send(Site.self, path, method: "GET", credentials: creds, http: http)
        } catch ProviderFailure.unsupported {
            // A 404 from this path is always "this key cannot see that site",
            // and at setup time that is an auth failure however well-formed
            // the domain is: a key is scoped to one team, and a site owned by
            // another answers exactly as a wrong domain does.
            throw ProviderFailure.authFailed(
                "Plausible has no site \"\(creds.siteID)\" on this key's team. A key is scoped to "
                    + "one team, and a site owned by another answers the same way a wrong domain does.")
        }

        let label = site.domain?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProviderAccount(
            label: (label?.isEmpty == false ? label : nil) ?? creds.siteID,
            // Not a money connector. A currency here would have a tile render
            // 412 visitors as $4.12.
            currency: nil)
    }

    // MARK: - Requests

    /// Percent-encoding for a domain in a path segment.
    ///
    /// A site id reaches here from a text field, and an unescaped one with a
    /// slash in it would address a different endpoint entirely.
    static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~")))
            ?? value
    }

    static func send<T: Decodable>(
        _ type: T.Type, _ path: String, method: String, credentials: Credentials,
        body: Data? = nil, http: ProviderHTTP
    ) async throws -> T {
        var headers = [
            "authorization": "Bearer \(credentials.apiKey)",
            "accept": "application/json",
        ]
        if body != nil { headers["content-type"] = "application/json" }

        let response = try await http.send(
            base + path, method: method, headers: headers, body: body)
        guard response.ok else { throw failure(for: response) }
        return try response.json(type)
    }

    // MARK: - Failures

    /// Plausible's status codes, in the buckets the caller acts differently on.
    ///
    /// The 400 and 404 cases carry Plausible's own sentence in front, because
    /// it is a better one than ours: "Site could not be found" and "metric is
    /// not available on your plan" both arrive as a 4xx that a generic mapping
    /// can only call a bad response, which sends somebody to re-roll a key
    /// that was never the problem.
    static func failure(for response: ProviderHTTP.Response) -> ProviderFailure {
        let detail = message(in: response.body)
        /// Plausible's words, prefixed so a tile says whose words they are.
        let quoted = detail.map { "Plausible: \($0)" }

        switch response.status {
        case 404:
            // Classified on the status, not on whether a body turned up. A 404
            // from any of these paths is "this key cannot see that site or that
            // metric", and a connector that only says so when Plausible
            // bothers to explain says the wrong thing at the worst moment.
            //
            // `unsupported` rather than `authFailed`: it is a statement about
            // one resource, so the connection is not marked broken. `verify`
            // is the one caller that reads it as an auth problem, because at
            // setup time there is nothing else it can be.
            return .unsupported(quoted ?? "Plausible has no such site or metric.")
        case 400:
            return .badResponse(quoted ?? "Plausible returned 400.")
        case 401, 403:
            // The status is in the fallback on purpose: a 403 from a host that
            // normally answers 401 is how a WAF in front of the provider shows
            // up, and that is a different afternoon from a mistyped key.
            return .authFailed(detail ?? "Plausible rejected that API key (\(response.status)).")
        case 429:
            // Defaulted to a minute when Plausible sent no header, as the
            // Worker's `errorForStatus` does: a nil wait means the refresh
            // loop retries on its own tick, which on a spent quota is
            // immediately.
            let retry = response.header("retry-after").flatMap(TimeInterval.init) ?? 60
            return .rateLimited("Plausible's rate limit is spent.", retryAfter: retry)
        case 500...599:
            return .providerDown("Plausible is having trouble.")
        default:
            return .badResponse(detail ?? "Plausible returned \(response.status).")
        }
    }

    /// Plausible's own explanation, when it sent one.
    ///
    /// `{"error": "..."}` is its documented shape and the only one worth
    /// reading; `message` is accepted too because its gateway answers in that
    /// one. Anything else is dropped rather than pasted in raw — an HTML
    /// error page in a notch tile is worse than the bare status it replaces.
    static func message(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        let candidates = [object["error"], object["message"]].compactMap { $0 as? String }
        guard let raw = candidates.first(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else { return nil }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Bounded, but generously: 200 characters cut a plan message off
        // before the part that named the plan.
        return trimmed.count > 400 ? String(trimmed.prefix(397)) + "..." : trimmed
    }
}
