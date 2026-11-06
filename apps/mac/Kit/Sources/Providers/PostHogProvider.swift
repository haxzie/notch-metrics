import Foundation

/// PostHog, read from this Mac with the user's own personal API key.
///
/// Ported from `packages/integrations/src/providers/posthog`. Every number
/// this connector answers is a HogQL `SELECT` rather than a REST read, and
/// the queries are the contract: a reworded one is a different number, and
/// nobody notices until the tile disagrees with PostHog's own dashboard.
///
/// `verify` is deliberately the same two calls in the same order as the
/// Worker's. The first names the connection and proves `user:read`; the
/// second is a literal, so it proves `query:read` and that this key can see
/// this project without reading a single event row off the query budget.
public struct PostHogProvider: LocalProvider {
    public let id = "posthog"
    /// Both of the manifest's hosts. Which one a request goes to is
    /// `Credentials.host`, chosen by the stored region — the allowlist
    /// permits the pair, it does not pick between them.
    ///
    /// The private API hosts, not the `*.i.posthog.com` ingestion ones: those
    /// are POST-only capture endpoints and answer nothing we ask for.
    public let allowedHosts = ["us.posthog.com", "eu.posthog.com"]

    /// Fifteen seconds, not the default eight.
    ///
    /// Every number here is a HogQL aggregate over the event table rather
    /// than a row read, and a ninety-day one measured five to nine and a half
    /// seconds across this connector's metrics. The default eight sits inside
    /// that spread, so the same widget timed out or answered depending on the
    /// day — which reads as a flaky connection rather than as a timeout that
    /// is simply set too low.
    public var requestTimeout: TimeInterval { 15 }

    public init() {}

    // MARK: - Credentials

    /// Which PostHog Cloud a key belongs to.
    ///
    /// US and EU are separate databases, not two views of one, so a US key is
    /// simply not found in the EU one. That is why the region is asked for on
    /// the form rather than probed: both answers are a 401.
    enum Region: String {
        case us
        case eu

        var host: String { self == .eu ? "eu.posthog.com" : "us.posthog.com" }
    }

    struct Credentials {
        let apiKey: String
        /// Empty means "whichever project this key is currently pointed at",
        /// resolved once per call from `/api/users/@me/`. A numeric id nobody
        /// knows by heart is the field people abandon the form on, and the
        /// key already names a default project — see `resolveProject`.
        let projectId: String?
        let region: Region

        var host: String { region.host }
    }

