import Foundation

/// Paddle Billing, read from this Mac with the user's own API key.
///
/// Ported from `packages/integrations/src/providers/paddle`. `verify` is
/// deliberately the same three calls in the same order as the Worker's,
/// because the last two are not health checks: Paddle's permissions are per
/// entity, and a key scoped to transactions only is a perfectly good key that
/// must be offered revenue without being offered MRR.
public struct PaddleProvider: LocalProvider {
    public let id = "paddle"
    /// Both of the manifest's hosts. Which one a request actually goes to is
    /// `Credentials.host`, chosen by the stored mode — the allowlist permits
    /// the pair, it does not pick between them.
    public let allowedHosts = ["api.paddle.com", "sandbox-api.paddle.com"]

    public init() {}

    // MARK: - Credentials

    /// Which Paddle a key belongs to. Live and sandbox are separate stores
    /// with separate keys, not two views of one.
    enum Mode: String {
        case live
        case sandbox
    }

    struct Credentials {
        let apiKey: String
        let mode: Mode

        /// The host is chosen by the declared mode, never inferred from the key.
        ///
        /// New keys do carry `pdl_live_` or `pdl_sdbx_`, but keys issued
        /// before May 2025 are fifty opaque characters, and a wrong guess is a
        /// 403 that reads as a revoked key.
        var host: String {
            mode == .sandbox ? "sandbox-api.paddle.com" : "api.paddle.com"
        }
    }

