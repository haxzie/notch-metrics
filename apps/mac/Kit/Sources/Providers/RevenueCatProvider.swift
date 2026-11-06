import Foundation

/// RevenueCat, read from this Mac with the user's own v2 secret key.
///
/// Ported from `packages/integrations/src/providers/revenuecat`. Two things
/// about this provider shape the whole file and are worth knowing first:
///
/// - **Metrics are per project.** A key can see several, so one of them has
///   to be named before any figure can be asked for. `verify` resolves it and
///   refuses to guess, because picking the first silently would show one
///   app's MRR under another app's name.
/// - **Permission is a dial.** A Charts-only key — the least privilege these
///   metrics need — gets a 403 from `/projects`, and that is a perfectly good
///   key rather than a broken connection. Hence the 403 branch in
///   `resolveProject` and the mapping of 403 to `unsupported` below.
public struct RevenueCatProvider: LocalProvider {
    public let id = "revenuecat"
    public let allowedHosts = ["api.revenuecat.com"]
    static let base = "https://api.revenuecat.com/v2"

    public init() {}

    // MARK: - Credentials

    /// The secret key, and the project the user pinned the connection to.
    ///
    /// `project_id` is optional and an empty text field arrives as `""`,
    /// which is not an id and is not the same as "not provided". Normalised
    /// here so nothing downstream branches on an empty string — the same
    /// thing the Worker's credential schema does with its `z.literal("")`
    /// transform. The field is hidden in some builds of the connect sheet, so
    /// every path has to work with it absent.
    struct Credentials: Sendable {
        let secretKey: String
        let projectId: String?

        init(_ credentials: [String: String]) throws {
            secretKey = try requiredCredential(credentials, "secret_key")
            let project = credentials["project_id"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            projectId = project.isEmpty ? nil : project
        }
    }

    // MARK: - Verify

    public func verify(
        _ credentials: [String: String], http: ProviderHTTP
    ) async throws -> ProviderAccount {
        let creds = try Credentials(credentials)
        let project = try await resolveProject(creds: creds, http: http)

        // Proves `charts_metrics:overview:read`, which every metric here
        // needs. A key without it would otherwise become a stored connection
        // that fails on its first poll.
        let metrics = try await overview(creds: creds, projectId: project.id, http: http)

        // No `unavailableMetrics`: every metric here reads either the
        // Overview or the Charts revenue endpoint, and both sit behind the
        // one permission the call above just proved. There is no subset to
        // narrow to.
        return ProviderAccount(
            label: project.label,
            currency: metrics.currency?.uppercased())
    }

    /// Which project the numbers come from, and what to call the connection.
    func resolveProject(
        creds: Credentials, http: ProviderHTTP
    ) async throws -> (id: String, label: String) {
        let response = try await request("/projects", creds: creds, http: http,
                                        params: ["limit": "100"])

        // 403 and 401 are different answers here. RevenueCat says 401 for a
        // key it does not recognise and 403 for one that lacks the
        // permission — and a Charts-only key is exactly the second case.
        // Folding both into "bad key" would tell somebody with a perfectly
        // good key to go and make another one.
        if response.status == 403 {
            guard let projectId = creds.projectId else {
                throw ProviderFailure.unsupported(
                    "This key cannot list projects. Enter the project ID, or grant it Projects read.")
            }
            return (id: projectId, label: "Project \(projectId)")
        }
        guard response.ok else { throw Self.failure(for: response) }

        let projects = try response.json(ProjectList.self).items ?? []

        if let projectId = creds.projectId {
            guard let chosen = projects.first(where: { $0.id == projectId }) else {
                throw ProviderFailure.unsupported("This key cannot see project \(projectId).")
            }
            return (id: chosen.id, label: chosen.name ?? "Project \(chosen.id)")
        }

        guard let first = projects.first else {
            throw ProviderFailure.unsupported("This key can see no projects.")
        }
        // Asked for rather than guessed: the wrong project is a plausible
        // number under the wrong name, which nobody notices.
        if projects.count > 1 {
            let names = projects
                .map { "\($0.name ?? "Project \($0.id)") (\($0.id))" }
                .joined(separator: ", ")
            throw ProviderFailure.unsupported(
                "This key can see \(projects.count) projects. Enter the Project ID of one: \(names).")
        }
        return (id: first.id, label: first.name ?? "Project \(first.id)")
    }

    // MARK: - Requests

