import Foundation
import MetricsCore

/// Claude, read from this Mac with the user's own organisation admin key.
///
/// Ported from `packages/integrations/src/providers/anthropic`. The id is
/// `anthropic` and the name the user reads is "Claude": the tile sits next to
/// "OpenAI" and has twelve characters to say which one it is, while the
/// provider id matches the `ProviderId` the catalogue serves, so one table
/// routes both halves.
///
/// `verify` is deliberately the same two calls in the same order as the
/// Worker's. The second is not a health check: the cost report and the usage
/// report are separately available on a scoped key, and skipping the probe
/// would offer API spend on a connection that can never answer it.
public struct AnthropicProvider: LocalProvider {
    public let id = "anthropic"
    public let allowedHosts = ["api.anthropic.com"]
    static let base = "https://api.anthropic.com/v1"

    public init() {}

    // No `requestTimeout` override: the Worker's adapter declares no
    // `requestTimeoutMs`, so eight seconds is what both halves use.

    public func verify(
        _ credentials: [String: String], http: ProviderHTTP
    ) async throws -> ProviderAccount {
        let creds = try Self.credentials(credentials)

        // Yesterday, unaligned, one bucket. Only the *cost* report snaps its
        // start up to a day boundary, so the usage probe may use a plain
        // `now - 24h`.
        var usage: [(String, String)] = [
            ("starting_at", ISO8601.string(from: Date().addingTimeInterval(-Self.day))),
            ("bucket_width", "1d"),
            ("limit", "1"),
        ]
        if let workspace = creds.workspaceId { usage.append(("workspace_ids[]", workspace)) }
        _ = try await Self.get(
            Page<UsageResult>.self, path: "/organizations/usage_report/messages",
            key: creds.adminKey, params: usage, http: http)

        // Spend is withheld rather than the three token metrics being listed,
        // which is the same narrowing stated the other way up: the catalogue
        // derives what is available from the metrics, so `verify` only has to
        // say what this key cannot reach.
        var unavailable: [String] = []

        do {
            _ = try await Self.get(
                Page<CostResult>.self, path: "/organizations/cost_report",
                key: creds.adminKey,
                params: [
                    // Yesterday 00:00 UTC: the most recent range that is a
                    // whole bucket of the only width this report has.
                    (
                        "starting_at",
                        ISO8601.string(
                            from: Self.startOfUTCDay(Date()).addingTimeInterval(-Self.day))
                    ),
                    ("limit", "1"),
                ], http: http)
        } catch let failure as ProviderFailure {
            // A permanent refusal narrows; a transient one is fatal.
            //
            // `unavailableMetrics` is written once at connect, so letting a
            // 503 pass would hide spend until the user reconnected. But
            // re-throwing everything else meant an optional probe could fail
            // the entire connection — which is what a malformed cost request
            // did, leaving Claude unconnectable even though all three token
            // metrics worked.
            switch failure {
            case .authFailed, .badResponse, .unsupported:
                unavailable = ["api_spend"]
            case .rateLimited, .providerDown:
                throw failure
            }
        }

        return ProviderAccount(
            // The Admin API exposes no organisation name. A second Claude
            // connection is distinguished by its workspace, or failing that by
            // the "(2)" the connection name appends — and because this field is
            // not optional where the Worker's is, the provider's own name is
            // what an organisation-wide key gets.
            label: creds.workspaceId ?? "Claude",
            currency: "USD",
            unavailableMetrics: unavailable)
    }

    // MARK: - Credentials

    /// An admin key, and the workspace to scope to if the user named one.
    struct Credentials {
        let adminKey: String
        /// Nil for "total every workspace in the organisation", which is what
        /// an empty field means. Empty-string and absent have to behave the
        /// same: a user who typed a workspace id and then cleared it would
        /// otherwise be scoped to `""` and see nothing at all.
        let workspaceId: String?
    }

