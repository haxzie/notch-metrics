import Foundation

/// Stripe, read from this Mac with the user's own secret key.
///
/// Ported from `packages/integrations/src/providers/stripe`. `verify` is
/// deliberately the same two calls in the same order as the Worker's, because
/// the second one is not a health check: it is how a restricted key that
/// cannot read subscriptions is detected, and skipping it would offer MRR on
/// a connection that can never answer it.
public struct StripeProvider: LocalProvider {
    public let id = "stripe"
    public let allowedHosts = ["api.stripe.com"]
    private static let base = "https://api.stripe.com/v1"

    public init() {}

    private struct Account: Decodable {
        let id: String
        let defaultCurrency: String?
        let businessProfile: BusinessProfile?

        struct BusinessProfile: Decodable {
            let name: String?
        }

        enum CodingKeys: String, CodingKey {
            case id
            case defaultCurrency = "default_currency"
            case businessProfile = "business_profile"
        }
    }

    /// The metrics that need the subscriptions list, and so the scope to read it.
    static let subscriptionMetrics = [
        "mrr", "active_subscribers", "new_subscribers", "churned_subscribers",
    ]

    public func verify(
        _ credentials: [String: String], http: ProviderHTTP
    ) async throws -> ProviderAccount {
        let key = try requiredCredential(credentials, "secret_key")
        let account = try await get(Account.self, "/account", key: key, http: http)

        // A restricted key may read charges and not subscriptions. Narrowing
        // what is offered beats refusing the connection and telling somebody
        // their perfectly good key is broken.
        var unavailable: [String] = []
        do {
            _ = try await get(Empty.self, "/subscriptions?limit=1", key: key, http: http)
        } catch let failure as ProviderFailure {
            // Both of Stripe's answers for "this key may not read
            // subscriptions" are tolerable, and they land in different
            // buckets: a restricted key without the scope is a 403, and an
            // account that cannot serve the resource at all is a 402.
            switch failure {
            case .authFailed, .unsupported:
                unavailable = Self.subscriptionMetrics
            default:
                throw failure
            }
        }

        return ProviderAccount(
            label: account.businessProfile?.name ?? account.id,
            currency: account.defaultCurrency?.uppercased(),
            unavailableMetrics: unavailable)
    }

    private struct Empty: Decodable {}

    private func get<T: Decodable>(
        _ type: T.Type, _ path: String, key: String, http: ProviderHTTP
    ) async throws -> T {
        let response = try await http.get(
            Self.base + path,
            headers: [
                "authorization": "Bearer \(key)",
                // Pinned, so a future default on Stripe's side cannot change a
                // field under an installed app that has no way to be updated
                // for it. Matches the Worker's adapter.
                "stripe-version": "2024-06-20",
            ])
        guard response.ok else { throw Self.failure(for: response) }
        return try response.json(type)
    }

    /// Stripe's status codes, in the buckets the caller acts differently on.
    static func failure(for response: ProviderHTTP.Response) -> ProviderFailure {
        let detail = message(in: response.body)
        switch response.status {
        case 401:
            return .authFailed(detail ?? "Stripe rejected that secret key.")
        case 402, 403:
            // Not `authFailed`: a restricted key is a statement about one
            // resource, and marking the whole connection broken would ask the
            // user to replace a key that works for everything else.
            return .unsupported(detail ?? "That key may not read this part of the account.")
        case 429:
            let retry = response.header("retry-after").flatMap(TimeInterval.init)
            return .rateLimited(detail ?? "Stripe's rate limit is spent.", retryAfter: retry)
        case 500...599:
            return .providerDown(detail ?? "Stripe is having trouble.")
        default:
            // The body almost always names the wrong part of the request.
            // Throwing it away leaves "Stripe returned 400" on screen and the
            // cause to be guessed from outside the system.
            return .badResponse(detail ?? "Stripe returned \(response.status).")
        }
    }

    /// Stripe's own explanation, when it sent one.
    private static func message(in body: Data) -> String? {
        struct Envelope: Decodable {
            struct Failure: Decodable { let message: String? }
            let error: Failure?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body),
              let message = envelope.error?.message, !message.isEmpty
        else { return nil }
        return message
    }
}
