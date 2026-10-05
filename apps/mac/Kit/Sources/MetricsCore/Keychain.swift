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
            // The modern keychain. Without it items land in the legacy file
            // keychain, which has its own ACL prompts and a different
            // migration story.
            kSecUseDataProtectionKeychain as String: true,
        ]
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
        case errSecInteractionNotAllowed, errSecAuthFailed:
            throw SecretStoreError.identityChanged
        default:
            throw SecretStoreError.unexpected(status)
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
        if status == errSecDuplicateItem {
            let update = SecItemUpdate(
                query(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard update == errSecSuccess else { throw SecretStoreError.unexpected(update) }
            return
        }
        guard status == errSecSuccess else { throw SecretStoreError.unexpected(status) }
    }

    public func deleteAll(matching prefix: String) throws {
        var request: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: true,
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