    static func credentials(_ credentials: [String: String]) throws -> Credentials {
        let key = try requiredCredential(credentials, "api_key")

        let rawRegion = credentials["region"]?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        // Absent is US, matching the manifest field's default — a connection
        // stored before the field existed is a US one.
        let region: Region
        if rawRegion.isEmpty {
            region = .us
        } else if let known = Region(rawValue: rawRegion) {
            region = known
        } else {
            // Refused rather than defaulted. Guessing US for an unreadable
            // region sends an EU key to the US host, and PostHog answers that
            // with the same 401 a revoked key gets — so the user spends the
            // afternoon rolling a key that was fine.
            throw ProviderFailure.unsupported(
                "\"\(rawRegion)\" is not a PostHog region. Pick United States or European Union.")
        }

        let rawProject = credentials["project_id"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Digits or empty, as the Worker's schema has it. The id is
        // interpolated into a URL path, so anything else is refused here
        // rather than sent and read back as a 404 about a missing project.
        guard rawProject.isEmpty || rawProject.allSatisfy(\.isNumber) else {
            throw ProviderFailure.unsupported("A PostHog project ID is a number.")
        }

        return Credentials(
            apiKey: key, projectId: rawProject.isEmpty ? nil : rawProject, region: region)
    }

    // MARK: - Verify

    public func verify(
        _ credentials: [String: String], http: ProviderHTTP
    ) async throws -> ProviderAccount {
        let creds = try Self.credentials(credentials)

        // Names the connection and proves `user:read` in one call.
        let identity = try await Self.me(creds, http: http)
        let project = creds.projectId ?? identity.team?.id.map(String.init)
        guard let project, !project.isEmpty else {
            throw ProviderFailure.unsupported("This key has no default project. Enter a project ID.")
        }

        // A literal, so it proves `query:read` and that this key can see this
        // project without reading a single event row off the budget.
        do {
            _ = try await Self.hogql(creds, project: project, query: "SELECT 1", name: "verify", http: http)
        } catch let failure as ProviderFailure {
            if case .authFailed = failure {
                // The key itself already answered `/users/@me/`, so a refusal
                // here is about the scope or the project, not the key.
                // Telling somebody their key is wrong sends them off to make
                // another one with the same scopes missing.
                throw ProviderFailure.authFailed(
                    "This key cannot run queries on that project. Give it the Query Read scope, "
                        + "and check the project ID.")
            }
            throw failure
        }

        let projectName = identity.team?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let orgName = identity.organization?.name?.trimmingCharacters(in: .whitespacesAndNewlines)

        // "Acme — Website" when both are known, so two projects in one org
        // are still told apart and two orgs with a "Website" each are too.
        let label: String
        if let projectName, let orgName, !projectName.isEmpty, !orgName.isEmpty,
           projectName != orgName {
            label = "\(orgName) — \(projectName)"
        } else if let projectName, !projectName.isEmpty {
            label = projectName
        } else if let orgName, !orgName.isEmpty {
            label = orgName
        } else {
            label = "Project \(project)"
        }

        return ProviderAccount(
            label: label,
            // Not about money. PostHog counts people and events.
            currency: nil,
            // Nothing is withheld: the two scopes this connector needs are
            // both proved above, and a key holding them answers all five
            // metrics or none of them.
            unavailableMetrics: [])
    }

    // MARK: - Requests

    static func me(_ creds: Credentials, http: ProviderHTTP) async throws -> Me {
        try await request(Me.self, "/api/users/@me/", creds: creds, http: http)
    }

    /// The project every query runs against.
    ///
    /// A typed id wins, so somebody with several projects can point two
    /// connections at two of them. Otherwise the key's own current project —
    /// which is a plain CRUD call, not a `/query`, so it does not touch the
    /// hourly read budget the query endpoint bills against.
    static func resolveProject(_ creds: Credentials, http: ProviderHTTP) async throws -> String {
        if let project = creds.projectId { return project }
        guard let id = try await me(creds, http: http).team?.id else {
            throw ProviderFailure.unsupported("This key has no default project. Enter a project ID.")
        }
        return String(id)
    }

    /// One HogQL query against a project.
    ///
    /// HogQL rather than a `TrendsQuery`: the trends response is typed
    /// `Record<string, any>` in PostHog's own schema and its field names are
    /// not in the docs, where a `SELECT` we wrote returns columns we named.
    /// Every query here is a bounded aggregate — PostHog bills `/query`
    /// against an hourly *bytes read* budget, so an unbounded scan is not
    /// merely slow, it spends somebody's quota.
    static func hogql(
        _ creds: Credentials, project: String, query: String, name: String, http: ProviderHTTP
    ) async throws -> [[Cell]] {
        // `name` lands in PostHog's own query_log, so a user looking at what
        // is hitting their project sees us by name rather than an anonymous
        // SELECT.
        let body = Request(query: .init(kind: "HogQLQuery", query: query), name: "notch:\(name)")
        guard let encoded = try? JSONEncoder().encode(body) else {
            throw ProviderFailure.badResponse("Could not build a PostHog query for \(name).")
        }

        let response = try await request(
            QueryResponse.self, "/api/projects/\(project)/query/", creds: creds, http: http,
            body: encoded)
        return response.results ?? []
    }

    static func request<T: Decodable>(
        _ type: T.Type, _ path: String, creds: Credentials, http: ProviderHTTP,
        body: Data? = nil
    ) async throws -> T {
        var headers = [
            "authorization": "Bearer \(creds.apiKey)",
            "accept": "application/json",
        ]
        if body != nil { headers["content-type"] = "application/json" }

        let response = try await http.send(
            "https://\(creds.host)\(path)", method: body == nil ? "GET" : "POST",
            headers: headers, body: body)
        guard response.ok else { throw failure(for: response, region: creds.region) }
        return try response.json(type)
    }

    // MARK: - Failures

    /// PostHog's status codes, in the buckets the caller acts differently on.
    static func failure(
        for response: ProviderHTTP.Response, region: Region
    ) -> ProviderFailure {
        let detail = message(in: response.body)
        switch response.status {
        case 401:
            // 401 names the region as well as the key. US and EU are separate
            // databases, so a US key presented to the EU host is not a wrong
            // password — it is a key that does not exist there, and PostHog
            // answers the same 401 either way. Somebody who picked the wrong
            // region would otherwise spend the afternoon rolling a key that
            // was fine.
            return .authFailed(
                "PostHog rejected this key. Check it is a \(region.rawValue.uppercased()) Cloud "
                    + "key — the other region answers 401 too.")
        case 403:
            // The status stays in the message, as the Worker's
            // `errorForStatus` has it: a 403 from a host that normally says
            // 401 is a WAF in front of the provider, and that is a different
            // afternoon from a key missing a scope.
            return .authFailed(
                detail.map { "PostHog rejected the credentials (403): \($0)" }
                    ?? "PostHog rejected the credentials (403).")
        case 429:
            // A spent quota, not a broken key. PostHog bills `/query` against
            // an hourly bytes-read budget, so this is the status a *working*
            // key gets after a busy hour; read as `authFailed` it would mark
            // the integration broken and stop polling, and the user would
            // have to reconnect to recover from being briefly over budget.
            //
            // Defaulted to a minute when PostHog sent no header, as the
            // Worker does: a nil wait means the refresh loop retries on its
            // own tick, which on a spent quota is immediately.
            let retry = response.header("retry-after").flatMap(TimeInterval.init) ?? 60
            return .rateLimited(detail ?? "PostHog's query quota is spent.", retryAfter: retry)
        case 500...599:
            return .providerDown(detail ?? "PostHog is having trouble.")
        default:
            // The body almost always names the wrong part of the query — a
            // column that does not exist, a function with the wrong arity.
            // Throwing it away leaves "PostHog returned 400" on screen and
            // the cause to be guessed from outside the system.
            return .badResponse(detail ?? "PostHog returned \(response.status).")
        }
    }

    /// PostHog's own explanation, when it sent one.
    ///
    /// `detail` is the shape that matters — PostHog's API is Django REST
    /// Framework — but the candidate order is the Worker's `providerMessage`,
    /// because the query endpoint answers in `error` on a HogQL syntax
    /// failure.
    static func message(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }

        // Every candidate is taken only when it is a string: DRF puts an
        // array of field errors in `detail` on a validation failure, and
        // pasting a raw array or an HTML page into a notch tile is worse than
        // the bare status it replaces.
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

        // Any key PostHog quoted back at us goes before this reaches a
        // screen. Stripe truncates the key it echoes; nothing promises
        // PostHog does.
        let redacted = raw.replacing(/ph[a-z]_[A-Za-z0-9_\-]+/, with: "ph…")

        // Whole sentences go, rather than the URL being cut out of them.
        // Providers append console deep links that run to a couple of hundred
        // characters, and removing just the link leaves "You can fix this at
        // ." behind. Where to click is `setupSteps`' job to say.
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

        // Bounded, but generously: 200 cut a permission message off before
        // the part that named the permission.
        return cleaned.count > 400 ? String(cleaned.prefix(397)) + "..." : cleaned
    }
}