    static func credentials(_ credentials: [String: String]) throws -> Credentials {
        let key = try requiredCredential(credentials, "admin_key")
        let workspace = credentials["workspace_id"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Credentials(
            adminKey: key,
            workspaceId: (workspace?.isEmpty ?? true) ? nil : workspace)
    }

    // MARK: - Time

    static let hour: TimeInterval = 60 * 60
    static let day: TimeInterval = 24 * hour

    /// Midnight UTC at the start of the day `date` falls in.
    ///
    /// The cost report's `starting_at` is snapped *up* to the next day
    /// boundary and its `ending_at` defaults to the start of today, so an
    /// unaligned timestamp inside the current day snaps to exactly that
    /// default and the request is refused with "ending date must be after
    /// starting date" — a 400 that reads as a bad key. `now - 24h` is inside
    /// the current day for all but the midnight UTC hour, which is why the
    /// connector could not be connected at all.
    ///
    /// The docs say the timestamp is simply snapped, so this is not inferable
    /// from them; it was found by walking the boundary against the live API.
    static func startOfUTCDay(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.startOfDay(for: date)
    }

    // MARK: - Requests

    static func get<T: Decodable>(
        _ type: T.Type, path: String, key: String, params: [(String, String)],
        http: ProviderHTTP
    ) async throws -> T {
        var components = URLComponents(string: Self.base + path)
        // An array rather than a dictionary all the way down, because two of
        // these parameters repeat: `workspace_ids[]` and `group_by[]` are both
        // list-valued, and a dictionary would keep one value of each.
        components?.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = components?.url?.absoluteString else {
            throw ProviderFailure.badResponse("Could not build a Claude URL for \(path).")
        }

        let response = try await http.get(
            url,
            headers: [
                "x-api-key": key,
                // Pinned, so a future default version on Anthropic's side
                // cannot rename a field under an installed app that has no way
                // to be updated for it. Matches the Worker's adapter.
                "anthropic-version": "2023-06-01",
                "accept": "application/json",
                // Asked for by the Admin API docs so Anthropic can see
                // integration traffic for what it is.
                "user-agent": "notch-metrics",
            ])

        if response.status == 401 || response.status == 403 {
            // The same rejection covers a bad key, a workspace-scoped key, and
            // an individual account that has no Admin API at all. All three are
            // the user's to fix and none of them is "try again later", so the
            // message has to name all three.
            //
            // This is the one place the port does *not* follow Stripe's rule
            // that a refusal about one resource is `.unsupported`: Anthropic
            // sends the same status whether the key is wrong or merely scoped,
            // so there is nothing here to tell the two apart. The narrowing
            // happens in `verify` instead, which catches this exact failure
            // from the cost probe and withholds spend rather than the
            // connection.
            throw ProviderFailure.authFailed(
                "Claude would not read your usage. This needs an organisation Admin key — "
                    + "workspace keys and individual accounts cannot read the Admin API.")
        }
        guard response.ok else { throw Self.failure(for: response) }
        return try response.json(type)
    }

    /// Anthropic's statuses, in the buckets the caller acts differently on.
    ///
    /// 401 and 403 never reach here: `get` has already turned them into the
    /// sentence above, which says more than a status can.
    static func failure(for response: ProviderHTTP.Response) -> ProviderFailure {
        let detail = message(in: response.body)
        switch response.status {
        case 429:
            // Sixty seconds when Anthropic named none, as the Worker's shared
            // `errorForStatus` does — a nil would have the caller retry on the
            // next tick and spend the quota again.
            let retry = response.header("retry-after").flatMap(TimeInterval.init) ?? 60
            return .rateLimited("Claude asked us to wait.", retryAfter: retry)
        case 500...599:
            return .providerDown(detail ?? "Claude is having trouble.")
        default:
            // The body almost always names the wrong part of the request.
            // Throwing it away leaves "Claude returned 400" on screen and the
            // cause to be guessed from outside the system — which is how a bad
            // query parameter survives a release.
            return .badResponse(detail ?? "Claude returned \(response.status).")
        }
    }

    /// Anthropic's own explanation, when it sent one.
    static func message(in body: Data) -> String? {
        struct Envelope: Decodable {
            struct Failure: Decodable { let message: String? }
            let error: Failure?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body),
              let message = envelope.error?.message, !message.isEmpty
        else { return nil }
        return message
    }
}
