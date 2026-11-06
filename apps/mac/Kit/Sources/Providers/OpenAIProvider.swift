import Foundation

/// OpenAI's organisation usage and cost reports, read from this Mac with the
/// user's own admin key.
///
/// Ported from `packages/integrations/src/providers/openai`. `verify` is
/// deliberately the same two calls in the same order as the Worker's, and the
/// second one is not a health check: the cost report is a separate permission
/// from the usage report on a scoped admin key, and skipping the probe would
/// offer spend on a connection that can never answer it.
public struct OpenAIProvider: LocalProvider {
    public let id = "openai"
    public let allowedHosts = ["api.openai.com"]
    static let base = "https://api.openai.com/v1"

    /// The one metric the cost report backs, withheld when that report refuses.
    static let costMetrics = ["api_spend"]

    public init() {}

    // MARK: - Credentials

    /// An admin key, and the project to narrow every report to.
    ///
    /// The project is genuinely optional: left empty, every report totals the
    /// whole organisation. So this is not `requiredCredential` with a
    /// friendlier message — an absent project id is the documented default,
    /// and `project_ids[]` must then be left off the query rather than sent
    /// empty, which OpenAI reads as "a project whose id is the empty string"
    /// and answers with zeroes.
    struct Credentials {
        let adminKey: String
        let projectId: String?
    }

    static func credentials(_ credentials: [String: String]) throws -> Credentials {
        let project = credentials["project_id"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Credentials(
            adminKey: try requiredCredential(credentials, "admin_key"),
            projectId: (project?.isEmpty == false) ? project : nil)
    }

    // MARK: - Verify

    public func verify(
        _ credentials: [String: String], http: ProviderHTTP
    ) async throws -> ProviderAccount {
        let creds = try Self.credentials(credentials)

        // Yesterday onwards, one bucket. The window does not matter — this
        // call exists to prove the key is an admin key before anything is
        // stored, and an organisation with no traffic yesterday still answers
        // 200 with an empty bucket.
        let usage = Self.query(
            "/organization/usage/completions",
            params: [
                "start_time": Self.unixSeconds(Date().addingTimeInterval(-Self.daySeconds)),
                "bucket_width": "1d",
                "limit": "1",
            ],
            projectId: creds.projectId)
        _ = try await Self.get(Page<UsageResult>.self, usage, creds: creds, http: http)

        var unavailable: [String] = []
        var label = creds.projectId

        // Cost is a separate permission from usage on a scoped admin key.
        // Narrowed rather than fatal: a key that can read tokens but not
        // dollars is still worth four working widgets.
        do {
            let costs = Self.query(
                "/organization/costs",
                params: [
                    "start_time": Self.unixSeconds(Date().addingTimeInterval(-Self.daySeconds)),
                    "limit": "1",
                ],
                // No project filter here, matching the Worker: this probe asks
                // only whether the cost report answers at all.
                projectId: nil)
            let body = try await Self.get(Page<CostResult>.self, costs, creds: creds, http: http)
            label = body.data.flatMap { $0.results }
                .compactMap { $0.organizationId }
                .first ?? label
        } catch let failure as ProviderFailure {
            // A permanent refusal narrows; a transient one is fatal.
            //
            // `unavailableMetrics` is written once at connect time, so
            // swallowing a 500 or a rate limit would hide spend permanently
            // over a bad thirty seconds. But treating every failure as a
            // narrowing is the other half of the same bug, and letting an
            // *optional* probe fail the whole connection is what left the
            // Claude connector unconnectable while all four token metrics
            // worked.
            switch failure {
            case .authFailed, .badResponse, .unsupported:
                unavailable = Self.costMetrics
            case .rateLimited, .providerDown:
                throw failure
            }
        }

        return ProviderAccount(
            // The organisation id when the cost report named one, the project
            // id when one was given, and the provider's name as a last resort:
            // nothing on the usage report identifies the organisation.
            label: label ?? "OpenAI",
            currency: "USD",
            unavailableMetrics: unavailable)
    }

    // MARK: - Requests

    static let hourSeconds: TimeInterval = 60 * 60
    static let daySeconds: TimeInterval = 24 * hourSeconds

    static func unixSeconds(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970.rounded(.down)))
    }

    /// One report URL, with the project filter applied only when there is one.
    ///
    /// `project_ids[]` is appended rather than set because the parameter is a
    /// repeated-key array on OpenAI's side; one value is all this connector
    /// ever sends, but the name has to keep its brackets either way.
    static func query(
        _ path: String, params: [String: String], projectId: String?
    ) -> String {
        var components = URLComponents(string: base + path)
        // Sorted, so a request is reproducible in a log and in a test.
        var items = params.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        if let projectId { items.append(URLQueryItem(name: "project_ids[]", value: projectId)) }
        components?.queryItems = items
        return components?.url?.absoluteString ?? base + path
    }

    static func get<T: Decodable>(
        _ type: T.Type, _ url: String, creds: Credentials, http: ProviderHTTP
    ) async throws -> T {
        let response = try await http.get(
            url,
            headers: [
                "authorization": "Bearer \(creds.adminKey)",
                "accept": "application/json",
            ])
        guard response.ok else { throw failure(for: response) }
        return try response.json(type)
    }

    /// OpenAI's status codes, in the buckets the caller acts differently on.
    static func failure(for response: ProviderHTTP.Response) -> ProviderFailure {
        let detail = message(in: response.body)
        switch response.status {
        case 401, 403:
            // Deliberately not the generic "rejected the credentials", and
            // deliberately `authFailed` rather than `unsupported` even though
            // this is nominally a permissions answer: on these two endpoints
            // the overwhelmingly common cause is a perfectly valid *project*
            // key, which cannot read usage at all and never will. Telling
            // somebody their key is wrong sends them off to regenerate the
            // same kind again.
            //
            // The one place a 403 here really is about a single resource is
            // the cost report on a scoped admin key, and `verify` handles that
            // locally by narrowing rather than by widening this bucket.
            return .authFailed(
                "OpenAI would not read your usage. This needs an organisation Admin key, "
                    + "not a project or user key.")
        case 429:
            let retry = response.header("retry-after").flatMap(TimeInterval.init)
            return .rateLimited(detail ?? "OpenAI's rate limit is spent.", retryAfter: retry)
        case 500...599:
            return .providerDown(detail ?? "OpenAI is having trouble.")
        default:
            // The body almost always names the wrong part of the request.
            // Throwing it away leaves "OpenAI returned 400" on screen and the
            // cause to be guessed from outside the system.
            return .badResponse(detail ?? "OpenAI returned \(response.status).")
        }
    }

    /// OpenAI's own explanation, when it sent one.
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
