import Foundation

/// What a connector answers when its credentials are checked.
public struct ProviderAccount: Sendable, Equatable {
    /// What to call the connection in the UI: a business name, a login, an
    /// account id as a last resort.
    public let label: String
    /// ISO 4217, upper case, or nil for a connector that is not about money.
    public let currency: String?
    /// Metrics this particular credential cannot answer.
    ///
    /// A restricted Stripe key reads charges but not subscriptions. Narrowing
    /// what is offered beats refusing a connection and telling somebody their
    /// perfectly good key is broken.
    public let unavailableMetrics: [String]

    public init(label: String, currency: String? = nil, unavailableMetrics: [String] = []) {
        self.label = label
        self.currency = currency
        self.unavailableMetrics = unavailableMetrics
    }
}

/// Why a provider call failed, in the five buckets the caller acts differently on.
///
/// The same vocabulary as `ProviderError` in `packages/integrations`, and
/// deliberately so: these adapters are being ported from those, the error
/// handling is the part most easily lost in a rewrite, and a shared set of
/// names makes the two readable side by side while both exist.
public enum ProviderFailure: Error, Sendable, Equatable {
    /// The credential is wrong, revoked, or lacks the scope. Stops polling and
    /// asks the user to fix it.
    case authFailed(String)
    /// Quota spent. `retryAfter` is seconds when the provider said.
    case rateLimited(String, retryAfter: TimeInterval?)
    /// Their outage, not ours. Retried on the next tick.
    case providerDown(String)
    /// A well-formed answer this adapter cannot read.
    case badResponse(String)
    /// A statement about *this request* rather than about the connection: a
    /// renamed repository, a metric the plan does not include.
    case unsupported(String)

    /// What to put in front of the user.
    public var message: String {
        switch self {
        case .authFailed(let m), .providerDown(let m), .badResponse(let m), .unsupported(let m):
            return m
        case .rateLimited(let m, _):
            return m
        }
    }
}

/// One external account the notch can read numbers from, running on this Mac.
///
/// The Worker's adapters are the reference implementation; see
/// `packages/integrations/src/providers/<id>`. The contract fixtures under
/// `contracts/` stay the shared definition of the wire shapes, which is what
/// keeps a port honest rather than merely plausible.
public protocol LocalProvider: Sendable {
    /// Matches the `ProviderId` the catalogue serves, so one table routes both.
    var id: String { get }

    /// How long one request to this provider may take, when eight seconds is
    /// the wrong answer for it.
    ///
    /// Defaulted, so an adapter that suits the usual REST read says nothing.
    /// PostHog is the reason it exists: every number there is a HogQL
    /// aggregate over the event table rather than a row read, and a
    /// ninety-day one measures five to nine and a half seconds. The default
    /// eight sits inside that spread, so the same widget timed out or
    /// answered depending on the day.
    var requestTimeout: TimeInterval { get }

    /// Every host this adapter may reach, as the manifest declares them.
    ///
    /// On the protocol rather than passed in at the call site, so there is no
    /// way to build a client for one provider with another's allowlist. That
    /// is not a theoretical slip: the caller is a view model holding several
    /// connectors, and an allowlist chosen there would be one argument away
    /// from letting a Stripe key be sent to whatever host a different
    /// adapter names.
    var allowedHosts: [String] { get }

    /// Proves the credentials work. Called before anything is stored.
    func verify(_ credentials: [String: String], http: ProviderHTTP) async throws -> ProviderAccount

    /// Answers one widget's question.
    ///
    /// Throwing `unsupported` for a metric this adapter does not implement is
    /// the contract, not a failure mode: the catalogue is served and lists
    /// every metric the *Worker* can answer, so a build partway through the
    /// port will be asked for ones it cannot do yet.
    func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue
}

extension LocalProvider {
    /// What suits a REST call that reads a row, and what the Worker's
    /// `createHttp` uses when an adapter declares nothing.
    public var requestTimeout: TimeInterval { ProviderHTTP.defaultTimeout }
}

/// Pulls a required credential out of the blob, or says which one is missing.
///
/// The form will not submit without a required field, so a gap here is a bug
/// rather than user error — but it reaches a request either way, and
/// `credentials["x"] ?? ""` sends an empty bearer token to a live API and
/// reads back as a revoked key.
public func requiredCredential(
    _ credentials: [String: String], _ key: String
) throws -> String {
    guard let value = credentials[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty
    else {
        throw ProviderFailure.authFailed("No \(key) was stored for this connection.")
    }
    return value
}
