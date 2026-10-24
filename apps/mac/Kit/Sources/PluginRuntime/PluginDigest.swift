import CryptoKit
import Foundation

/// What a plugin's contents hash to, stably.
///
/// The installed copy lives in a directory the user owns, so "copied, and
/// therefore not altered on the fly" is only half true: nothing stops a
/// process writing over it afterwards, and an agent that can write once can
/// write twice. The copy stops drift; this is what catches tampering.
///
/// It replaces `"\(data.hashValue)-\(entry.hashValue)"`, which could not do
/// the job it was written for. Swift seeds `Hashable` randomly **per process**,
/// so that value differed on every launch — comparing it across two runs
/// always said "changed", and comparing it within one said nothing useful.
/// A digest has to survive a relaunch to be worth recording.
///
/// SHA-256 rather than something cheaper because this decides whether code
/// runs with the user's API keys. The input is two small files; the cost is
/// not worth optimising.
public enum PluginDigest {
    /// Over the manifest *and* the entry, in a fixed order, length-prefixed.
    ///
    /// Length prefixes because concatenation alone is ambiguous: a manifest
    /// ending in `X` with entry `Y` hashes the same as one ending in `XY` with
    /// an empty entry. That is a contrived collision rather than a likely one,
    /// and it costs sixteen bytes to make impossible.
    ///
    /// The manifest is included because it carries `allowedHosts` and
    /// `secrets` — approving a metric is approving *what it may reach*, and a
    /// digest over the code alone would let the hosts be rewritten freely.
    public static func of(manifest: Data, entry: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: withUnsafeBytes(of: UInt64(manifest.count).bigEndian) { Data($0) })
        hasher.update(data: manifest)
        hasher.update(data: withUnsafeBytes(of: UInt64(entry.count).bigEndian) { Data($0) })
        hasher.update(data: entry)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The digest of what is on disk, or nil if either file cannot be read.
    public static func of(directory: URL, entry: String) -> String? {
        guard
            let manifest = try? Data(
                contentsOf: directory.appendingPathComponent("manifest.json")),
            let source = try? Data(contentsOf: directory.appendingPathComponent(entry))
        else { return nil }
        return of(manifest: manifest, entry: source)
    }
}
