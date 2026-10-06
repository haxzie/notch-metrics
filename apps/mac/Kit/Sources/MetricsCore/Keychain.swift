import Foundation
import Security

public struct SecretKey: Hashable, Sendable {
    public let account: String
    public init(account: String) { self.account = account }

    public static let refreshToken = SecretKey(account: "auth.refreshToken")
    public static let deviceToken = SecretKey(account: "auth.deviceToken")

    /// One item per (plugin, secret), so deleting a plugin can wipe by prefix.
    public static func plugin(_ id: String, _ name: String) -> SecretKey {
        SecretKey(account: "plugin.\(id).\(name)")
    }

    public static func pluginPrefix(_ id: String) -> String { "plugin.\(id)." }
}

public enum SecretStoreError: Error, Equatable {
    /// The signing identity changed, so the ACL no longer matches.
    ///
    /// This is not hypothetical and not rare: it happens the first time anybody
    /// moves between a locally ad-hoc-signed build and a Developer ID one on
    /// the same Mac. Surfaced as its own case so the UI can say "sign in
    /// again" instead of crashing on an opaque OSStatus.
    case identityChanged
    /// The write reported success but the value did not come back.
    case notPersisted
    case unexpected(OSStatus)
}

public protocol SecretStore: Sendable {
    func string(for key: SecretKey) throws -> String?
    func set(_ value: String?, for key: SecretKey) throws
    func deleteAll(matching prefix: String) throws
}

public struct KeychainSecretStore: SecretStore {
    private let service: String

    public init(service: String = AppPaths.bundleIdentifier) {
        self.service = service
    }

    private func query(_ key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account,
        ]
        // Deliberately *not* kSecUseDataProtectionKeychain.
        //
        // The data-protection keychain requires a keychain-access-group
        // entitlement, which comes from a provisioning profile. This app is
        // non-sandboxed Developer ID with no profile, so every write returned
        // -34018 (errSecMissingEntitlement) — meaning the Keychain never
        // worked at all, and sign-in silently dropped its token every time.
        //
        // Turning it back on requires adding the entitlement first; check
        // with a signed build, because an unsigned one fails the same way for
        // a different reason.
    }

    public func string(for key: SecretKey) throws -> String? {
        var request = query(key)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw mapped(status)
        }
    }

    public func set(_ value: String?, for key: SecretKey) throws {
        guard let value, let data = value.data(using: .utf8) else {
            let status = SecItemDelete(query(key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SecretStoreError.unexpected(status)
            }
            return
        }

        var insert = query(key)
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(insert as CFDictionary, nil)
        if status == errSecSuccess { return }

        if status == errSecDuplicateItem {
            let update = SecItemUpdate(
                query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if update == errSecSuccess { return }

            // An item left by a differently-signed build of this app. Its ACL
            // names the old identity, so it can be matched and deleted but not
            // updated — which is why the update fails rather than the add.
            //
            // Deleting and re-adding is safe for everything we keep here: a
            // device token and plugin secrets are all re-obtainable, and the
            // alternative is an app that can never sign in again on this Mac
            // without the user finding the item in Keychain Access.
            if isIdentityFailure(update) {
                SecItemDelete(query(key) as CFDictionary)
                let retry = SecItemAdd(insert as CFDictionary, nil)
                guard retry == errSecSuccess else { throw mapped(retry) }
                return
            }
            throw mapped(update)
        }

        throw mapped(status)
    }

    /// The statuses that mean "this item belongs to a different signature",
    /// rather than "something is wrong with the request".
    private func isIdentityFailure(_ status: OSStatus) -> Bool {
        status == errSecInteractionNotAllowed || status == errSecAuthFailed
            || status == errSecMissingEntitlement
    }

    private func mapped(_ status: OSStatus) -> SecretStoreError {
        isIdentityFailure(status) ? .identityChanged : .unexpected(status)
    }

    public func deleteAll(matching prefix: String) throws {
        var request: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        request[kSecReturnData as String] = false

        var items: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &items)
        guard status == errSecSuccess, let entries = items as? [[String: Any]] else { return }

        for entry in entries {
            guard let account = entry[kSecAttrAccount as String] as? String,
                  account.hasPrefix(prefix)
            else { continue }
            SecItemDelete(query(SecretKey(account: account)) as CFDictionary)
        }
    }
}

/// So Kit tests run in CI, which has no keychain and no login session.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func string(for key: SecretKey) throws -> String? {
        lock.withLock { storage[key.account] }
    }

    public func set(_ value: String?, for key: SecretKey) throws {
        lock.withLock { storage[key.account] = value }
    }

    public func deleteAll(matching prefix: String) throws {
        lock.withLock { storage = storage.filter { !$0.key.hasPrefix(prefix) } }
    }
}
