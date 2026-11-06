import Foundation

/// Which connectors this build can run without the Worker.
///
/// Every live connector, in catalogue order. Mixpanel is absent and that is
/// not an oversight: it is `coming_soon` on the server with no implementation
/// on either side, so there is nothing to port.
///
/// `adapter(for:)` returning nil still means "this one is the Worker's",
/// which is what let the migration land provider by provider rather than as
/// one change that either worked or did not. It is also what a build older
/// than a newly served connector falls back to.
public enum ProviderRegistry {
    private static let all: [any LocalProvider] = [
        // Revenue
        StripeProvider(),
        DodoPaymentsProvider(),
        LemonSqueezyProvider(),
        PolarProvider(),
        PaddleProvider(),
        RevenueCatProvider(),
        ShopifyProvider(),
        // Product analytics
        PostHogProvider(),
        PlausibleProvider(),
        AmplitudeProvider(),
        // Developer
        GitHubProvider(),
        NpmProvider(),
        // AI
        OpenAIProvider(),
        AnthropicProvider(),
    ]

    public static func adapter(for id: String) -> (any LocalProvider)? {
        all.first { $0.id == id }
    }

    /// True when this Mac can verify and read the connector itself.
    public static func isLocal(_ id: String) -> Bool { adapter(for: id) != nil }

    /// Every id that has been ported, for the tests and for the settings pane.
    public static var localIds: [String] { all.map(\.id) }

    /// Checks one connector's credentials on this Mac.
    ///
    /// The HTTP client is built here from the adapter's own allowlist, so a
    /// caller cannot supply the wrong one. `session` is injectable for the
    /// tests and for nothing else.
    public static func verify(
        _ id: String, credentials: [String: String], session: URLSession? = nil
    ) async throws -> ProviderAccount {
        guard let adapter = adapter(for: id) else {
            throw ProviderFailure.unsupported("This build cannot check \(id) on its own yet.")
        }
        let http = ProviderHTTP(
            allowedHosts: adapter.allowedHosts, timeout: adapter.requestTimeout, session: session)
        return try await adapter.verify(credentials, http: http)
    }

    /// Reads one metric on this Mac.
    ///
    /// The HTTP client is built from the adapter's own allowlist here too, so
    /// there is exactly one place a provider client is constructed and no
    /// call site can pass the wrong hosts.
    public static func fetch(
        _ id: String, credentials: [String: String], window: MetricWindow,
        session: URLSession? = nil
    ) async throws -> MetricValue {
        guard let adapter = adapter(for: id) else {
            throw ProviderFailure.unsupported("This build cannot read \(id) on its own yet.")
        }
        let http = ProviderHTTP(
            allowedHosts: adapter.allowedHosts, timeout: adapter.requestTimeout, session: session)
        return try await adapter.fetch(credentials, window: window, http: http)
    }
}
