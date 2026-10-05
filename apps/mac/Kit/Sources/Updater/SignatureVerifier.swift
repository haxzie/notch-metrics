import CommonCrypto
import Foundation
import MetricsCore
import Security

public enum VerificationError: Error, Sendable, Equatable {
    case hashMismatch(expected: String, actual: String)
    case notSigned
    case wrongSigner(String)
    case downgrade(from: String, to: String)
    case unreadableBundle
}

/// Checks a downloaded build before it is allowed to replace the running one.
///
/// Two checks, and **both** are required.
///
/// The sha256 is cheap and catches a truncated or corrupted download before
/// anything is mounted. It is *not* sufficient on its own: the hash travels in
/// the same `latest.json`, from the same origin, as the disk image it
/// describes. Anybody who can rewrite the bucket, or compromise the publish
/// pipeline, rewrites both consistently and the check passes.
///
/// The code signature is what actually matters. It binds the artefact to a
/// private key that is not in the delivery path at all, so a compromised bucket
/// cannot produce one that validates.
public enum SignatureVerifier {
    public static let teamIdentifier = "2WH7TUH8N5"
    public static let bundleIdentifier = AppPaths.bundleIdentifier

    /// Streamed in chunks: the disk image is tens of megabytes and loading it
    /// whole to hash it is a pointless spike in a background task.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256Streaming()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(chunk)
        }
        return hasher.finalize()
    }

    public static func verifyHash(of url: URL, expected: String) throws {
        let actual = try sha256(of: url)
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw VerificationError.hashMismatch(expected: expected, actual: actual)
        }
    }

    /// Validates the bundle against a requirement pinning our team and bundle id.
    public static func verifySignature(of appURL: URL) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode
        else { throw VerificationError.unreadableBundle }

        // `anchor apple generic` means Apple's root, which a notarised
        // Developer ID build chains to. The leaf OU is the team id, and the
        // identifier pins the bundle — without it, any notarised app from this
        // team would satisfy the requirement.
        let text = """
            anchor apple generic \
            and identifier "\(bundleIdentifier)" \
            and certificate leaf[subject.OU] = "\(teamIdentifier)"
            """

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { throw VerificationError.notSigned }

        let status = SecStaticCodeCheckValidity(
            staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode),
            requirement)

        guard status == errSecSuccess else {
            throw VerificationError.wrongSigner(
                SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)")
        }
    }

    /// Refuses a build that is not actually newer.
    ///
    /// A downgrade is a real attack: serving an older, signed, legitimately
    /// notarised build with a known flaw passes every signature check there is.
    public static func verifyNotADowngrade(
        mountedApp: URL, manifest: LatestManifest, running: String
    ) throws {
        guard let plist = NSDictionary(
            contentsOf: mountedApp.appendingPathComponent("Contents/Info.plist")),
            let bundled = plist["CFBundleShortVersionString"] as? String
        else { throw VerificationError.unreadableBundle }

        guard bundled == manifest.version else {
            throw VerificationError.wrongSigner(
                "the disk image contains \(bundled), not the \(manifest.version) it advertised")
        }

        guard let new = SemanticVersion(bundled), let old = SemanticVersion(running), new > old
        else { throw VerificationError.downgrade(from: running, to: bundled) }
    }
}

/// A tiny streaming SHA-256 so `MetricsCore` need not depend on CryptoKit.
struct SHA256Streaming {
    private var context = CC_SHA256_CTX()

    init() { CC_SHA256_Init(&context) }

    mutating func update(_ data: Data) {
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256_Update(&context, buffer.baseAddress, CC_LONG(buffer.count))
        }
    }

    mutating func finalize() -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
