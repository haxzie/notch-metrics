import Foundation
import MetricsCore

public enum APIError: Error, Sendable, Equatable {
    case unauthorized
    case subscriptionRequired
    case rateLimited(retryAfter: Int)
    case server(status: Int, code: String?, message: String?)
    case transport(String)
    case decoding(String)
    case offline
}

public struct APIProblem: Decodable, Sendable {
    public let code: String?
    public let message: String?
}

public protocol TokenProviding: Sendable {
    func validToken() async throws -> String?
    func clear() async
}

/// Typed access to the Worker.
///
/// An actor because it owns the shared decoder and the in-flight refresh. The
/// decoder is configured once: building one per request is measurable when a
/// batch of eight series lands inside a spring animation.
public actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokens: any TokenProviding
    private let decoder: JSONDecoder

    public init(baseURL: URL, tokens: any TokenProviding, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokens = tokens
        self.session = session

        let decoder = JSONDecoder()
        // The wire uses camelCase throughout — the zod schemas are written that
        // way — so no key conversion. Dates stay as ISO strings and are parsed
        // where they are used, because a series of thirty points does not need
        // thirty Date allocations to be drawn.
        self.decoder = decoder
    }

    public func get<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem] = [], as type: T.Type
    ) async throws(APIError) -> T {
        try await send(path: path, method: "GET", query: query, body: Optional<Never>.none, as: type)
    }

    public func post<Body: Encodable & Sendable, T: Decodable & Sendable>(
        _ path: String, body: Body, as type: T.Type
    ) async throws(APIError) -> T {
        try await send(path: path, method: "POST", query: [], body: body, as: type)
    }

    public func delete<T: Decodable & Sendable>(
        _ path: String, as type: T.Type
    ) async throws(APIError) -> T {
        try await send(
            path: path, method: "DELETE", query: [], body: Optional<Never>.none, as: type)
    }

    public func patch<Body: Encodable & Sendable, T: Decodable & Sendable>(
        _ path: String, body: Body, as type: T.Type
    ) async throws(APIError) -> T {
        try await send(path: path, method: "PATCH", query: [], body: body, as: type)
    }

    private func send<Body: Encodable & Sendable, T: Decodable & Sendable>(
        path: String, method: String, query: [URLQueryItem], body: Body?, as _: T.Type,
        isRetry: Bool = false
    ) async throws(APIError) -> T {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 20

        // The catalogue is readable signed out, so a missing token is not an
        // error here — the request simply goes without one and comes back
        // without the user-specific parts.
        if let token = try? await tokens.validToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            // Never answered from URLCache. The cache keys on the URL alone,
            // and the catalogue is served `public, max-age=300` to anonymous
            // callers — so a signed-in fetch within five minutes of a
            // signed-out one got the anonymous body back, which lists no
            // connections. Every dropped widget then landed on "Pick a
            // connection" for an account that was plainly connected.
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                // Encoding our own request body cannot fail for any reason the
                // caller can act on, so it is reported as a decoding fault
                // rather than given a case of its own.
                throw APIError.decoding(String(describing: error))
            }
        }

        // Logged on both sides, because the interesting failures are the ones
        // with no exception: a 200 whose body is not what this build expects,
        // and a 4xx whose message is the only statement of what went wrong.
        // The path and the elapsed time are enough to line a tile's error up
        // against the Worker's own log for the same request.
        let started = Date()
        let label = "\(method) \(path)\(query.isEmpty ? "" : "?" + query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&"))"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            await LogFile.shared.write("api", "\(label) — offline")
            throw APIError.offline
        } catch {
            await LogFile.shared.write("api", "\(label) — transport: \(error.localizedDescription)")
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            await LogFile.shared.write("api", "\(label) — not an HTTP response")
            throw APIError.transport("not an HTTP response")
        }

        let ms = Int(Date().timeIntervalSince(started) * 1000)
        // The body only on a failure. A catalogue response is tens of
        // kilobytes and would bury everything around it, and a successful
        // metric body is the number already on screen.
        let detail =
            (200..<300).contains(http.statusCode)
            ? ""
            : " " + LogFile.redacted(String(decoding: data.prefix(400), as: UTF8.self))
        await LogFile.shared.write("api", "\(label) → \(http.statusCode) in \(ms)ms\(detail)")

        switch http.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(String(describing: error))
            }

        case 401:
            // One retry after a forced refresh, then give up. A second 401 is
            // a revoked token, and retrying it in a loop just burns the rate
            // limit on an account that needs to sign in again.
            guard !isRetry else {
                await tokens.clear()
                throw APIError.unauthorized
            }
            return try await send(
                path: path, method: method, query: query, body: body, as: T.self, isRetry: true)

        case 402:
            throw APIError.subscriptionRequired

        case 429:
            let retry = Int(http.value(forHTTPHeaderField: "retry-after") ?? "") ?? 60
            throw APIError.rateLimited(retryAfter: retry)

        default:
            let problem = try? decoder.decode(APIProblem.self, from: data)
            throw APIError.server(
                status: http.statusCode, code: problem?.code, message: problem?.message)
        }
    }
}

