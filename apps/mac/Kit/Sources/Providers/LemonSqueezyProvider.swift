import Foundation

/// Lemon Squeezy, read from this Mac with the user's own API key.
///
/// Ported from `packages/integrations/src/providers/lemonsqueezy`. Two things
/// about this provider shape the whole file and are worth knowing before
/// reading it:
///
/// - The API is JSON:API, so every object arrives as `{ id, attributes }` and
///   a list as `{ data: [...], meta: { page } }`. Modelled as `Resource` and
///   `Page` rather than flattened per call site, because the envelope is the
///   same for orders, subscriptions, prices and stores.
/// - A store has exactly one currency and a price carries none of its own, so
///   the currency on an answer comes from `verify` recording the store's,
///   not from the row.
public struct LemonSqueezyProvider: LocalProvider {
    public let id = "lemonsqueezy"
    public let allowedHosts = ["api.lemonsqueezy.com"]
    static let base = "https://api.lemonsqueezy.com/v1"

    public init() {}

    // MARK: - JSON:API envelopes

    /// JSON:API: every object is `{ id, attributes }`.
    struct Resource<A: Decodable & Sendable>: Decodable, Sendable {
        let id: String
        let attributes: A
    }

    /// A list, with the paging block the walk reads `lastPage` out of.
    ///
    /// `data` is optional because an error body and a filtered-to-nothing
    /// response both arrive without it, and a non-optional field would turn
    /// "no orders yet" into a decode failure.
    struct Page<A: Decodable & Sendable>: Decodable, Sendable {
        let data: [Resource<A>]?
        let meta: Meta?

        struct Meta: Decodable, Sendable {
            let page: PageMeta?

            /// Camel case, unlike every `attributes` block in this API. Not a
            /// transcription slip: Lemon Squeezy really does send
            /// `meta.page.lastPage` beside `attributes.created_at`.
            struct PageMeta: Decodable, Sendable {
                let lastPage: Int?
                let currentPage: Int?
            }
        }
    }

    /// A single resource — `/users/me`, `/prices/{id}`.
    struct Single<A: Decodable & Sendable>: Decodable, Sendable {
        let data: Resource<A>?
    }

    // MARK: - Attribute blocks

    struct OrderAttributes: Decodable, Sendable {
        let storeId: Int?
        let currency: String
        /// Minor units, as Lemon Squeezy sends them. Never divided by 100
        /// here: money stays an integer all the way to the formatter.
        let total: Int
        let status: String
        let refunded: Bool?
        let refundedAmount: Int?
        let createdAt: String
        let userName: String?
        let userEmail: String?
        let firstOrderItem: OrderItem?

        struct OrderItem: Decodable, Sendable {
            let productName: String?
            let variantName: String?

            enum CodingKeys: String, CodingKey {
                case productName = "product_name"
                case variantName = "variant_name"
            }
        }

        enum CodingKeys: String, CodingKey {
            case storeId = "store_id"
            case currency
            case total
            case status
            case refunded
            case refundedAmount = "refunded_amount"
            case createdAt = "created_at"
            case userName = "user_name"
            case userEmail = "user_email"
            case firstOrderItem = "first_order_item"
        }
    }

    struct SubscriptionAttributes: Decodable, Sendable {
        let storeId: Int?
        let status: String
        let createdAt: String?
        let firstSubscriptionItem: SubscriptionItem?

        struct SubscriptionItem: Decodable, Sendable {
            let priceId: Int
            let quantity: Int?

            enum CodingKeys: String, CodingKey {
                case priceId = "price_id"
                case quantity
            }
        }

        enum CodingKeys: String, CodingKey {
            case storeId = "store_id"
            case status
            case createdAt = "created_at"
            case firstSubscriptionItem = "first_subscription_item"
        }
    }

    struct PriceAttributes: Decodable, Sendable {
        let unitPrice: Int
        let category: String
        let renewalIntervalUnit: String?
        let renewalIntervalQuantity: Int?

        enum CodingKeys: String, CodingKey {
            case unitPrice = "unit_price"
            case category
            case renewalIntervalUnit = "renewal_interval_unit"
            case renewalIntervalQuantity = "renewal_interval_quantity"
        }
    }

    struct StoreAttributes: Decodable, Sendable {
        let name: String?
        let currency: String?
    }

    struct UserAttributes: Decodable, Sendable {
        let name: String?
        let email: String?
    }

    // MARK: - Credentials

    /// The API key, and the store the user pinned the connection to.
    ///
    /// `store_id` is optional and an empty text field arrives as `""`, which
    /// is not a store id and is not the same as "every store". Normalised here
    /// so nothing downstream branches on an empty string — the same thing the
    /// Worker's credential schema does with a `z.literal("")` transform.
    struct Credentials: Sendable {
        let apiKey: String
        let storeId: String?

