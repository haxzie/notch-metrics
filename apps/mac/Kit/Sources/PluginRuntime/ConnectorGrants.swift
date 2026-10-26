import Foundation
import MetricsCore

/// What enabling a custom app actually hands it.
///
/// This exists because the previous gate asked an unanswerable question. It
/// recorded a SHA over the manifest and the code, so *any* rewrite came back
/// as `.modified` with a "Review" button — and a button is not a diff. Editing
/// an app's `icon`, bumping its `version` or raising its `timeoutMs` revoked
/// its approval and demanded a decision the user had no way to make except by
/// clicking yes. Six of those in one afternoon teaches the habit of clicking
/// yes, which is precisely the habit that makes the seventh dangerous.
///
/// So the gate moved from *contents* to *grants*. Three things widen what an
/// app can do, and all three are one line of readable text:
///
/// - `allowedHosts` — where its `fetch` may go.
/// - `hostCredentials` — a token the **app** reads out of the Keychain on the
///   connector's behalf. This is the real escalation: connector code could not
///   obtain the Claude Code OAuth token itself without raising a Keychain
///   prompt, and the injection is what spares it one.
/// - `auth` — the keys whose stored secrets get passed in.
///
/// A rewrite that leaves all three alone grants nothing new, so it runs. A
/// rewrite that adds to any of them asks again, and can say what it is asking
/// for. Note the asymmetry: approval is checked as a **superset**, so dropping
/// a host or a credential is not a change worth interrupting anyone over.
///
/// What this deliberately does *not* claim: that unchanged grants make new
/// code safe. Containment here is not a sandbox — `node:fs` is unrestricted —
/// so an app rewritten in place can read anything its user can. The defence
/// against that is that whoever wrote the file could have read those files
/// directly anyway; what they could not have done is mint a Keychain token,
/// which is why `hostCredentials` is in this set and `entry`'s bytes are not.
public struct ConnectorGrants: Sendable, Equatable {
    public let hosts: Set<String>
    public let hostCredentials: Set<String>
    public let secrets: Set<String>

    /// Tags the stored string so a value written by an older build — a bare
    /// SHA-256 — is recognisable as one rather than parsed into empty grants,
    /// which would read as "this app asked for nothing" and approve anything.
    static let marker = "g1"

    public init(hosts: Set<String>, hostCredentials: Set<String>, secrets: Set<String>) {
        self.hosts = hosts
        self.hostCredentials = hostCredentials
        self.secrets = secrets
    }

    public init(manifest: ConnectorManifest) {
        // Hosts lowercased because DNS is case-insensitive and
        // `API.Anthropic.com` is not a new grant.
        hosts = Set(manifest.allowedHosts.map { $0.lowercased() })
        // `.unknown` is dropped rather than recorded. The app never
        // supplies a credential it cannot fetch, so an unfamiliar one
        // grants nothing and must not be the reason a row asks again.
        hostCredentials = Set(manifest.supportedHostCredentials.map(\.rawValue))
        secrets = Set(manifest.auth.map(\.key))
    }

    /// Nothing granted. The baseline `additions(over:)` is diffed against to
    /// describe an app's grants in full rather than as a change.
    public static let none = ConnectorGrants(hosts: [], hostCredentials: [], secrets: [])

    /// Everything this app may do, phrased as `additions` phrases a change.
    public var summary: [String] { additions(over: .none) }

    /// True when nothing is handed over that the writer of the file did not
    /// already have. Used for the one legacy case below.
    public var isBare: Bool { hostCredentials.isEmpty && secrets.isEmpty }

    /// Everything this app asks for, in a fixed order, as one string.
    ///
    /// Stored rather than hashed. A hash would answer "did this change?"; the
    /// list also answers "into what?", which is what the row has to say out
    /// loud for the prompt to be worth showing at all.
    public var canonical: String {
        func list(_ values: Set<String>) -> String {
            values.sorted().joined(separator: ",")
        }
        return [
            Self.marker,
            "hosts:" + list(hosts),
            "cred:" + list(hostCredentials),
            "auth:" + list(secrets),
        ].joined(separator: "|")
    }

    /// Reads back what was approved, or nil if the stored value predates this
    /// format.
    public static func parse(_ stored: String) -> ConnectorGrants? {
        let parts = stored.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.first.map(String.init) == marker else { return nil }

        func field(_ prefix: String) -> Set<String> {
            guard let part = parts.first(where: { $0.hasPrefix(prefix + ":") }) else { return [] }
            return Set(
                part.dropFirst(prefix.count + 1)
                    .split(separator: ",")
                    .map(String.init)
                    .filter { !$0.isEmpty })
        }
        return ConnectorGrants(
            hosts: field("hosts"), hostCredentials: field("cred"), secrets: field("auth"))
    }

    /// Whether a yes given to `approved` already covers this.
    public func isCovered(by approved: ConnectorGrants) -> Bool {
        hosts.isSubset(of: approved.hosts)
            && hostCredentials.isSubset(of: approved.hostCredentials)
            && secrets.isSubset(of: approved.secrets)
    }

    /// What is newly asked for, as a sentence the row can show.
    ///
    /// The point of the whole exercise: "this app has changed" is not a
    /// question anyone can answer, where "it now wants your Claude Code
    /// sign-in" is.
    public func additions(over approved: ConnectorGrants) -> [String] {
        var lines: [String] = []

        let newHosts = hosts.subtracting(approved.hosts).sorted()
        if !newHosts.isEmpty {
            lines.append("reach " + newHosts.joined(separator: ", "))
        }

        let newCredentials = hostCredentials.subtracting(approved.hostCredentials)
            .map { HostCredential(rawValue: $0)?.displayName ?? $0 }
            .sorted()
        if !newCredentials.isEmpty {
            lines.append("use " + newCredentials.joined(separator: ", "))
        }

        let newSecrets = secrets.subtracting(approved.secrets).sorted()
        if !newSecrets.isEmpty {
            lines.append("ask you for " + newSecrets.joined(separator: ", "))
        }
        return lines
    }
}
