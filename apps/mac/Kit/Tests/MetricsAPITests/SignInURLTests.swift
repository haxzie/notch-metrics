import Foundation
import Testing

@testable import MetricsAPI
import MetricsCore

@Suite struct SignInURLTests {
    private func coordinator() -> (AuthCoordinator, URL) {
        let pending = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("pending-auth.json")
        return (AuthCoordinator(pendingURL: pending), pending)
    }

    private var appBase: URL { URL(string: "http://localhost:3100")! }

    @Test("the sign-in URL carries the challenge and the state")
    func carriesTheQuery() throws {
        // The whole bug this pins: the Settings pane opened /desktop/auth bare,
        // and the page can only answer "this link is missing information".
        let (auth, _) = coordinator()
        let url = try auth.signInURL(appBase: appBase)

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)

        #expect(components.path == "/desktop/auth")
        #expect(Set(items.map(\.name)) == ["challenge", "state"])
        for item in items {
            #expect(item.value?.isEmpty == false)
        }
    }

    @Test("the challenge is sent, never the verifier")
    func sendsTheChallengeNotTheVerifier() throws {
        let (auth, pendingURL) = coordinator()
        let url = try auth.signInURL(appBase: appBase)

        let pending = try JSONDecoder().decode(
            PendingAuth.self, from: Data(contentsOf: pendingURL))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let challenge = components.queryItems?.first { $0.name == "challenge" }?.value

        #expect(challenge == pending.challenge)
        // Sending the verifier would make PKCE pointless: anything that could
        // read the URL could complete the sign-in.
        #expect(url.absoluteString.contains(pending.verifier) == false)
    }

    @Test("a fresh sign-in replaces the previous pending challenge")
    func startsFresh() throws {
        let (auth, _) = coordinator()
        let first = try auth.signInURL(appBase: appBase)
        let second = try auth.signInURL(appBase: appBase)
        #expect(first.query != second.query)
    }
}

@Suite struct TokenStorageTests {
    /// A store whose writes vanish — the failure mode the read-back catches.
    private final class AmnesiacStore: SecretStore, @unchecked Sendable {
        func string(for key: SecretKey) throws -> String? { nil }
        func set(_ value: String?, for key: SecretKey) throws {}
        func deleteAll(matching prefix: String) throws {}
    }

    @Test("a token that does not come back is a failed sign-in, not a silent one")
    func rejectsAWriteThatDoesNotPersist() async throws {
        let auth = AuthStore(secrets: AmnesiacStore())
        await #expect(throws: SecretStoreError.notPersisted) {
            try await auth.store(token: "a-device-token")
        }
        // And it must not report itself signed in on the strength of a cache
        // the next launch will not have.
        #expect(await auth.isSignedIn == false)
    }

    @Test("a working store signs in")
    func storesAndReportsSignedIn() async throws {
        let auth = AuthStore(secrets: InMemorySecretStore())
        try await auth.store(token: "a-device-token")
        #expect(await auth.isSignedIn)
    }
}
