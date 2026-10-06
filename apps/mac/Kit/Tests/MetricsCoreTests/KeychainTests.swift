import Foundation
import Security
import Testing

@testable import MetricsCore

/// Exercises the **real** Keychain, not the in-memory double.
///
/// The double cannot catch the failure that mattered: with
/// `kSecUseDataProtectionKeychain` set, every write returned -34018
/// (errSecMissingEntitlement), because that keychain needs an entitlement a
/// non-sandboxed Developer ID app does not have. Sign-in dropped its token
/// every single time and the only symptom was a button that stayed on
/// "Sign in".
///
/// Skipped where there is no keychain to talk to, which is CI.
/// Is there a usable keychain on this machine at all?
///
/// Probed with `Security` directly rather than through `KeychainSecretStore`.
/// Using the code under test would mean any breakage in it reads as "no
/// keychain here" and the whole suite skips — which is precisely what
/// happened, and precisely the bug these tests exist to catch.
///
/// Declared outside the suite: a condition referencing the suite's own type
/// is a circular macro reference.
private let keychainAvailable: Bool = {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.notchmetrics.app.availability",
        kSecAttrAccount as String: "probe",
    ]
    SecItemDelete(query as CFDictionary)
    var add = query
    add[kSecValueData as String] = Data("probe".utf8)
    let status = SecItemAdd(add as CFDictionary, nil)
    SecItemDelete(query as CFDictionary)
    return status == errSecSuccess
}()

@Suite(.enabled(if: keychainAvailable))
struct KeychainTests {
    private func store() -> (KeychainSecretStore, SecretKey) {
        (
            KeychainSecretStore(service: "com.notchmetrics.app.tests.\(UUID().uuidString)"),
            SecretKey(account: "auth.deviceToken")
        )
    }

    @Test("a written secret reads back")
    func roundTrips() throws {
        let (keychain, key) = store()
        defer { try? keychain.set(nil, for: key) }

        try keychain.set("a-device-token", for: key)
        #expect(try keychain.string(for: key) == "a-device-token")
    }

    @Test("writing twice overwrites rather than failing as a duplicate")
    func overwrites() throws {
        let (keychain, key) = store()
        defer { try? keychain.set(nil, for: key) }

        try keychain.set("first", for: key)
        try keychain.set("second", for: key)
        #expect(try keychain.string(for: key) == "second")
    }

    @Test("a missing secret is nil, not an error")
    func missingIsNil() throws {
        let (keychain, key) = store()
        #expect(try keychain.string(for: key) == nil)
    }

    @Test("clearing removes it")
    func clears() throws {
        let (keychain, key) = store()
        try keychain.set("a-device-token", for: key)
        try keychain.set(nil, for: key)
        #expect(try keychain.string(for: key) == nil)
    }
}
