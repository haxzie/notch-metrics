import Foundation
import Testing

@testable import Providers

/// Stripe's statuses, in the buckets the caller acts differently on.
///
/// Tested through `failure(for:)` rather than over a stubbed session: what is
/// worth pinning is which bucket each status lands in, and that a restricted
/// key does not mark the whole connection broken.
@Suite("stripe failures")
struct StripeFailureTests {
    private func response(_ status: Int, body: String = "", headers: [String: String] = [:])
        -> ProviderHTTP.Response
    {
        ProviderHTTP.Response(status: status, headers: headers, body: Data(body.utf8))
    }

    @Test("a rejected key is an auth failure, and carries Stripe's own words")
    func badKey() {
        let failure = StripeProvider.failure(
            for: response(401, body: #"{"error":{"message":"Invalid API Key provided"}}"#))
        #expect(failure == .authFailed("Invalid API Key provided"))
    }

    /// The one worth being deliberate about. A restricted key that cannot read
    /// subscriptions is a statement about one resource; calling it an auth
    /// failure would mark the connection broken and ask the user to replace a
    /// key that works for everything else.
    @Test("a restricted key is unsupported, not an auth failure")
    func restricted() {
        for status in [402, 403] {
            let failure = StripeProvider.failure(for: response(status))
            #expect(failure == .unsupported("That key may not read this part of the account."))
        }
    }

    @Test("a spent quota carries the wait Stripe asked for")
    func rateLimited() {
        let failure = StripeProvider.failure(
            for: response(429, headers: ["Retry-After": "30"]))
        #expect(failure == .rateLimited("Stripe's rate limit is spent.", retryAfter: 30))
    }

    @Test("a 5xx is their outage, retried rather than reported as a bad key")
    func down() {
        #expect(StripeProvider.failure(for: response(503)) == .providerDown("Stripe is having trouble."))
    }

    /// Throwing the body away leaves "Stripe returned 400" on screen, and the
    /// cause then has to be guessed from outside the system.
    @Test("any other 4xx keeps the explanation Stripe sent")
    func explained() {
        let failure = StripeProvider.failure(
            for: response(400, body: #"{"error":{"message":"Unknown parameter: limti"}}"#))
        #expect(failure == .badResponse("Unknown parameter: limti"))
    }

    @Test("and says the status when it sent none")
    func unexplained() {
        #expect(StripeProvider.failure(for: response(418)) == .badResponse("Stripe returned 418."))
    }
}

@Suite("stripe credentials")
struct StripeCredentialTests {
    /// The form will not submit an empty required field, so this is a bug
    /// rather than user error — but it reaches a live API either way, and an
    /// empty bearer token reads back as a revoked key.
    @Test("a missing secret key is refused before any request is made")
    func missing() async {
        let outcome = await Result {
            try await ProviderRegistry.verify("stripe", credentials: [:])
        }
        #expect(throws: ProviderFailure.self) { try outcome.get() }
    }

    /// Mixpanel rather than a provider mid-port. This used to name Paddle,
    /// which made the test fail the moment Paddle was registered — a port
    /// breaking a *different* provider's suite, for no reason anyone reading
    /// the failure would guess. Mixpanel is `coming_soon` with no
    /// implementation on either side, so it stays a safe stand-in.
    @Test("a connector with no adapter says so rather than failing obscurely")
    func notPorted() async {
        let outcome = await Result {
            try await ProviderRegistry.verify("mixpanel", credentials: ["secret": "x"])
        }
        #expect(throws: ProviderFailure.self) { try outcome.get() }
    }

    @Test("stripe is read on this Mac, and an unported connector is not")
    func registry() {
        #expect(ProviderRegistry.isLocal("stripe"))
        #expect(!ProviderRegistry.isLocal("mixpanel"))
    }
}

/// `Result` has no async throwing initialiser of its own.
extension Result where Failure == any Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
