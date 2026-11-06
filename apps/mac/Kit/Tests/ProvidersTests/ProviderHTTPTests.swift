import Foundation
import Testing

@testable import Providers

@Suite("the host allowlist")
struct HostAllowlistTests {
    @Test("matches an exact host, case-insensitively")
    func exact() {
        #expect(ProviderHTTP.hostAllowed("api.stripe.com", in: ["api.stripe.com"]))
        #expect(ProviderHTTP.hostAllowed("API.Stripe.COM", in: ["api.stripe.com"]))
        #expect(!ProviderHTTP.hostAllowed("api.stripe.com.evil.net", in: ["api.stripe.com"]))
    }

    /// The failure a plain `hasSuffix` would let through. A store that has
    /// been renamed and redirects is the ordinary way this gets reached, and
    /// the request carries an Admin API token.
    @Test("a wildcard matches one label and not a longer tail")
    func wildcard() {
        #expect(ProviderHTTP.hostAllowed("store.myshopify.com", in: ["*.myshopify.com"]))
        #expect(!ProviderHTTP.hostAllowed("a.b.myshopify.com", in: ["*.myshopify.com"]))
        #expect(!ProviderHTTP.hostAllowed("store.myshopify.com.attacker.net", in: ["*.myshopify.com"]))
        // The bare domain is not one label deep, so it does not match either.
        #expect(!ProviderHTTP.hostAllowed("myshopify.com", in: ["*.myshopify.com"]))
    }

    @Test("an empty allowlist allows nothing")
    func empty() {
        #expect(!ProviderHTTP.hostAllowed("api.stripe.com", in: []))
    }
}
