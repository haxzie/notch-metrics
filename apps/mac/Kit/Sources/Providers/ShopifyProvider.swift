import Foundation

/// Shopify, read from this Mac with the store's own Admin API token.
///
/// Ported from `packages/integrations/src/providers/shopify`. Two things here
/// are not the shape of the other payment connectors, and both are the
/// store's fault rather than a choice:
///
/// The credential is a *pair* — a shop domain and a token — because the Admin
/// API has no global host. The domain is normalised before anything branches
/// on it, so `https://My-Store.myshopify.com/admin` and `my-store` reach the
/// same store.
///
/// And every call is one POST to a GraphQL endpoint that answers **200 for
/// most of what went wrong**: a missing scope, a throttle and a query that
/// costs too much all arrive as `errors` beside a null `data`. Reading only
/// the status code would turn each of them into an empty tile with no
/// explanation, so the body is read for all three.
public struct ShopifyProvider: LocalProvider {
    public let id = "shopify"

    /// The manifest's own allowlist, passed through rather than widened.
    ///
    /// One wildcard label deep, which is exactly what a shop domain is.
    /// `ProviderHTTP.hostAllowed` matches a single label, so
    /// `store.myshopify.com` passes and `store.myshopify.com.attacker.net`
    /// does not — and the check runs again on every redirect hop, so a
    /// renamed store that 30x-es elsewhere fails the allowlist rather than
    /// replaying the Admin token at whatever answered.
    public let allowedHosts = ["*.myshopify.com"]

    /// Pinned, never `latest` or `unstable`.
    ///
    /// A Shopify version is supported for twelve months and then starts
    /// answering with the next one's shapes. Pinning means an upgrade is a
    /// commit with a test run behind it; `latest` means the store's numbers
    /// change on Shopify's release day, in production, on a Tuesday. The same
    /// version the Worker's adapter pins.
    static let apiVersion = "2026-10"

    public init() {}

    // MARK: - Credentials

    struct Credentials: Sendable {
        /// Already normalised, so no call site can send a vanity domain.
        let shopDomain: String
        let accessToken: String

        var endpoint: String {
            "https://\(shopDomain)/admin/api/\(ShopifyProvider.apiVersion)/graphql.json"
        }

        /// What to call the store before `verify` has asked it its name.
        var handle: String {
            shopDomain.hasSuffix(".myshopify.com")
                ? String(shopDomain.dropLast(".myshopify.com".count))
                : shopDomain
        }
    }

    /// `https://My-Store.myshopify.com/admin/` → `my-store.myshopify.com`.
    ///
    /// A bare handle gets the suffix. Anything else is left alone for the
    /// check in `credentials(_:)` to reject by name — silently rewriting
    /// `shop.example.com` into `shop.example.com.myshopify.com` would fail
    /// later as a 404 that reads like a deleted store.
    ///
    /// Idempotent, because this runs on every fetch against a blob that was
    /// already normalised when it was stored, exactly as the Worker's Zod
    /// `.transform` does.
    static func normaliseShopDomain(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let withoutScheme =
            trimmed.hasPrefix("https://")
            ? String(trimmed.dropFirst("https://".count))
            : trimmed.hasPrefix("http://") ? String(trimmed.dropFirst("http://".count)) : trimmed
        let host = withoutScheme.split(separator: "/", omittingEmptySubsequences: false).first ?? ""
        if !host.isEmpty && !host.contains(".") { return "\(host).myshopify.com" }
        return String(host)
    }

    /// The stored blob as something that can be sent.
    ///
    /// Both halves are checked here rather than at the first request, because
    /// the failure a wrong domain produces is a 404 — which reads as a deleted
    /// store and sends the user looking for a problem they do not have.
    static func credentials(_ raw: [String: String]) throws -> Credentials {
        let domain = normaliseShopDomain(try requiredCredential(raw, "shop_domain"))
        // A `.myshopify.com` host, one label deep, starting with a letter or
        // digit. The literal is inline rather than a stored `Regex`, which is
        // not `Sendable` and so cannot be a static on a `Sendable` provider.
        guard domain.wholeMatch(of: /[a-z0-9][a-z0-9-]*\.myshopify\.com/) != nil else {
            throw ProviderFailure.authFailed(
                "A Shopify store's Admin API lives on its .myshopify.com domain, "
                    + "not on a custom storefront domain.")
        }

        let token = try requiredCredential(raw, "access_token")
        // `shpat_` for a custom app's Admin token, `shpca_` for a
        // collaborator's. Both are what the manifest's `pattern` accepts.
        guard token.wholeMatch(of: /shp(at|ca)_[A-Za-z0-9]+/) != nil else {
            throw ProviderFailure.authFailed(
                "An Admin API access token starts with shpat_.")
        }

        return Credentials(shopDomain: domain, accessToken: token)
    }

