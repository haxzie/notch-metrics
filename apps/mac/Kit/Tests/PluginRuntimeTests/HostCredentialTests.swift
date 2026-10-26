import Foundation
import MetricsCore
import Testing

@testable import PluginRuntime

/// Credentials the app holds and hands to a connector that asked for one.
///
/// This is the one place a custom app receives something the user never typed,
/// so the rules it has to keep are narrow and worth pinning: only what the
/// manifest names, nothing this build cannot supply, and a usable reason on
/// every way it can fail.
struct HostCredentialTests {
    static func manifest(hostCredentials: [String]?) throws -> ConnectorManifest {
        var object: [String: Any] = [
            "schemaVersion": 1, "id": "claude-usage", "name": "Claude usage",
            "description": "d", "appId": "custom", "authMode": "none", "auth": [],
            "allowedHosts": ["api.anthropic.com"],
            "metrics": [
                [
                    "id": "session_used", "label": "Session", "shortLabel": "Session",
                    "unit": "ratio", "shape": ["kind": "scalar"], "methodology": "m",
                ]
            ],
            "refreshIntervalSeconds": 300, "timeoutMs": 8000, "entry": "connector.mjs",
            "createdAt": "2026-10-25T00:00:00.000Z", "updatedAt": "2026-10-25T00:00:00.000Z",
        ]
        if let hostCredentials { object["hostCredentials"] = hostCredentials }
        return try JSONDecoder().decode(
            ConnectorManifest.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test("an app that names one gets it")
    func declared() throws {
        let manifest = try Self.manifest(hostCredentials: ["claude_code_oauth"])
        #expect(manifest.supportedHostCredentials == [.claudeCodeOAuth])
        // Still asks the user for nothing: a host credential is not an
        // `auth` field and must not make the Settings row show an empty form.
        #expect(manifest.requiresCredentials == false)
    }

    @Test("an app that names none gets none")
    func undeclared() throws {
        #expect(try Self.manifest(hostCredentials: []).supportedHostCredentials.isEmpty)
        // Absent entirely, as in every manifest written before the field
        // existed. Must decode, and must receive nothing.
        #expect(try Self.manifest(hostCredentials: nil).supportedHostCredentials.isEmpty)
    }

    @Test("a credential this build cannot supply is dropped, not refused")
    func unknownIsDropped() throws {
        // Forward compatibility in the safe direction: the manifest still
        // loads, so the app's other metrics keep working, but nothing is
        // handed over — this build has no idea where that token lives.
        let manifest = try Self.manifest(hostCredentials: ["some_future_token"])
        #expect(manifest.hostCredentials == [.unknown])
        #expect(manifest.supportedHostCredentials.isEmpty)
    }

    @Test("a credential is named in words the user recognises")
    func displayName() {
        // Rendered in the Settings row before the app is enabled, so it has to
        // read as the thing being handed over, not as a manifest key.
        #expect(HostCredential.claudeCodeOAuth.displayName == "your Claude Code sign-in")
    }

    @Test("every unusable outcome gives the tile something to say")
    func outcomesExplainThemselves() {
        // A tile with no reason is a tile nobody can act on, and each reason
        // names a different remedy: sign in, open Claude Code, sign in again.
        #expect(HostCredentials.Outcome.value("t").tileReason == nil)
        #expect(HostCredentials.Outcome.missing.tileReason == "Sign in to Claude Code")
        #expect(
            HostCredentials.Outcome.stale(since: Date()).tileReason
                == "Open Claude Code to refresh")
        #expect(
            HostCredentials.Outcome.expired(since: Date()).tileReason
                == "Claude Code sign-in expired")
        #expect(HostCredentials.Outcome.unreadable("x").tileReason == "Credential unreadable")
    }

    @Test("an unknown credential resolves to missing rather than crashing")
    func unknownLookupIsMissing() {
        #expect(HostCredentials.lookup(.unknown) == .missing)
    }

