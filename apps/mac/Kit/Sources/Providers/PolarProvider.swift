import Foundation

/// Polar, read from this Mac with the user's own organisation access token.
///
/// Ported from `packages/integrations/src/providers/polar`. `verify` makes the
/// same three calls in the same order as the Worker's, and the last two are
/// not health checks: Polar's scopes are per endpoint and a token can carry
/// any subset, so probing `/metrics/` and `/orders/` separately is how the
/// payments feed is withheld from a token that only has `metrics:read`
/// instead of offered and then failing on every poll.
public struct PolarProvider: LocalProvider {
    public let id = "polar"
    /// Both of the manifest's hosts, because the stored mode decides which one
    /// a request goes to and an allowlist cannot be chosen per credential.
    public let allowedHosts = ["api.polar.sh", "sandbox-api.polar.sh"]

    public init() {}

    /// Every id this connector serves, for the "no usable scope at all" check.
    static let allMetricIDs = [
        "mrr", "revenue", "active_subscribers", "new_subscribers", "churned_subscribers",
        "recent_payments",
    ]
    /// The metrics that come off `/metrics/`, and so need `metrics:read`.
    static let metricsEndpointMetrics = [
        "mrr", "revenue", "active_subscribers", "new_subscribers", "churned_subscribers",
    ]
    /// The one that comes off `/orders/`, and so needs `orders:read`.
    static let ordersEndpointMetrics = ["recent_payments"]

    // MARK: - Credentials

    /// A stored connection, resolved to the one host it may talk to.
    struct Credentials: Sendable {
        let token: String
        /// Already decided from `mode`, so no call site can forget to.
        let host: String

        var base: String { "https://\(host)/v1" }
    }

    /// The host is chosen by the declared mode, never inferred from the token.
    ///
    /// Both environments issue `polar_oat_` tokens, so there is nothing to
    /// infer from — and a production token sent to the sandbox answers 401,
    /// which reads as a revoked key and sends the user off to make a new one.
    static func credentials(_ raw: [String: String]) throws -> Credentials {
        let token = try requiredCredential(raw, "access_token")
        let mode = raw["mode"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Defaulted rather than required, matching the manifest's default: a
        // connection stored before the field existed is a production one.
        return Credentials(
            token: token, host: mode == "sandbox" ? "sandbox-api.polar.sh" : "api.polar.sh")
    }

    // MARK: - Verify

    struct Organization: Decodable {
        let id: String
        let name: String
        let defaultPresentmentCurrency: String?

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case defaultPresentmentCurrency = "default_presentment_currency"
        }
    }

    struct Page<T: Decodable>: Decodable {
        let items: [T]?
    }

    /// Polar reports its metrics in the organization's currency, and says so
    /// nowhere in the response — so it is read here once and carried.
    static func currency(of organization: Organization) -> String {
        guard let code = organization.defaultPresentmentCurrency, !code.isEmpty else { return "USD" }
        return code.uppercased()
    }

    /// The token's organization.
    ///
    /// An organisation access token is bound to exactly one organization, so
    /// the first item is the only item.
    func organization(
        _ credentials: Credentials, http: ProviderHTTP
    ) async throws -> Organization {
        let page = try await get(
            Page<Organization>.self, "/organizations/", credentials: credentials,
            params: ["limit": "1"], http: http)
        guard let organization = page.items?.first else {
            throw ProviderFailure.unsupported("This token can see no organization.")
        }
        return organization
    }

    public func verify(
        _ credentials: [String: String], http: ProviderHTTP
    ) async throws -> ProviderAccount {
        let creds = try Self.credentials(credentials)
        let organization = try await organization(creds, http: http)

        // Said as what the token *cannot* reach rather than built up as what
        // it can, so this does not become a second copy of the catalogue that
        // has to stay in step with the metrics below.
        var unavailable: [String] = []

        func scoped(_ path: String, params: [String: String], grants: [String]) async throws {
            do {
                _ = try await get(
                    Empty.self, path, credentials: creds, params: params, http: http)
            } catch let failure as ProviderFailure {
                // Both of Polar's answers for "this token may not read this"
                // are tolerable and they land in different buckets: a missing
                // scope is a 403, which this adapter calls `unsupported`
                // because it is a statement about one endpoint, and a token
                // Polar will not even introspect is a 401.
                switch failure {
                case .authFailed, .unsupported:
                    unavailable.append(contentsOf: grants)
                default:
                    throw failure
                }
            }
        }

        try await scoped("/metrics/limits", params: [:], grants: Self.metricsEndpointMetrics)
        try await scoped("/orders/", params: ["limit": "1"], grants: Self.ordersEndpointMetrics)

        if unavailable.count == Self.allMetricIDs.count {
            throw ProviderFailure.unsupported(
                "This token can read neither metrics nor orders. "
                    + "Grant it metrics:read and orders:read.")
        }

        return ProviderAccount(
            label: organization.name.isEmpty ? organization.id : organization.name,
            currency: Self.currency(of: organization),
            unavailableMetrics: unavailable)
    }