    /// One GET, with the response handed back unread.
    ///
    /// Separate from `get` because `resolveProject` has to see a 403 before
    /// it becomes a failure, and a helper that throws on every non-2xx takes
    /// that decision away from it.
    func request(
        _ path: String, creds: Credentials, http: ProviderHTTP, params: [String: String] = [:]
    ) async throws -> ProviderHTTP.Response {
        var components = URLComponents(string: Self.base + path)
        if !params.isEmpty {
            // Sorted, so a request is reproducible in a log and in a test.
            components?.queryItems = params.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url?.absoluteString else {
            throw ProviderFailure.badResponse("Could not build a RevenueCat URL for \(path).")
        }

        return try await http.get(
            url,
            headers: [
                // v2 insists on the scheme. A bare key, which v1 accepted, is
                // a 401 that reads as a wrong key rather than a malformed
                // header.
                "authorization": "Bearer \(creds.secretKey)",
                "accept": "application/json",
            ])
    }

    func get<T: Decodable>(
        _ type: T.Type, _ path: String, creds: Credentials, http: ProviderHTTP,
        params: [String: String] = [:]
    ) async throws -> T {
        let response = try await request(path, creds: creds, http: http, params: params)
        guard response.ok else { throw Self.failure(for: response) }
        return try response.json(type)
    }

    /// RevenueCat's status codes, in the buckets the caller acts differently on.
    static func failure(for response: ProviderHTTP.Response) -> ProviderFailure {
        let detail = message(in: response.body)
        switch response.status {
        case 401:
            return .authFailed(detail ?? "RevenueCat rejected that secret key.")
        case 403:
            // Not `authFailed`, and deliberately unlike the Worker's generic
            // `errorForStatus`, which buckets every 403 as rejected
            // credentials. RevenueCat's 403 means this key lacks one
            // permission — Projects read, most often — and `authFailed` marks
            // the whole connection broken and asks the user to replace a key
            // that answers everything else.
            return .unsupported(detail ?? "That key may not read this part of the project.")
        case 404:
            // Addressed by id: `/projects/{id}/metrics/...`. A 404 is a fact
            // about the project, not a malformed request.
            return .unsupported(detail ?? "RevenueCat has no such project or metric.")
        case 429:
            // 60 when it asked for nothing, matching the Worker. A nil wait
            // would have the refresh loop retry on its own tick, which on a
            // spent quota is immediately — and RevenueCat's Charts domain
            // allows only 25 calls a minute.
            let retry = response.header("retry-after").flatMap(TimeInterval.init) ?? 60
            return .rateLimited(detail ?? "RevenueCat's rate limit is spent.", retryAfter: retry)
        case 500...599:
            return .providerDown(detail ?? "RevenueCat is having trouble.")
        default:
            // The body almost always names the wrong part of the request.
            // Throwing it away leaves "RevenueCat returned 400" on screen and
            // the cause to be guessed from outside the system.
            return .badResponse(detail ?? "RevenueCat returned \(response.status).")
        }
    }

    /// RevenueCat's own explanation, when it sent one.
    ///
    /// v2 answers `{ type, message, doc_url }`; the gateway in front of it
    /// answers `{ error: { message } }` on a rejected key. Both are read, and
    /// anything unrecognised is dropped rather than pasted in raw: an HTML
    /// error page in a notch tile is worse than the bare status it replaces.
    private static func message(in body: Data) -> String? {
        struct Envelope: Decodable {
            struct Failure: Decodable { let message: String? }
            let message: String?
            let detail: String?
            let error: Failure?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return nil }
        for candidate in [envelope.message, envelope.detail, envelope.error?.message] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return nil
    }
}

/// RevenueCat's wire shapes, nested under the adapter that reads them.
///
/// Nested rather than at file scope because `Project`, `Overview` and
/// `RevenueMetric` are names other providers in this module want too. At the
/// top level the second one to be written fails to compile, and the error
/// names a file its author never touched.
extension RevenueCatProvider {
    struct Project: Decodable, Sendable {
        let id: String
        /// Optional: a key with Projects read but not the project's own
        /// metadata has been seen to omit it, and a non-optional field would
        /// turn that into a decode failure on an otherwise usable key.
        let name: String?
    }

    struct ProjectList: Decodable, Sendable {
        let items: [Project]?
    }

    struct Overview: Decodable, Sendable {
        let metrics: [OverviewMetric]?
        let currency: String?
    }

    struct OverviewMetric: Decodable, Sendable {
        let id: String
        /// Optional so a single null card does not fail the whole decode —
        /// the caller turns an absent value into a `badResponse` naming the
        /// card, which is the TS adapter's `typeof value !== "number"` check.
        let value: Double?
        /// Milliseconds since the epoch, and unused: `MetricValue` carries no
        /// `asOf`, so the Worker's "as of" stamp has nowhere to go here. Kept
        /// decoded rather than dropped so the shape stays readable beside the
        /// TS, and the field it would fill is one line away.
        let lastUpdatedAt: Double?

        enum CodingKeys: String, CodingKey {
            case id
            case value
            case lastUpdatedAt = "last_updated_at"
        }
    }

    struct RevenueMetric: Decodable, Sendable {
        /// Major units, as a decimal. Converted exactly once, by
        /// `minorUnits(_:currency:)`, and never divided by 100 afterwards.
        let value: Double?
        let currency: String?
    }
}
