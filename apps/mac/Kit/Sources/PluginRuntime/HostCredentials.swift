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
        if let cached = cache.value(for: credential, now: now) { return cached }

        let read: (outcome: Outcome, goodUntil: Date?) =
            switch credential {
            case .claudeCodeOAuth: claudeCodeToken(now: now)
            case .unknown: (.missing, nil)
            }
        cache.store(read.outcome, goodUntil: read.goodUntil, for: credential, now: now)
        return read.outcome
    }

    /// Clears what is remembered, so the next lookup reads the Keychain.
    ///
    /// For the moment a user has gone and signed in to the other app and
    /// wants the tile to notice without relaunching.
    public static func forget() { cache.clear() }

    private static let cache = CredentialCache()
}

/// What was last read, so a refresh is not a Keychain hit.
///
/// macOS prompts for a password when an application reads a Keychain item
/// another application created, and keeps prompting until the user grants
/// "Always Allow" to that exact binary. Reading Claude Code's item is
/// therefore a prompt, by design and correctly — but `lookup` was called
/// twice per connector refresh, once to decide whether the tile should say
/// anything and once to build the credentials for the run. A user who had
/// not granted the standing permission got two dialogs every refresh.
///
/// So the answer is held for as long as it is good for. A live token is kept
/// until its own expiry, which is the moment it stops being usable anyway. A
/// failure is kept for a minute: long enough that one refusal does not
/// become a dialog a second later, short enough that signing in to the other
/// app is noticed without relaunching this one.
///
/// Memory only. Nothing here is written anywhere, which is the whole reason
/// the token is read from the owning app's Keychain in the first place.
final class CredentialCache: @unchecked Sendable {
    private struct Entry {
        let outcome: HostCredentials.Outcome
        let until: Date
    }

    private let lock = NSLock()
    private var entries: [HostCredential: Entry] = [:]

    /// Long enough to cover a run; short enough to notice a sign-in.
    private static let failureTTL: TimeInterval = 60

    func value(for credential: HostCredential, now: Date) -> HostCredentials.Outcome? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[credential], entry.until > now else { return nil }
        return entry.outcome
    }

    /// `goodUntil` comes from the same read that produced the outcome.
    ///
    /// It has to. Looking the expiry up separately would be a second Keychain
    /// hit and therefore a second password prompt, which is the thing this
    /// cache exists to stop — the first version of it did exactly that.
    func store(
        _ outcome: HostCredentials.Outcome, goodUntil: Date?, for credential: HostCredential,
        now: Date
    ) {
        let until: Date
        switch outcome {
        case .value:
            // Until the token itself expires. A blob that names no expiry
            // gets five minutes: long enough to stop a refresh prompting,
            // short enough that a rotation is picked up.
            until = goodUntil ?? now.addingTimeInterval(300)
        case .missing, .stale, .expired, .unreadable:
            until = now.addingTimeInterval(Self.failureTTL)
        }

        lock.lock()
        entries[credential] = Entry(outcome: outcome, until: until)
        lock.unlock()
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}

extension HostCredentials {

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
    static func claudeCodeToken(now: Date = Date()) -> (outcome: Outcome, goodUntil: Date?) {
        guard let data = keychainValue(service: claudeCodeService) else { return (.missing, nil) }
        return (interpret(blob: data, now: now), accessExpiry(in: data))
    }

    /// When the access token in this blob stops being usable.
    ///
    /// Parsed from the bytes already in hand rather than read again: a second
    /// `SecItemCopyMatching` is a second password prompt.
    static func accessExpiry(in data: Data) -> Date? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let account = root["claudeAiOauth"] as? [String: Any],
            let millis = account["expiresAt"] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
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