    // MARK: - Verify

    static let VERIFY = """
        query NotchVerify {
          shop { name currencyCode myshopifyDomain }
          ordersCount(limit: 1) { count }
          customersCount(limit: 1) { count }
        }
        """

    struct VerifyData: Decodable {
        let shop: Shop?
        let ordersCount: Count?
        let customersCount: Count?

        struct Shop: Decodable {
            let name: String?
            let currencyCode: String?
            let myshopifyDomain: String?
        }

        struct Count: Decodable {
            let count: Int?
        }
    }

    /// The metrics that come off the orders connection, and so need `read_orders`.
    static let orderMetrics = [
        "revenue", "orders", "average_order_value", "refunds", "recent_payments",
    ]
    /// The two that come off the customers connection, and so need `read_customers`.
    static let customerMetrics = ["customers", "new_customers"]

    public func verify(
        _ credentials: [String: String], http: ProviderHTTP
    ) async throws -> ProviderAccount {
        let creds = try Self.credentials(credentials)

        // One round trip, tolerating per-field errors: a token missing
        // `read_customers` returns the shop and a null `customersCount` beside
        // an ACCESS_DENIED, and narrowing on that is better than rejecting a
        // key that reads orders perfectly well.
        let data = try await Self.unthrottled {
            try await graphql(
                VerifyData.self, creds, query: Self.VERIFY, tolerateErrors: true, http: http)
        }

        guard let shop = data.shop else {
            throw ProviderFailure.authFailed(
                "\(creds.shopDomain) rejected the token, or the app it belongs to "
                    + "has no API access.")
        }

        let canReadOrders = data.ordersCount != nil
        let canReadCustomers = data.customersCount != nil

        if !canReadOrders && !canReadCustomers {
            throw ProviderFailure.authFailed(
                "This token can read neither orders nor customers. Add the read_orders "
                    + "and read_customers scopes to the app, then reinstall it.")
        }

        // Said as what the token *cannot* read, so this does not become a
        // second copy of the catalogue that has to stay in step with `fetch`.
        var unavailable: [String] = []
        if !canReadOrders { unavailable.append(contentsOf: Self.orderMetrics) }
        if !canReadCustomers { unavailable.append(contentsOf: Self.customerMetrics) }

        let name = shop.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ProviderAccount(
            label: (name?.isEmpty == false ? name! : nil) ?? creds.handle,
            currency: shop.currencyCode?.uppercased(),
            unavailableMetrics: unavailable)
    }

    // MARK: - GraphQL

    /// Raised mid-walk so a partial total can still be reported with a note.
    ///
    /// Not a `ProviderFailure`, because the order walk has something useful to
    /// do with a throttle that nothing else does: report the pages it already
    /// has. Every path out of this adapter has to turn one into a
    /// `.rateLimited` before it leaves — see `unthrottled`.
    struct Throttled: Error {
        let retryAfterSeconds: TimeInterval
    }

