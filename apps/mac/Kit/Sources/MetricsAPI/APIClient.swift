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
    ) async throws -> T {
        try await send(path: path, method: "GET", query: query, body: Optional<Never>.none, as: type)
    }

    public func post<Body: Encodable & Sendable, T: Decodable & Sendable>(
        _ path: String, body: Body, as type: T.Type
    ) async throws -> T {
        try await send(path: path, method: "POST", query: [], body: body, as: type)
    }

    private func send<Body: Encodable & Sendable, T: Decodable & Sendable>(
        path: String, method: String, query: [URLQueryItem], body: Body?, as _: T.Type,
        isRetry: Bool = false
    ) async throws -> T {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 20

        if let token = try await tokens.validToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw APIError.offline
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("not an HTTP response")
        }

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
