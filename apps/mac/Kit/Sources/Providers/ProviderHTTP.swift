import Foundation

/// The only way an adapter reaches the network.
///
/// A port of `createHttp` in `packages/integrations/src/http.ts`, and it keeps
/// that file's guarantees rather than a subset of them. All four matter, and
/// none of them is the kind of thing that announces its absence:
///
/// - **The allowlist**, re-checked on every hop. Without it a provider that
///   30x-ed somewhere else would be handed the user's key.
/// - **Manual redirects.** `URLSession` follows them itself and reapplies the
///   `Authorization` header while doing so, which is exactly the leak the
///   allowlist exists to stop. Hence `willPerformHTTPRedirection` returning
///   nil and a loop here.
/// - **A byte cap**, so a provider having a bad day cannot make this process
///   hold 400 MB of JSON.
/// - **A timeout**, because a menu-bar app must not keep a connection open
///   for a minute over a number nobody is looking at.
public struct ProviderHTTP: Sendable {
    public static let defaultTimeout: TimeInterval = 8
    static let maxBytes = 4 * 1024 * 1024
    static let maxRedirects = 3

    private let allowedHosts: [String]
    private let timeout: TimeInterval
    private let session: URLSession

    public init(
        allowedHosts: [String],
        timeout: TimeInterval = ProviderHTTP.defaultTimeout,
        session: URLSession? = nil
    ) {
        self.allowedHosts = allowedHosts
        self.timeout = timeout
        self.session = session ?? URLSession(
            configuration: .ephemeral, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    /// `api.stripe.com` matches itself; `*.example.com` matches exactly one label.
    ///
    /// One label, not any depth: `*.myshopify.com` must match `store.myshopify.com`
    /// and not `store.evil.myshopify.com.attacker.net`, and `hasSuffix` alone
    /// says yes to the second.
    public static func hostAllowed(_ host: String, in allowed: [String]) -> Bool {
        let h = host.lowercased()
        return allowed.contains { pattern in
            let p = pattern.lowercased()
            guard p.hasPrefix("*.") else { return h == p }
            let suffix = String(p.dropFirst())  // ".example.com"
            guard h.hasSuffix(suffix) else { return false }
            return !h.dropLast(suffix.count).contains(".")
        }
    }

    public struct Response: Sendable {
        public let status: Int
        public let headers: [String: String]
        public let body: Data

        public var ok: Bool { (200..<300).contains(status) }

        /// Case-insensitive, because HTTP header names are and a dictionary is not.
        public func header(_ name: String) -> String? {
            let wanted = name.lowercased()
            return headers.first { $0.key.lowercased() == wanted }?.value
        }

        public func json<T: Decodable>(_ type: T.Type) throws -> T {
            do {
                return try JSONDecoder().decode(type, from: body)
            } catch {
                throw ProviderFailure.badResponse("The response could not be read.")
            }
        }
    }

    public func get(_ url: String, headers: [String: String] = [:]) async throws -> Response {
        try await send(url, method: "GET", headers: headers)
    }

    public func send(
        _ url: String, method: String, headers: [String: String] = [:], body: Data? = nil
    ) async throws -> Response {
        guard var target = URL(string: url) else {
            throw ProviderFailure.badResponse("\(url) is not a URL.")
        }

        for hop in 0...Self.maxRedirects {
            guard let host = target.host else {
                throw ProviderFailure.unsupported("\(target) names no host.")
            }
            // Before every request, including after a redirect. Checking only
            // the first would make the allowlist advice rather than a rule.
            guard Self.hostAllowed(host, in: allowedHosts) else {
                throw ProviderFailure.unsupported("\(host) is not a host this connector may reach.")
            }
            guard target.scheme?.lowercased() == "https" else {
                throw ProviderFailure.unsupported("\(host) was asked for over plain HTTP.")
            }

            var request = URLRequest(url: target, timeoutInterval: timeout)
            request.httpMethod = method
            request.httpBody = body
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

            let (data, response) = try await perform(request, host: host)
            guard let http = response as? HTTPURLResponse else {
                throw ProviderFailure.badResponse("\(host) did not answer with HTTP.")
            }

            if (300..<400).contains(http.statusCode) {
                guard let location = http.value(forHTTPHeaderField: "location") else {
                    throw ProviderFailure.badResponse("\(host) redirected with no location.")
                }
                guard hop < Self.maxRedirects, let next = URL(string: location, relativeTo: target)
                else {
                    throw ProviderFailure.badResponse("\(host) redirected too many times.")
                }
                target = next
                continue
            }

            // The declared length first, so an oversized body is refused
            // before it is held in memory; `data.count` second, because a
            // chunked response declares nothing.
            let declared = Int(http.value(forHTTPHeaderField: "content-length") ?? "") ?? 0
            if declared > Self.maxBytes || data.count > Self.maxBytes {
                throw ProviderFailure.badResponse("\(host) returned more than 4 MB.")
            }

            return Response(
                status: http.statusCode,
                headers: http.allHeaderFields.reduce(into: [:]) { out, pair in
                    if let name = pair.key as? String, let value = pair.value as? String {
                        out[name] = value
                    }
                },
                body: data)
        }

        throw ProviderFailure.badResponse("\(target.host ?? "the provider") redirected too many times.")
    }

    private func perform(_ request: URLRequest, host: String) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw ProviderFailure.providerDown("\(host) did not answer in time.")
        } catch let error as URLError
            where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw ProviderFailure.providerDown("This Mac appears to be offline.")
        } catch {
            throw ProviderFailure.providerDown("\(host) could not be reached.")
        }
    }
}

/// Refuses every redirect, so the loop above sees them instead.
///
/// `URLSession` otherwise follows a 30x itself and carries the
/// `Authorization` header to wherever it points, which would hand a user's
/// provider key to any host a compromised or merely misconfigured provider
/// named. Returning nil from this delegate makes the 30x the response.
private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
