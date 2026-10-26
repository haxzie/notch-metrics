import Foundation
import MetricsCore

/// Credentials the app already has, for connectors that declare they want one.
///
/// Everything here reads something **another** application stores. That is the
/// whole point and also the whole risk, so two rules hold:
///
/// - A connector gets a host credential only by naming it in its manifest, and
///   the Settings row shows which — the user can see that an app receives
///   their Claude Code token before they enable it.
/// - Nothing here is written, refreshed or rotated. A token that has expired
///   is reported as missing and the tile says so; silently refreshing someone
///   else's OAuth session would invalidate the token the owning app is using
///   and sign them out of it.
public enum HostCredentials {
    /// What a lookup produced.
    public enum Outcome: Sendable, Equatable {
        case value(String)
        /// Nothing stored — the user is not signed in to that app.
        case missing
        /// The access token is past its expiry, but the refresh token is not.
        ///
        /// The common case, and emphatically **not** a sign-out: a Claude Code
        /// access token lasts about eight hours and is refreshed lazily, when
        /// the owning app next makes a request. Between the two there is a
        /// window — minutes if Claude Code is in use, longer if it is not —
        /// where the stored token is stale and the user is still perfectly
        /// signed in. Reporting that as "expired" sent people off to re-auth
        /// an account that was never signed out.
        case stale(since: Date)
        /// The refresh token itself is past its expiry. This one really is a
        /// sign-out, and the remedy really is to sign in again.
        case expired(since: Date)
        /// The item exists and could not be read or parsed.
        case unreadable(String)
    }

    public static func lookup(_ credential: HostCredential, now: Date = Date()) -> Outcome {
        switch credential {
        case .claudeCodeOAuth: claudeCodeToken(now: now)
        case .unknown: .missing
        }
    }

    /// The Claude Code subscription OAuth token.
    ///
    /// Stored by Claude Code as one generic-password item whose value is a
    /// JSON blob; the account token lives under `claudeAiOauth`. Read rather
    /// than any `ANTHROPIC_API_KEY`, because on a subscription there is no API
    /// key — the usage endpoint takes this OAuth token and nothing else.
    ///
    /// macOS will prompt the first time this app reads an item another
    /// application created. That prompt is correct and worth it: it is the
    /// user being told, by the system, that Notch Metrics wants their Claude
    /// Code credential.
    static func claudeCodeToken(now: Date = Date()) -> Outcome {
        guard let data = keychainValue(service: claudeCodeService) else { return .missing }
        return interpret(blob: data, now: now)
    }

    /// The stored blob as an outcome, with no Keychain in the way.
    ///
    /// Split out so the expiry rules are testable. Reaching the Keychain from
    /// a test means either an item that is not there on CI or a prompt no
    /// runner can answer, and these two dates are the whole of the logic.
    static func interpret(blob data: Data, now: Date) -> Outcome {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let account = root["claudeAiOauth"] as? [String: Any]
        else {
            return .unreadable("The Claude Code credential is not in a shape this build knows.")
        }

        guard let token = account["accessToken"] as? String, !token.isEmpty else {
            return .missing
        }

        // Milliseconds since the epoch, as Claude Code stores it. Treated as
        // "no expiry known" rather than "expired" when absent, so a format
        // change cannot blank a working tile.
        func expiry(_ key: String) -> Date? {
            (account[key] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        }

        guard let access = expiry("expiresAt"), access <= now else { return .value(token) }

        // Which of the two expiries has run out decides what the user is
        // told, because the remedies are opposite: one is "wait, or open
        // Claude Code", the other is "sign in again". An absent refresh
        // expiry is read as a sign-out, which is the conservative way round —
        // it names a remedy that always works.
        guard let refresh = expiry("refreshTokenExpiresAt"), refresh > now else {
            return .expired(since: access)
        }
        return .stale(since: access)
    }

    static let claudeCodeService = "Claude Code-credentials"

    /// Reads one generic-password item's value.
    ///
    /// No account is specified: the item is identified by service alone, which
    /// is how the owning application wrote it.
    private static func keychainValue(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
}

extension HostCredentials.Outcome {
    /// What a tile says when the credential is not usable. Nil when it is.
    public var tileReason: String? {
        switch self {
        case .value: nil
        case .missing: "Sign in to Claude Code"
        // Names the remedy rather than the diagnosis. Claude Code mints a new
        // token the next time it is used, and nothing this app can do brings
        // that forward — refreshing the session ourselves would invalidate
        // the token Claude Code is holding and sign the user out of it.
        case .stale: "Open Claude Code to refresh"
        case .expired: "Claude Code sign-in expired"
        case .unreadable: "Credential unreadable"
        }
    }
}
