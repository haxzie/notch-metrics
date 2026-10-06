import Foundation
import Testing

@testable import MetricsAPI

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