    /// The outcome's date, within a millisecond of the expected one.
    ///
    /// Not `==`. The blob stores whole milliseconds, so a `Date` survives the
    /// round trip only to that precision while `Date` equality is exact — an
    /// assertion on the nose fails against a value that prints identically,
    /// which is a test failing for a reason that is not the code's.
    static func matches(_ outcome: HostCredentials.Outcome, expired expected: Date) -> Bool {
        guard case let .expired(since) = outcome else { return false }
        return abs(since.timeIntervalSince(expected)) < 0.001
    }

    static func matches(_ outcome: HostCredentials.Outcome, stale expected: Date) -> Bool {
        guard case let .stale(since) = outcome else { return false }
        return abs(since.timeIntervalSince(expected)) < 0.001
    }

    static func blob(access: Date?, refresh: Date?, token: String = "sk-ant-oat01-x") -> Data {
        var account: [String: Any] = ["accessToken": token]
        if let access { account["expiresAt"] = access.timeIntervalSince1970 * 1000 }
        if let refresh { account["refreshTokenExpiresAt"] = refresh.timeIntervalSince1970 * 1000 }
        return try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": account])
    }

    @Test("a live token is handed over")
    func liveToken() {
        let now = Date()
        #expect(
            HostCredentials.interpret(
                blob: Self.blob(
                    access: now.addingTimeInterval(3600),
                    refresh: now.addingTimeInterval(86400)), now: now)
                == .value("sk-ant-oat01-x"))
    }

    @Test("a stale access token is not a sign-out")
    func staleIsNotExpired() {
        // The bug this split exists for. A Claude Code access token lasts
        // about eight hours and is refreshed lazily, when the owning app next
        // makes a request — so there is a window where the stored token is
        // past its expiry and the user is signed in perfectly well. Calling
        // that "expired" sent people off to re-auth an account nobody had
        // signed out of.
        let now = Date()
        let access = now.addingTimeInterval(-60)
        #expect(
            Self.matches(
                HostCredentials.interpret(
                    blob: Self.blob(access: access, refresh: now.addingTimeInterval(86400)),
                    now: now),
                stale: access))
    }

    @Test("a dead refresh token is a sign-out")
    func refreshExpiryIsTheRealOne() {
        // The refresh token is what actually says whether the user is signed
        // in. Once it is gone, nothing short of signing in again helps.
        let now = Date()
        let access = now.addingTimeInterval(-86400)
        #expect(
            Self.matches(
                HostCredentials.interpret(
                    blob: Self.blob(access: access, refresh: now.addingTimeInterval(-3600)),
                    now: now),
                expired: access))

        // Absent entirely: read as a sign-out, which is the conservative way
        // round — it names a remedy that always works.
        #expect(
            Self.matches(
                HostCredentials.interpret(
                    blob: Self.blob(access: access, refresh: nil), now: now),
                expired: access))
    }

    @Test("a blob with no expiry at all is still usable")
    func noExpiryIsNotAFailure() {
        // Forward compatibility: a format change that drops or renames the
        // field must not blank a working tile. The API is the backstop — it
        // rejects a token this app wrongly believed in.
        let now = Date()
        #expect(
            HostCredentials.interpret(blob: Self.blob(access: nil, refresh: nil), now: now)
                == .value("sk-ant-oat01-x"))
    }

    @Test("a blob in an unfamiliar shape says so rather than reading as signed out")
    func unreadableBlob() {
        let now = Date()
        guard
            case .unreadable = HostCredentials.interpret(
                blob: Data("{\"something\":1}".utf8), now: now)
        else {
            Issue.record("expected unreadable")
            return
        }
        // An empty token is a sign-in that never completed, not a bad format.
        #expect(
            HostCredentials.interpret(
                blob: Self.blob(access: nil, refresh: nil, token: ""), now: now) == .missing)
    }
}
