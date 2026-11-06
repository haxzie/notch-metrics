import Foundation

/// Dodo Payments, read from this Mac with the user's own API key.
///
/// Ported from `packages/integrations/src/providers/dodopayments`. Two things
/// in here are not incidental and are the reason the Worker's version looks
/// the way it does:
///
/// - The host comes from the declared `mode`, never from the shape of the
///   key. A live key sent to the test host answers 401, which reads as a bad
///   key rather than the wrong host and costs an hour before anyone suspects
///   it.
/// - `verify` probes each list separately, because Dodo keys carry scopes per
///   resource. A key with `payments:read` and no `subscriptions:read` is a
///   perfectly good key for revenue, and rejecting it outright told somebody
///   their key was wrong when it was merely narrow.
public struct DodoPaymentsProvider: LocalProvider {
    public let id = "dodopayments"
    /// Both, because the mode decides which one a given connection uses and
    /// the allowlist is fixed per adapter rather than per connection.
    public let allowedHosts = ["live.dodopayments.com", "test.dodopayments.com"]

    public init() {}

    // MARK: - Mode

    enum Mode: String, Sendable {
        case test
        case live

        var baseURL: String { "https://\(host)" }
        var host: String { "\(rawValue).dodopayments.com" }
    }

    /// Live unless the stored credential says otherwise.
    ///
    /// The same default the Worker's zod schema carries. A connection stored
    /// before the field existed, or one whose value has been hand-edited to
    /// something unrecognised, is live — which is the mode the overwhelming
    /// majority of keys are issued in, and the one whose failure (a test key
    /// against the live host) is a plain 401 rather than silently empty data.
    static func mode(in credentials: [String: String]) -> Mode {
        Mode(rawValue: credentials["mode"]?.lowercased() ?? "") ?? .live
    }

    // MARK: - Verify

    /// The metrics that read `/payments`, and so need `payments:read`.
    static let paymentMetrics = ["revenue", "one_time_sales", "recent_payments"]
    /// The metrics that read `/subscriptions`, and so need `subscriptions:read`.
    static let subscriptionMetrics = ["mrr", "active_subscribers"]

    public func verify(
        _ credentials: [String: String], http: ProviderHTTP
    ) async throws -> ProviderAccount {
        let key = try requiredCredential(credentials, "api_key")
        let mode = Self.mode(in: credentials)

        // There is no `/me` on this API, so the proof that the key works
        // against this host is a one-row list — and one list per resource,
        // because the scopes are per resource.
        let payments = try await probe(
            DodoPayment.self, "/payments", key: key, mode: mode, http: http)
        let subscriptions = try await probe(
            DodoSubscription.self, "/subscriptions", key: key, mode: mode, http: http)

        var unavailable: [String] = []
        if !payments.allowed { unavailable += Self.paymentMetrics }
        if !subscriptions.allowed { unavailable += Self.subscriptionMetrics }

        if !payments.allowed && !subscriptions.allowed {
            throw ProviderFailure.unsupported(
                "This key can read neither payments nor subscriptions. "
                    + "Give it payments:read and subscriptions:read.")
        }

        return ProviderAccount(
            // The API exposes no account or business name, so the mode is the
            // only thing that distinguishes two connections. The Worker
            // returns nil for live and lets `connectionName` supply the
            // provider's name; this field is not optional, so the provider's
            // name is written out here instead — which is the same string
            // `baseName` would have produced.
            label: mode == .test ? "Test" : "Dodo Payments",
            currency: (subscriptions.firstCurrency ?? payments.firstCurrency)?.uppercased(),
            unavailableMetrics: unavailable)
    }

    /// Whether this key may read a list, and the currency of its newest row.
    ///
    /// 401 and 403 are different answers from Dodo: 401 is a key it does not
    /// know, 403 is a key it knows that lacks the scope for this resource.
    /// `failure(for:)` folds the second into `.unsupported`, which is right
    /// for a metric fetch and not enough here, where the scope decides what
    /// to offer — so the status is read directly.
    private func probe<T: DodoRow>(
        _ type: T.Type, _ path: String, key: String, mode: Mode, http: ProviderHTTP
    ) async throws -> (allowed: Bool, firstCurrency: String?) {
        let response = try await request(
            path, key: key, mode: mode, http: http,
            params: ["page_size": "1", "page_number": "0"])
        if response.status == 403 { return (false, nil) }
        guard response.ok else { throw Self.failure(for: response, mode: mode) }
        let body = try response.json(DodoList<T>.self)
        return (true, body.items?.first?.currency)
    }

    // MARK: - HTTP

    /// Dodo answers `{ items: [...] }` with no cursor and no total.
    ///
    /// `items` is optional because an empty list has been observed to omit it
    /// altogether, and a decode failure there would report a working key as a
    /// response this build cannot read.
    struct DodoList<T: Decodable>: Decodable {
        let items: [T]?
    }

