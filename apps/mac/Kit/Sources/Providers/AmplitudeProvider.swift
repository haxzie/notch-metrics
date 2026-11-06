import Foundation

/// Amplitude, read from this Mac with the user's own key pair.
///
/// Ported from `packages/integrations/src/providers/amplitude`. Three facts
/// about this provider shape the whole file and are worth knowing first:
///
/// - **The Dashboard API is signed with HTTP Basic**, the API key as the user
///   and the secret key as the password. Not a bearer token: Amplitude
///   answers a bearer with a 401 that reads exactly like a mistyped key.
/// - **The two regions are separate deployments.** A US project's keys simply
///   do not exist in the EU one, which answers 401 just like a wrong secret —
///   so the host follows the stored region, and the 401 message says as much
///   rather than sending somebody off to issue another key.
/// - **There is no identity endpoint.** No "who am I", no project name, so
///   `verify` proves the pair with the smallest real query and the connection
///   can only be labelled by its key.
///
/// The manifest says `status: "beta"`, because every call here is shaped from
/// Amplitude's documentation rather than from a recorded response. That makes
/// this a faithful port of the Worker's arithmetic and not an improvement on
/// it: where the two could differ, the Worker wins.
public struct AmplitudeProvider: LocalProvider {
    public let id = "amplitude"

    /// Both regions, because the region is per connection while the allowlist
    /// is per adapter. Exactly the manifest's `allowedHosts`.
    public let allowedHosts = ["amplitude.com", "analytics.eu.amplitude.com"]

    public init() {}

    // MARK: - Credentials

    /// Which of Amplitude's two deployments a project lives in.
    public enum Region: String, Sendable {
        case us
        case eu

        /// The EU deployment is a different hostname, not a path or a header
        /// on the US one.
        public var host: String {
            switch self {
            case .us: return "amplitude.com"
            case .eu: return "analytics.eu.amplitude.com"
            }
        }
    }

    /// The key pair, and the region that selects the host.
    ///
    /// An absent or unrecognised region is `us`, which is both the manifest's
    /// default and the enum-with-a-fallback rule this app decodes every wire
    /// enum under. Refusing instead would break a connection stored before
    /// the field existed; guessing from the key is not possible, as both
    /// regions issue the same hex shape.
    struct Credentials: Sendable {
        let apiKey: String
        let secretKey: String
        let region: Region

        init(_ credentials: [String: String]) throws {
            apiKey = try requiredCredential(credentials, "api_key")
            secretKey = try requiredCredential(credentials, "secret_key")
            let raw = credentials["region"]?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            region = Region(rawValue: raw) ?? .us
        }

        var host: String { region.host }
    }

    /// `Basic base64(api_key:secret_key)`, which is how the Dashboard API is
    /// signed — the secret key is the password, not a bearer token.
    ///
    /// UTF-8 before base64 because that is what `Data` offers; the Worker
    /// uses `btoa`, which is Latin-1. The two agree here because both keys are
    /// hex, so there is nothing outside ASCII for either to disagree about —
    /// but if Amplitude ever issues a key that is not, this line is where the
    /// Worker and this adapter would start sending different credentials.
    static func authorization(_ creds: Credentials) -> String {
        let pair = "\(creds.apiKey):\(creds.secretKey)"
        return "Basic \(Data(pair.utf8).base64EncodedString())"
    }

    // MARK: - Verify

    public func verify(
        _ credentials: [String: String], http: ProviderHTTP
    ) async throws -> ProviderAccount {
        let creds = try Credentials(credentials)

        // A one-day active-users query. There is no identity endpoint on the
        // Dashboard API, so the cheapest thing that proves the pair works is
        // the smallest real query — and it proves the region too, which a
        // key-shape check never could.
        let today = Self.day(Date(), timeZone: .current)
        _ = try await get(
            ChartResponse.self, "/api/2/users", creds: creds,
            params: ["start": today, "end": today, "m": "active", "i": "1"], http: http)

        return ProviderAccount(
            // Amplitude never names the project over this API, so there is
            // nothing to distinguish two connections by but the key. Half of
            // it: the API key is not the secret, but it is still not ours to
            // print in full.
            label: "project \(creds.apiKey.prefix(6))…",
            // Not a money connector. A currency here would have the formatter
            // put a symbol in front of a user count.
            currency: nil)
    }

    // MARK: - Requests

    /// One Dashboard API call, as the region's host.
    func get<T: Decodable>(
        _ type: T.Type, _ path: String, creds: Credentials,
        params: [String: String], http: ProviderHTTP
    ) async throws -> T {
        var components = URLComponents(string: "https://\(creds.host)\(path)")
        // Sorted, so a request is reproducible in a log and in a test.
        components?.queryItems = params.sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url?.absoluteString else {
            throw ProviderFailure.badResponse("Could not build an Amplitude URL for \(path).")
        }

        let response = try await http.get(
            url,
            headers: [
                "authorization": Self.authorization(creds),
                "accept": "application/json",
            ])
        guard response.ok else { throw Self.failure(for: response, region: creds.region) }
        return try response.json(type)
    }

    /// Amplitude's statuses, in the buckets the caller acts differently on.
    static func failure(
        for response: ProviderHTTP.Response, region: Region
    ) -> ProviderFailure {
        let host = region.host
        switch response.status {
        case 401, 403:
            // `authFailed` for both, and unlike Stripe's 403 this is not a
            // statement about one resource: the Dashboard API has no scopes,
            // so a 403 here means the pair is not this deployment's. Naming
            // the status matters because the commonest cause is an EU
            // project's keys sent to the US host, and "rejected the
            // credentials" sends somebody off to issue a key they already have.
            return .authFailed(
                "Amplitude rejected these keys. Check they are the "
                    + "\(region.rawValue.uppercased()) project's pair — the other region answers "
                    + "\(response.status) too.")
        case 429:
            // 60 is the Worker's fallback. A nil would have the refresh loop
            // retry on its own tick, which on a spent quota is immediately.
            let retry = response.header("retry-after").flatMap(TimeInterval.init) ?? 60
            return .rateLimited("\(host) asked us to wait.", retryAfter: retry)
        case 500...599:
            // No body: a 5xx from this API is usually an HTML error page, and
            // that in a notch tile is worse than the bare status.
            return .providerDown("\(host) returned \(response.status).")
        default:
            // The body almost always names the wrong part of the request —
            // a malformed `e`, a start after the end. Throwing it away leaves
            // "amplitude.com returned 400" on screen and the cause to be
            // guessed from outside the system.
            return .badResponse(message(in: response.body) ?? "\(host) returned \(response.status).")
        }
    }

    /// Amplitude's own explanation, when it sent one.
    ///
    /// Three shapes because this API has used all three, and anything
    /// unrecognised is dropped rather than pasted in raw: an HTML page or a
    /// stack trace in a notch tile is worse than the status it replaces.
    static func message(in body: Data) -> String? {
        struct Envelope: Decodable {
            struct Nested: Decodable { let message: String? }
            /// `error` is a bare string on some endpoints and an object on
            /// others, so both are decoded and whichever arrived is used.
            let error: String?
            let errorObject: Nested?
            let message: String?

            enum CodingKeys: String, CodingKey {
                case error
                case message
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                error = try? container.decodeIfPresent(String.self, forKey: .error)
                errorObject = try? container.decodeIfPresent(Nested.self, forKey: .error)
                message = try? container.decodeIfPresent(String.self, forKey: .message)
            }
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return nil }
        for candidate in [envelope.error, envelope.errorObject?.message, envelope.message] {
            if let candidate, !candidate.isEmpty { return candidate }
        }
        return nil
    }
}