    static func credentials(_ credentials: [String: String]) throws -> Credentials {
        let key = try requiredCredential(credentials, "api_key")
        let raw = credentials["mode"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Absent is live, matching the manifest field's default — a connection
        // stored before the field existed is a live one.
        guard !raw.isEmpty else { return Credentials(apiKey: key, mode: .live) }
        guard let mode = Mode(rawValue: raw.lowercased()) else {
            // Refused rather than defaulted. Guessing live for an unreadable
            // mode sends a sandbox key to the live host, and Paddle answers
            // that with a 403 the user reads as "my key was revoked".
            throw ProviderFailure.unsupported(
                "\"\(raw)\" is not a Paddle environment. Pick Live or Sandbox.")
        }
        return Credentials(apiKey: key, mode: mode)
    }

    // MARK: - Verify

    /// The metrics that need the transactions list, and so read permission on it.
    static let transactionMetrics = ["revenue", "recent_payments"]
    /// The metrics that need the subscriptions list.
    static let subscriptionMetrics = [
        "mrr", "active_subscribers", "new_subscribers", "churned_subscribers",
    ]

    public func verify(
        _ credentials: [String: String], http: ProviderHTTP
    ) async throws -> ProviderAccount {
        let creds = try Self.credentials(credentials)

        // The cheapest authenticated call Paddle has: no permission, no
        // paging. Proves the key is real and on the right host before
        // anything else, so a live key pasted into sandbox fails here with
        // one request rather than twice over below.
        _ = try await Self.get(Empty.self, "/event-types", creds: creds, http: http)

        var unavailable: [String] = []
        var currency: String?

        // Narrowing what is offered beats rejecting a key that was
        // deliberately scoped down. Both of Paddle's answers for "this key
        // may not read that" are tolerated and they land in different
        // buckets: a missing permission is a 403, which `failure(for:)` calls
        // `unsupported`, and a key revoked between the two calls is a 401.
        func permitted(_ grants: [String], _ probe: () async throws -> Void) async throws {
            do {
                try await probe()
            } catch let failure as ProviderFailure {
                switch failure {
                case .authFailed, .unsupported:
                    unavailable.append(contentsOf: grants)
                default:
                    throw failure
                }
            }
        }

        try await permitted(Self.transactionMetrics) {
            let page = try await Self.get(
                Page<Transaction>.self, "/transactions", creds: creds, http: http,
                params: ["per_page": "1"])
            // Paddle has no endpoint that reports the seller's currency, so
            // the newest transaction is the only thing that knows it.
            currency = page.data?.first?.currencyCode.uppercased()
        }
        try await permitted(Self.subscriptionMetrics) {
            _ = try await Self.get(
                Empty.self, "/subscriptions", creds: creds, http: http,
                params: ["per_page": "1"])
        }

        if unavailable.count == Self.transactionMetrics.count + Self.subscriptionMetrics.count {
            throw ProviderFailure.unsupported(
                "This key can read neither transactions nor subscriptions. "
                    + "Grant it read access to both.")
        }

        return ProviderAccount(
            // Paddle has no endpoint that names the seller, so the
            // environment is the only thing that tells two connections apart.
            // The Worker leaves a live connection's label empty and lets
            // `connectionName` supply the provider's name; nothing does that
            // here, so the provider's name is the label.
            label: creds.mode == .sandbox ? "Paddle Sandbox" : "Paddle",
            currency: currency,
            unavailableMetrics: unavailable)
    }

    struct Empty: Decodable {}

    // MARK: - Requests

    /// One page of any Paddle list endpoint.
    ///
    /// `data` is optional because an error body that slipped past a 2xx check
    /// has none, and a throwing decode of the whole response is a worse
    /// message than an empty walk.
    struct Page<T: Decodable>: Decodable {
        let data: [T]?
        let meta: Meta?

        struct Meta: Decodable {
            let pagination: Pagination?
        }

        struct Pagination: Decodable {
            let hasMore: Bool?
            let next: String?

            enum CodingKeys: String, CodingKey {
                case hasMore = "has_more"
                case next
            }
        }
    }

    static func url(
        _ path: String, creds: Credentials, params: [String: String]
    ) throws -> URL {
        var components = URLComponents(string: "https://\(creds.host)\(path)")
        // Sorted, so a request is reproducible in a log and in a test.
        components?.queryItems =
            params.isEmpty
            ? nil
            : params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else {
            throw ProviderFailure.badResponse("Could not build a Paddle URL for \(path).")
        }
        return url
    }

    static func get<T: Decodable>(
        _ type: T.Type, _ path: String, creds: Credentials, http: ProviderHTTP,
        params: [String: String] = [:]
    ) async throws -> T {
        try await fetchJson(type, try url(path, creds: creds, params: params), creds: creds, http: http)
    }

    static func fetchJson<T: Decodable>(
        _ type: T.Type, _ url: URL, creds: Credentials, http: ProviderHTTP
    ) async throws -> T {
        let response = try await http.get(
            url.absoluteString,
            headers: [
                "authorization": "Bearer \(creds.apiKey)",
                // Pinned. Paddle's default version is a per-account setting,
                // so an unpinned request's shape depends on who connected it.
                "paddle-version": "1",
                "accept": "application/json",
            ])
        guard response.ok else { throw failure(for: response, host: creds.host) }
        return try response.json(type)
    }

    // MARK: - Failures

    /// Paddle's status codes, in the buckets the caller acts differently on.
    static func failure(for response: ProviderHTTP.Response, host: String) -> ProviderFailure {
        let detail = message(in: response.body)
        switch response.status {
        case 401:
            return .authFailed(detail ?? "\(host) rejected that API key.")
        case 403:
            // Not `authFailed`, which is where the Worker's shared
            // `errorForStatus` puts a 403. Paddle's permissions are per
            // entity, so a 403 is a statement about one list and the key is
            // fine for the others; marking the whole connection broken would
            // ask the user to replace a key that works.
            return .unsupported(detail ?? "That key may not read this part of the account.")
        case 429:
            // Paddle sends `retry-after` on its per-key limit. 60 is the
            // Worker's fallback, and a nil here would mean polling again on
            // the next tick into the same wall.
            let retry = response.header("retry-after").flatMap(TimeInterval.init) ?? 60
            return .rateLimited(detail ?? "\(host) asked us to wait.", retryAfter: retry)
        case 500...599:
            return .providerDown(detail ?? "\(host) is having trouble.")
        default:
            // The body almost always names the wrong part of the request.
            // Throwing it away leaves "Paddle returned 400" on screen and the
            // cause to be guessed from outside the system.
            return .badResponse(detail ?? "\(host) returned \(response.status).")
        }
    }

    /// Paddle's own explanation, when it sent one.
    ///
    /// `error.detail` is the sentence; `error.code` is the slug. The
    /// `documentation_url` alongside them is deliberately not used: a
    /// hundred-character deep link in a notch tile crowds out the sentence
    /// that says what went wrong.
    static func message(in body: Data) -> String? {
        struct Envelope: Decodable {
            struct Failure: Decodable {
                let detail: String?
                let code: String?
            }
            let error: Failure?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return nil }
        for candidate in [envelope.error?.detail, envelope.error?.code] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return nil
    }
}