/// PostHog's wire shapes, nested under the adapter that reads them.
///
/// Nested rather than at file scope because `Team`, `Me` and `QueryResponse`
/// are names half the connectors in this module want. At the top level the
/// second one to be written fails to compile, and the error names a file its
/// author never touched.
extension PostHogProvider {
    struct Team: Decodable {
        let id: Int?
        let name: String?
    }

    struct Me: Decodable {
        let team: Team?
        let organization: Organization?

        struct Organization: Decodable {
            let name: String?
        }
    }

    /// The `/query/` request body, which PostHog reads as a tagged query node.
    struct Request: Encodable {
        let query: Node
        let name: String

        struct Node: Encodable {
            let kind: String
            let query: String
        }
    }

    /// One cell of a HogQL result row.
    ///
    /// The rows are a positional `unknown[][]` on the wire: the columns are
    /// whatever the `SELECT` named, and ClickHouse is free to serialise a
    /// 64-bit count as a string so it survives JSON without losing
    /// precision. So each cell is decoded as whichever scalar arrived and
    /// read as a number afterwards, rather than being typed per column.
    enum Cell: Decodable, Equatable {
        case number(Double)
        case text(String)
        case flag(Bool)
        case other

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            // Bool first: `Double` would not decode `true` anyway, but the
            // order says which reading wins when both could.
            if let flag = try? container.decode(Bool.self) {
                self = .flag(flag)
            } else if let number = try? container.decode(Double.self) {
                self = .number(number)
            } else if let text = try? container.decode(String.self) {
                self = .text(text)
            } else {
                // A null, an object, or an array. Not a decode failure: one
                // unreadable cell in one row must not blank the whole tile,
                // and `number` below reads this as zero exactly as the
                // Worker's `toNumber` does.
                self = .other
            }
        }

        /// The Worker's `toNumber`: a string is parsed, anything else that is
        /// not a finite number is zero.
        var number: Double {
            switch self {
            case .number(let value):
                return value.isFinite ? value : 0
            case .text(let text):
                let parsed = Double(text)
                return (parsed?.isFinite == true) ? parsed! : 0
            // Deliberately zero rather than one. `toNumber` in the Worker
            // rejects a boolean too; the one place a boolean is meaningful is
            // the `is_current` column, and `isTrue` reads that.
            case .flag, .other:
                return 0
            }
        }

        /// ClickHouse serialises the `is_current` boolean as 0/1; tolerate a
        /// real boolean too.
        var isTrue: Bool {
            if case .flag(let flag) = self { return flag }
            return number == 1
        }
    }

    struct QueryResponse: Decodable {
        let results: [[Cell]]?
        let columns: [String]?
    }
}