    /// A `Throttled` nobody caught is still a rate limit, not a crash.
    ///
    /// Wrapped at the two entry points rather than per metric: per metric it
    /// would be seven chances to forget, and a `Throttled` that escapes
    /// surfaces as "something went wrong" with the wait Shopify asked for
    /// thrown away.
    static func unthrottled<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let throttled as Throttled {
            throw ProviderFailure.rateLimited(
                "Shopify is rate limiting this store", retryAfter: throttled.retryAfterSeconds)
        }
    }

    private struct GraphQLRequest: Encodable {
        let query: String
        let variables: Variables
    }

    /// Every variable any of this adapter's queries takes.
    ///
    /// One struct rather than a dictionary of `Any`, so a typo is a compile
    /// error. A nil field is omitted, which GraphQL reads as the null a
    /// nullable variable defaults to — and the first page's cursor is exactly
    /// that.
    struct Variables: Encodable {
        var first: Int?
        var after: String?
        var query: String?
    }

    private struct GraphQLBody<T: Decodable>: Decodable {
        let data: T?
        let errors: Errors?
        let extensions: Extensions?

        struct Extensions: Decodable {
            let cost: Cost?
        }
    }

    /// The cost block Shopify attaches to every GraphQL answer.
    ///
    /// Points per second, not requests: it reports what the query cost and
    /// what is left of the bucket, which is what makes the backoff below
    /// arithmetic rather than a guess.
    struct Cost: Decodable {
        let requestedQueryCost: Double?
        let throttleStatus: ThrottleStatus?

        struct ThrottleStatus: Decodable {
            let currentlyAvailable: Double?
            let restoreRate: Double?
        }
    }

    /// Shopify's `errors` is an array of objects, except when the request never
    /// reached the GraphQL layer at all — then it is a bare string.
    ///
    /// Decoded as either rather than as the array alone, because a decode
    /// failure here would replace a sentence naming the problem with "the
    /// response could not be read".
    enum Errors: Decodable {
        case text(String)
        case list([GraphQLError])

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
            } else {
                self = .list(try container.decode([GraphQLError].self))
            }
        }

        var list: [GraphQLError] {
            switch self {
            case .text: return []
            case .list(let errors): return errors
            }
        }
    }

    struct GraphQLError: Decodable {
        let message: String?
        let extensions: Extensions?

        struct Extensions: Decodable {
            let code: String?
        }
    }

    /// One POST, one error taxonomy.
    ///
    /// `tolerateErrors` is for `verify` alone: a token with one of the two
    /// scopes answers with the data it can see *and* an ACCESS_DENIED for the
    /// rest, and rejecting that would refuse a connection that works.
    /// Everywhere else an error is an error.
    func graphql<T: Decodable>(
        _ type: T.Type, _ credentials: Credentials, query: String,
        variables: Variables = Variables(), tolerateErrors: Bool = false, http: ProviderHTTP
    ) async throws -> T {
        let payload: Data
        do {
            payload = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))
        } catch {
            throw ProviderFailure.badResponse("Could not build a Shopify query.")
        }

        let response = try await http.send(
            credentials.endpoint, method: "POST",
            headers: [
                "x-shopify-access-token": credentials.accessToken,
                "content-type": "application/json",
                "accept": "application/json",
            ],
            body: payload)

        guard response.ok else {
            throw Self.failure(for: response, shop: credentials.shopDomain)
        }

        let body: GraphQLBody<T>
        do {
            body = try JSONDecoder().decode(GraphQLBody<T>.self, from: response.body)
        } catch {
            throw ProviderFailure.badResponse(
                "\(credentials.shopDomain) answered with something this build cannot read.")
        }

        if case .text(let text) = body.errors {
            throw ProviderFailure.badResponse("\(credentials.shopDomain): \(text)")
        }
        let errors = body.errors?.list ?? []

        for error in errors {
            let code = error.extensions?.code
            // A throttle and a too-expensive query are thrown even when
            // errors are tolerated: neither leaves usable data behind, and
            // `verify` reporting "no scopes" for a throttled store would send
            // the user to rebuild a perfectly good app.
            if code == "THROTTLED" {
                throw Throttled(retryAfterSeconds: Self.retryAfter(body.extensions?.cost))
            }
            if code == "MAX_COST_EXCEEDED" {
                throw ProviderFailure.unsupported(
                    "Shopify refused the query as too large to run.")
            }
            let message = error.message ?? ""
            if code == "ACCESS_DENIED" || message.lowercased().contains("access denied") {
                // The message names the scope — "Required access:
                // `read_orders`" — and that sentence is the whole fix, so it
                // is passed through rather than flattened into "rejected the
                // credentials".
                if !tolerateErrors {
                    throw ProviderFailure.authFailed(
                        message.isEmpty ? "\(credentials.shopDomain) denied access." : message)
                }
            }
        }

        guard let data = body.data else {
            let first = errors.first?.message ?? "no data"
            throw ProviderFailure.badResponse("\(credentials.shopDomain): \(first)")
        }

        if !errors.isEmpty && !tolerateErrors {
            throw ProviderFailure.badResponse(
                "\(credentials.shopDomain): \(errors[0].message ?? "no data")")
        }

        return data
    }

    /// How long Shopify's own bucket needs to refill enough for the query we
    /// just tried.
    ///
    /// Shopify's budget is points per second rather than requests, and it
    /// reports both the cost and what is left — so the wait is arithmetic
    /// rather than a guess, and a throttled store backs off by the right
    /// amount. Clamped to a minute, because the caller is a menu-bar refresh
    /// loop and nothing in a notch is worth a longer hold than that.
    static func retryAfter(_ cost: Cost?) -> TimeInterval {
        let needed = cost?.requestedQueryCost ?? 0
        let available = cost?.throttleStatus?.currentlyAvailable ?? 0
        let restoreRate = cost?.throttleStatus?.restoreRate ?? 50
        let seconds = ((needed - available) / max(1, restoreRate)).rounded(.up)
        guard seconds.isFinite else { return 2 }
        return min(60, max(1, seconds))
    }

    // MARK: - Failures

    /// Shopify's status codes, in the buckets the caller acts differently on.
    ///
    /// The first three are the ones the generic mapping gets wrong. 402 is a
    /// store whose Shopify bill is unpaid or whose plan excludes the API and
    /// 423 is one Shopify has locked: both read as "rejected the credentials"
    /// through the generic mapping, which sends the user looking for a key
    /// problem they do not have. A 404 is the one case that really is the
    /// credential — the domain is wrong, or the app is no longer installed.
    static func failure(for response: ProviderHTTP.Response, shop: String) -> ProviderFailure {
        switch response.status {
        case 402:
            return .unsupported("\(shop) is frozen or on a plan without Admin API access.")
        case 423:
            return .unsupported("\(shop) is locked.")
        case 404:
            return .authFailed(
                "\(shop) does not exist, or the app has been uninstalled from it.")
        default:
            break
        }

        // A 5xx body is usually an HTML error page and a 429 is fully
        // described by its status plus the wait, so neither gets the body
        // attached. The same split as `errorForResponse` in the Worker.
        let detail = message(in: response.body)
        func explained(_ base: String) -> String {
            guard let detail else { return base }
            return "\(base): \(detail)"
        }

        switch response.status {
        case 401, 403:
            // The status is part of the message on purpose: a 403 from a host
            // that normally says 401 is how a WAF in front of Shopify shows
            // up, and that is a different afternoon from a revoked token.
            return .authFailed(explained("\(shop) rejected the credentials (\(response.status))"))
        case 429:
            let retry = response.header("retry-after").flatMap(TimeInterval.init) ?? 60
            return .rateLimited("\(shop) asked us to wait", retryAfter: retry)
        case 500...599:
            return .providerDown("\(shop) returned \(response.status)")
        default:
            // The body almost always names the wrong part of the request.
            // Throwing it away leaves "returned 400" on screen and the cause
            // to be guessed from outside the system.
            return .badResponse(explained("\(shop) returned \(response.status)"))
        }
    }

    /// One sentence per element, each keeping the punctuation that ended it.
    ///
    /// The Worker splits on `/(?<=[.!?])\s+/`, and Swift's regex engine has no
    /// lookbehind — so this is that split written out. Dropping the
    /// terminator instead would turn "Required access: read_orders." into a
    /// fragment, which is the half of the message that is worth keeping.
    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            current.append(character)
            index += 1
            guard ".!?".contains(character) else { continue }
            // A terminator only ends a sentence when whitespace follows it,
            // or every decimal point and every "e.g." becomes a break.
            var next = index
            while next < characters.count, characters[next].isWhitespace { next += 1 }
            if next > index {
                result.append(current)
                current = ""
                index = next
            }
        }

        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Shopify's own explanation, when it sent one.
    ///
    /// `errors` is the shape that matters and it arrives both ways — a string
    /// from the REST-era auth layer, an array of objects from GraphQL — so
    /// both are read. The other keys are the Worker's `providerMessage` order,
    /// kept because Shopify's gateway and its OAuth routes answer in them.
    ///
    /// Anything unrecognised is dropped rather than pasted in raw: an HTML
    /// page in a notch tile is worse than the bare status it replaces.
    static func message(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }

        var candidates: [Any?] = []
        if let nested = object["error"] as? [String: Any] {
            candidates.append(nested["message"])
        } else {
            candidates.append(object["error"])
        }
        candidates.append(object["message"])
        candidates.append(object["detail"])
        candidates.append(object["error_description"])
        if let list = object["errors"] as? [Any] {
            let joined = list.compactMap { entry -> String? in
                if let text = entry as? String { return text }
                return (entry as? [String: Any])?["message"] as? String
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
            candidates.append(joined.isEmpty ? nil : joined)
        } else {
            candidates.append(object["errors"])
        }

        guard let raw = candidates.compactMap({ $0 as? String })
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { return nil }

        // Any token Shopify quoted back at us goes before this reaches a
        // screen, and from there a screenshot in a support thread.
        let redacted = raw.replacing(/shp(at|ca)_[A-Za-z0-9]+/, with: "shpat_…")

        // Whole sentences go, rather than the URL being cut out of them.
        // Shopify appends admin deep links that run to a couple of hundred
        // characters, and removing just the link leaves "You can fix this at ."
        // behind. Where to click is `setupSteps`' job to say.
        let cleaned = sentences(redacted.replacing(/\s+/, with: " "))
            .filter { !$0.lowercased().contains("http://") && !$0.lowercased().contains("https://") }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return nil }

        // Bounded, but generously: 200 cut a permission message off before
        // the part that named the permission.
        return cleaned.count > 400 ? String(cleaned.prefix(397)) + "..." : cleaned
    }
}