    struct Empty: Decodable {}

    // MARK: - Requests

    func get<T: Decodable>(
        _ type: T.Type, _ path: String, credentials: Credentials,
        params: [String: String] = [:], http: ProviderHTTP
    ) async throws -> T {
        // The trailing slash on Polar's list routes is the caller's to get
        // right: without one the API 307s to the canonical path, and
        // `ProviderHTTP` refuses to carry a bearer token through a redirect.
        var components = URLComponents(string: credentials.base + path)
        if !params.isEmpty {
            // Sorted, so a request is reproducible in a log and in a test.
            components?.queryItems = params.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url?.absoluteString else {
            throw ProviderFailure.badResponse("Could not build a Polar URL for \(path).")
        }

        let response = try await http.get(
            url,
            headers: [
                "authorization": "Bearer \(credentials.token)",
                "accept": "application/json",
            ])
        guard response.ok else { throw Self.failure(for: response) }
        return try response.json(type)
    }

    /// Polar's status codes, in the buckets the caller acts differently on.
    static func failure(for response: ProviderHTTP.Response) -> ProviderFailure {
        let detail = message(in: response.body)
        switch response.status {
        case 401:
            return .authFailed(detail ?? "Polar rejected that access token.")
        case 403:
            // Not `authFailed`: a Polar token carries any subset of the scopes
            // and a 403 names one endpoint it may not read. Marking the whole
            // connection broken would ask the user to replace a token that
            // answers everything else.
            return .unsupported(
                detail ?? "That token's scopes do not cover this part of the organisation.")
        case 429:
            // Defaulted to a minute when Polar sent no header, as the Worker's
            // `errorForStatus` does: a nil wait there means the refresh loop
            // retries on its own tick, which on a spent quota is immediately.
            let retry = response.header("retry-after").flatMap(TimeInterval.init) ?? 60
            return .rateLimited(detail ?? "Polar's rate limit is spent.", retryAfter: retry)
        case 500...599:
            return .providerDown(detail ?? "Polar is having trouble.")
        default:
            // The body almost always names the wrong part of the request.
            // Throwing it away leaves "Polar returned 422" on screen and the
            // cause to be guessed from outside the system.
            return .badResponse(detail ?? "Polar returned \(response.status).")
        }
    }

    /// Polar's own explanation, when it sent one.
    ///
    /// `detail` is the shape that matters — Polar is built on FastAPI — but the
    /// candidate order is the Worker's `providerMessage`, because Polar's
    /// gateway and its OAuth routes answer in the other two.
    static func message(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }

        // A FastAPI validation error puts an array of objects in `detail`, so
        // every candidate is taken only when it is a string. Pasting a raw
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

        guard let raw = candidates.compactMap({ $0 as? String })
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { return nil }

        // Any token Polar quoted back at us goes before this reaches a screen.
        // Stripe truncates the key it echoes; nothing promises Polar does.
        let redacted = raw.replacing(/polar_[a-z]{3}_[A-Za-z0-9_\-]+/, with: "polar_…")

        // Whole sentences go, rather than the URL being cut out of them.
        // Providers append console deep links that run to a couple of hundred
        // characters, and removing just the link leaves "You can fix this at ."
        // behind. Where to click is `setupSteps`' job to say.
        //
        // A sentence ends at punctuation followed by whitespace, never at a
        // bare full stop: splitting on those would cut `https://polar.sh/x`
        // into a half that mentions no link and so survives the filter.
        var sentences: [String] = []
        var current: [String] = []
        for word in redacted.split(whereSeparator: \.isWhitespace) {
            current.append(String(word))
            if let last = word.last, ".!?".contains(last) {
                sentences.append(current.joined(separator: " "))
                current = []
            }
        }
        if !current.isEmpty { sentences.append(current.joined(separator: " ")) }

        let cleaned = sentences
            .filter { !$0.lowercased().contains("http://") && !$0.lowercased().contains("https://") }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return nil }

        // Bounded, but generously: 200 cut a permission message off before the
        // part that named the permission.
        return cleaned.count > 400 ? String(cleaned.prefix(397)) + "..." : cleaned
    }
}
