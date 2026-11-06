import Foundation
import MetricsCore

/// npm, read from this Mac.
///
/// Ported from `packages/integrations/src/providers/npm`. Two hosts, and they
/// are genuinely different services: the registry holds packages and
/// identities and takes the token, the statistics API holds download counts
/// and takes no credential at all.
public struct NpmProvider: LocalProvider {
    public let id = "npm"
    /// One host. npm publishes download counts to anyone who asks, so the
    /// registry is never reached: there is no identity to look up.
    public let allowedHosts = ["api.npmjs.org"]

    static let stats = "https://api.npmjs.org"

    public init() {}

    /// Nothing to prove.
    ///
    /// There is no credential, and no package either — that is a widget's
    /// parameter — so there is nothing a connect-time check could ask npm
    /// about. A widget pointed at a package that does not exist says so on
    /// the tile, which is where the package was named.
    ///
    /// This asked for an access token at first, purely so it could call
    /// `/-/whoami` and name the connection. npm charges a trip through 2FA
    /// for that, which is a poor price for a label, and a credential with no
    /// use is one that can leak for no reason.
    public func verify(
        _ credentials: [String: String], http: ProviderHTTP
    ) async throws -> ProviderAccount {
        ProviderAccount(label: "npm", currency: nil)
    }

    /// npm's statuses, in the buckets the caller acts differently on.
    static func failure(for response: ProviderHTTP.Response, subject: String) -> ProviderFailure {
        switch response.status {
        case 401, 403:
            // Should not happen: nothing here sends a credential. Kept
            // because npm's edge answers 403 to a blocked client, and
            // reporting that as a bad response would send somebody looking
            // for a key they never entered.
            return .providerDown("npm refused the request.")
        case 404:
            // A package that never existed, one that was unpublished, and a
            // private one this token cannot see all answer the same 404. The
            // message covers all three because the status cannot tell them
            // apart, and none of them is a reason to mark the connection
            // broken: the same token answers every other tile.
            return .unsupported(
                "That package could not be read. Check the name, and that this token can see it.")
        case 429:
            let retry = response.header("retry-after").flatMap(TimeInterval.init)
            return .rateLimited("npm asked us to wait.", retryAfter: retry ?? 60)
        case 500...599:
            return .providerDown("\(subject) is having trouble.")
        default:
            return .badResponse("\(subject) returned \(response.status).")
        }
    }
}