    func get<T: Decodable>(
        _ type: T.Type, _ path: String, key: String, mode: Mode, http: ProviderHTTP,
        params: [String: String] = [:]
    ) async throws -> T {
        let response = try await request(path, key: key, mode: mode, http: http, params: params)
        guard response.ok else { throw Self.failure(for: response, mode: mode) }
        return try response.json(type)
    }

    private func request(
        _ path: String, key: String, mode: Mode, http: ProviderHTTP, params: [String: String]
    ) async throws -> ProviderHTTP.Response {
        var components = URLComponents(string: mode.baseURL + path)
        if !params.isEmpty {
            // Sorted, so a request is reproducible in a log and in a test.
            components?.queryItems = params.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url?.absoluteString else {
            throw ProviderFailure.badResponse("Could not build a Dodo Payments URL for \(path).")
        }
        return try await http.get(url, headers: ["authorization": "Bearer \(key)"])
    }

    /// Dodo's status codes, in the buckets the caller acts differently on.
    static func failure(for response: ProviderHTTP.Response, mode: Mode = .live) -> ProviderFailure {
        let detail = message(in: response.body)
        switch response.status {
        case 401:
            // The mode is named because the commonest cause is a key issued
            // in the other environment, and "rejected the key" sends somebody
            // to make a new one instead of changing the dropdown.
            return .authFailed(
                detail ?? "Dodo Payments rejected that key for the \(mode.rawValue) environment.")
        case 403:
            // Not `authFailed`: a scope missing from the key is a statement
            // about one resource, and marking the whole connection broken
            // would ask the user to replace a key that works for the rest.
            return .unsupported(detail ?? "That key may not read this part of the account.")
        case 429:
            let retry = response.header("retry-after").flatMap(TimeInterval.init)
            return .rateLimited(
                detail ?? "Dodo Payments' rate limit is spent.", retryAfter: retry)
        case 500...599:
            return .providerDown(detail ?? "Dodo Payments is having trouble.")
        default:
            // The body almost always names the wrong part of the request.
            // Throwing it away leaves "returned 400" on screen and the cause
            // to be guessed from outside the system.
            return .badResponse(detail ?? "Dodo Payments returned \(response.status).")
        }
    }

    /// Dodo's own explanation, when it sent one.
    ///
    /// Three shapes, because this API has been seen to use all three:
    /// `{ message }`, `{ detail }` and a nested `{ error: { message } }`.
    /// Anything unrecognised is dropped rather than pasted in raw — an HTML
    /// error page in a notch tile is worse than the bare status it replaces.
    private static func message(in body: Data) -> String? {
        struct Envelope: Decodable {
            struct Nested: Decodable { let message: String? }
            let message: String?
            let detail: String?
            let error: Nested?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return nil }
        for candidate in [envelope.message, envelope.detail, envelope.error?.message] {
            if let candidate, !candidate.trimmingCharacters(in: .whitespaces).isEmpty {
                return candidate
            }
        }
        return nil
    }
}

/// Every Dodo row this adapter reads carries a currency, and the probe reads
/// it off whichever list the key is allowed to see.
protocol DodoRow: Decodable {
    var currency: String { get }
}

struct DodoSubscription: DodoRow {
    let subscriptionId: String
    let status: String
    /// Minor units, as Dodo sends them. Never divided by 100 here.
    let recurringPreTaxAmount: Double
    let currency: String
    /// Capitalised by Dodo ("Month"), which `toMonthly` does not expect.
    let paymentFrequencyInterval: String
    let paymentFrequencyCount: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case subscriptionId = "subscription_id"
        case status
        case recurringPreTaxAmount = "recurring_pre_tax_amount"
        case currency
        case paymentFrequencyInterval = "payment_frequency_interval"
        case paymentFrequencyCount = "payment_frequency_count"
        case createdAt = "created_at"
    }
}

struct DodoPayment: DodoRow {
    let paymentId: String
    /// Minor units, as Dodo sends them.
    let totalAmount: Double
    let currency: String
    let status: String
    let createdAt: String
    let customer: Customer?
    /// Null for a one-time purchase.
    let subscriptionId: String?
    /// Set alongside `subscription_id` when one checkout bought several.
    let subscriptionIds: [String]?

    struct Customer: Decodable {
        let name: String?
        let email: String?
    }

    enum CodingKeys: String, CodingKey {
        case paymentId = "payment_id"
        case totalAmount = "total_amount"
        case currency
        case status
        case createdAt = "created_at"
        case customer
        case subscriptionId = "subscription_id"
        case subscriptionIds = "subscription_ids"
    }

    /// A payment with no subscription behind it.
    ///
    /// Both fields, because Dodo added `subscription_ids` for
    /// multi-subscription checkouts and a payment can carry either. Checking
    /// only the singular would count a bundle renewal as a one-time sale.
    var isOneTime: Bool {
        (subscriptionId ?? "").isEmpty && (subscriptionIds ?? []).isEmpty
    }
}