        init(_ credentials: [String: String]) throws {
            apiKey = try requiredCredential(credentials, "api_key")
            let store = credentials["store_id"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            storeId = store.isEmpty ? nil : store
        }

        /// Every list request carries it when the user pinned one store.
        var storeFilter: [String: String] {
            guard let storeId else { return [:] }
            return ["filter[store_id]": storeId]
        }
    }

    // MARK: - Verify

    public func verify(
        _ credentials: [String: String], http: ProviderHTTP
    ) async throws -> ProviderAccount {
        let creds = try Credentials(credentials)

        let me = try await get(Single<UserAttributes>.self, "/users/me", creds: creds, http: http)
        let stores = try await get(
            Page<StoreAttributes>.self, "/stores", creds: creds, http: http,
            params: ["page[size]": "100"])

        let rows = stores.data ?? []
        let chosen = creds.storeId.map { wanted in rows.first { $0.id == wanted } } ?? rows.first

        // A store id that does not belong to this key would otherwise fail
        // later as an empty dashboard rather than a rejected connection.
        // `unsupported` and not `authFailed`: the key itself is fine, and
        // marking the connection broken would ask the user to replace it.
        if let storeId = creds.storeId, chosen == nil {
            throw ProviderFailure.unsupported("This API key cannot see store \(storeId).")
        }

        let label: String
        if let storeId = creds.storeId {
            label = chosen?.attributes.name ?? "Store \(storeId)"
        } else {
            label = me.data?.attributes.name ?? me.data?.attributes.email ?? "Lemon Squeezy"
        }

        // No `unavailableMetrics`: a Lemon Squeezy key is read-write with no
        // scope dial, so there is no restricted-key case to narrow for. Every
        // metric either works on this key or on none.
        return ProviderAccount(
            label: label,
            currency: chosen?.attributes.currency?.uppercased())
    }

    // MARK: - Requests

    func get<T: Decodable>(
        _ type: T.Type, _ path: String, creds: Credentials, http: ProviderHTTP,
        params: [String: String] = [:]
    ) async throws -> T {
        var components = URLComponents(string: Self.base + path)
        if !params.isEmpty {
            // Sorted, so a request is reproducible in a log and in a test.
            components?.queryItems = params.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url?.absoluteString else {
            throw ProviderFailure.badResponse("Could not build a Lemon Squeezy URL for \(path).")
        }

        let response = try await http.get(
            url,
            headers: [
                "authorization": "Bearer \(creds.apiKey)",
                // Both are required, and the second one on a GET with no body
                // looks redundant until it is missing: Lemon Squeezy answers
                // 406 without them, which reads as a routing problem rather
                // than an absent header.
                "accept": "application/vnd.api+json",
                "content-type": "application/vnd.api+json",
            ])
        guard response.ok else { throw Self.failure(for: response) }
        return try response.json(type)
    }

    /// Lemon Squeezy's status codes, in the buckets the caller acts differently on.
    static func failure(for response: ProviderHTTP.Response) -> ProviderFailure {
        let detail = message(in: response.body)
        switch response.status {
        case 401:
            return .authFailed(detail ?? "Lemon Squeezy rejected that API key.")
        case 403, 404:
            // Not `authFailed`, with the same reasoning as Stripe's 403: this
            // is a statement about one resource — a store on another account,
            // a price that was deleted — and marking the whole connection
            // broken would ask the user to replace a key that works.
            //
            // 404 belongs here rather than with the 4xx default because this
            // adapter addresses resources by id (`/prices/{id}`), and a
            // deleted price is a fact about the store, not a malformed request.
            return .unsupported(detail ?? "That key may not read this part of the store.")
        case 429:
            let retry = response.header("retry-after").flatMap(TimeInterval.init)
            return .rateLimited(detail ?? "Lemon Squeezy's rate limit is spent.", retryAfter: retry)
        case 500...599:
            return .providerDown(detail ?? "Lemon Squeezy is having trouble.")
        default:
            // The body almost always names the wrong part of the request.
            // Throwing it away leaves "Lemon Squeezy returned 400" on screen
            // and the cause to be guessed from outside the system.
            return .badResponse(detail ?? "Lemon Squeezy returned \(response.status).")
        }
    }

    /// Lemon Squeezy's own explanation, when it sent one.
    ///
    /// JSON:API puts it in `errors[].detail`, which is a different shape from
    /// Stripe's `error.message` — hence a second reader rather than a shared
    /// one. `message` is accepted too: the API gateway in front of the
    /// service answers in that shape on a rejected key.
    private static func message(in body: Data) -> String? {
        struct Envelope: Decodable {
            struct Failure: Decodable {
                let detail: String?
                let title: String?
            }
            let errors: [Failure]?
            let message: String?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return nil }
        let fromErrors = (envelope.errors ?? [])
            .compactMap { $0.detail ?? $0.title }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        for candidate in [fromErrors, envelope.message ?? ""] where !candidate.isEmpty {
            return candidate
        }
        return nil
    }
}