// MARK: - Typed calls the app actually makes

extension APIClient {
    /// The connector catalogue.
    ///
    /// Readable signed out, so the integrations list renders before anybody
    /// has an account — and folds in connected accounts when a token is
    /// present, so a row can say "Connected" without a second request and a
    /// flash of the wrong state.
    public func catalogue() async throws(APIError) -> ConnectorCatalogue {
        try await get("v1/connectors", as: ConnectorCatalogue.self)
    }

    /// Asks for a browser link to connect one integration.
    ///
    /// The app deliberately does not collect credentials itself: an OAuth
    /// flow needs a real address bar, and a native window asking for a Stripe
    /// key looks exactly like one a phishing app would show.
    public func connectLink(for connectorId: String) async throws(APIError) -> ConnectLink {
        try await post("v1/connect/\(connectorId)", body: EmptyBody(), as: ConnectLink.self)
    }

    public func connectStatus(for connectorId: String) async throws(APIError) -> ConnectStatus {
        try await get("v1/connect/\(connectorId)/status", as: ConnectStatus.self)
    }

    /// Every widget's number in one round trip.
    ///
    /// Results are index-aligned with the requests and partial success is
    /// normal: one broken provider must not blank a notch that has three
    /// working tiles on it.
    /// How many metrics the server will accept in one request.
    ///
    /// The Worker caps the batch so that one request cannot fan out into
    /// fifty provider calls inside a single invocation's budget. Thirteen
    /// widgets in one body is a 400 for the *whole* request, so every tile in
    /// the notch fails at once — which is why this is chunked here rather
    /// than left to each caller to remember.
    static let batchLimit = 12

    /// Fetches every metric, in as many requests as the server's cap needs.
    ///
    /// Sequential rather than concurrent on purpose: the point of batching is
    /// to arrive at the Worker as few requests as possible, and firing the
    /// chunks together would undo the per-integration spacing the server uses
    /// to stay inside a provider's rate limit.
    public func batch(_ requests: [MetricQueryRequest]) async throws(APIError) -> [MetricResult] {
        guard !requests.isEmpty else { return [] }

        var results: [MetricResult] = []
        results.reserveCapacity(requests.count)
        for chunk in stride(from: 0, to: requests.count, by: Self.batchLimit).map({ start in
            Array(requests[start..<min(start + Self.batchLimit, requests.count)])
        }) {
            let response = try await post(
                "v1/metrics/batch", body: MetricBatchBody(requests: chunk),
                as: MetricBatchResponse.self)
            // Index-aligned per chunk, so appending in order keeps the whole
            // reply aligned with what was asked for.
            results.append(contentsOf: response.results)
        }
        return results
    }

    /// One metric, for the widget preview.
    ///
    /// The real number through the real adapter — a preview built from
    /// invented data cannot show that a connection returns nothing, or that
    /// the account is in a different currency, which is exactly what somebody
    /// is checking before they commit a tile to the notch.
    public func metric(
        integrationId: String, metric: String, granularity: String, range: String
    ) async throws(APIError) -> MetricResult {
        try await get(
            "v1/metrics/query",
            query: [
                URLQueryItem(name: "integrationId", value: integrationId),
                URLQueryItem(name: "metric", value: metric),
                URLQueryItem(name: "granularity", value: granularity),
                URLQueryItem(name: "range", value: range),
            ],
            as: MetricResult.self)
    }

    /// The user's connected accounts.
    public func connections() async throws(APIError) -> [Integration] {
        try await get("v1/integrations", as: [Integration].self)
    }

    public func rename(connection id: String, to label: String) async throws(APIError) -> Integration {
        try await patch("v1/integrations/\(id)", body: ["label": label], as: Integration.self)
    }

    public func disconnect(_ id: String) async throws(APIError) -> OKResponse {
        try await delete("v1/integrations/\(id)", as: OKResponse.self)
    }
}

public struct OKResponse: Decodable, Sendable {
    public let ok: Bool
}

public struct EmptyBody: Encodable, Sendable {
    public init() {}
}

public struct ConnectLink: Decodable, Sendable {
    public let url: URL
    public let connectorId: String
    public let expiresIn: Int
}

public struct ConnectStatus: Decodable, Sendable {
    /// "none" | "pending" | "connected" | "expired"
    public let state: String
    public let integrationId: String?

    public var isConnected: Bool { state == "connected" }
    public var isPending: Bool { state == "pending" }
}
