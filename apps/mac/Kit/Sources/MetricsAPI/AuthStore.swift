import CryptoKit
import Foundation
import MetricsCore

/// The PKCE material for one in-flight sign-in.
public struct PendingAuth: Codable, Sendable {
    public let verifier: String
    public let state: String
    public let startedAt: Date

    public var isFresh: Bool { Date().timeIntervalSince(startedAt) < 600 }

    public var challenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    public static func start() -> PendingAuth {
        PendingAuth(
            verifier: Data.random(32).base64URLEncodedString(),
            state: Data.random(16).base64URLEncodedString(),
            startedAt: Date()
        )
    }
}

public enum AuthError: Error, Sendable, Equatable {
    /// The callback's `state` did not match. This is the CSRF guard.
    case stateMismatch
    case expired
    case noPendingSignIn
}

/// Holds the device token and serialises refreshes.
public actor AuthStore: TokenProviding {
    private let secrets: any SecretStore
    private var cached: String?
    private var inFlight: Task<String?, Never>?

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    public func validToken() async throws -> String? {
        if let cached { return cached }

        // Single-flight. Eight widgets refreshing at once would otherwise each
        // hit the Keychain, and on a token refresh they would each start one.
        if let inFlight { return await inFlight.value }

        let task = Task<String?, Never> { [secrets] in
            (try? secrets.string(for: .deviceToken)) ?? nil
        }
        inFlight = task
        let token = await task.value
        inFlight = nil
        cached = token
        return token
    }

    public func store(token: String) throws {
        try secrets.set(token, for: .deviceToken)
        cached = token
    }

    public func clear() async {
        cached = nil
        try? secrets.set(nil, for: .deviceToken)
    }

    public var isSignedIn: Bool {
        get async { (try? await validToken()) .flatMap { $0 } != nil }
    }
}

/// Drives the browser handshake and validates what comes back.
public struct AuthCoordinator: Sendable {
    private let pendingURL: URL

    public init(pendingURL: URL = AppPaths.pendingAuth) {
        self.pendingURL = pendingURL
    }

    /// Persisted, so quitting mid-sign-in is not a dead end — the callback can
    /// still be completed when the app comes back.
    public func begin() throws -> (authorizeQuery: [URLQueryItem], pending: PendingAuth) {
        let pending = PendingAuth.start()
        let data = try JSONEncoder().encode(pending)
        try FileManager.default.createDirectory(
            at: pendingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: pendingURL, options: .atomic)

        return (
            [
                URLQueryItem(name: "challenge", value: pending.challenge),
                URLQueryItem(name: "state", value: pending.state),
            ],
            pending
        )
    }

    /// Validates `notchmetrics://auth/callback?code=…&state=…`.
    public func complete(callback url: URL) throws -> (code: String, verifier: String) {
        guard let data = try? Data(contentsOf: pendingURL),
              let pending = try? JSONDecoder().decode(PendingAuth.self, from: data)
        else { throw AuthError.noPendingSignIn }

        guard pending.isFresh else {
            try? FileManager.default.removeItem(at: pendingURL)
            throw AuthError.expired
        }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value
        let state = items.first { $0.name == "state" }?.value

        // The CSRF guard. Without it, anything that can open a URL on this Mac
        // can hand the app a code minted for somebody else's account.
        guard let state, state == pending.state else { throw AuthError.stateMismatch }
        guard let code else { throw AuthError.noPendingSignIn }

        try? FileManager.default.removeItem(at: pendingURL)
        return (code, pending.verifier)
    }
}

extension Data {
    static func random(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
