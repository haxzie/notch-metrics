import Foundation
import MetricsCore
import Testing

@testable import PluginRuntime

/// Approval binds to contents, not to a name.
///
/// The installed copy is the Chrome-extension bargain: registering writes a
/// snapshot into a directory the app owns, and that snapshot is what runs. The
/// copy stops the source drifting under a running app. It does **not** make
/// the file read-only — the user owns that directory, and anything that could
/// write it once can write it again.
///
/// So the digest is the half that holds. Approving a metric approves its code
/// *and* its `allowedHosts` and declared secrets; changing any of them asks
/// again.
struct PluginIntegrityTests {
    static func makePlugin(
        in root: URL, id: String = "stars", hosts: [String] = ["api.github.com"],
        body: String = "export async function fetchMetric() { return { value: 1 } }"
    ) throws -> URL {
        let dir = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = """
            {
              "schemaVersion": 1, "id": "\(id)", "name": "Stars", "shortLabel": "Stars",
              "description": "d", "unit": "count",
              "format": { "decimals": 0, "compact": true, "prefix": "", "suffix": "" },
              "granularities": ["day"], "supportsSeries": false,
              "refreshIntervalSeconds": 900, "secrets": [],
              "allowedHosts": \(try String(data: JSONEncoder().encode(hosts), encoding: .utf8)!),
              "timeoutMs": 8000, "entry": "metric.mjs",
              "createdAt": "2026-10-05T12:00:00.000Z",
              "updatedAt": "2026-10-05T12:00:00.000Z"
            }
            """
        try manifest.write(
            to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try body.write(
            to: dir.appendingPathComponent("metric.mjs"), atomically: true, encoding: .utf8)
        return dir
    }

    static func temporaryRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("plugin-integrity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("the digest survives a relaunch")
    func digestIsStable() throws {
        // The property the old `Data.hashValue` version lacked. Swift seeds
        // hashing per process, so the previous contentHash differed on every
        // launch and could not be compared with anything written down.
        let manifest = Data("{}".utf8)
        let entry = Data("export async function fetchMetric() {}".utf8)
        let once = PluginDigest.of(manifest: manifest, entry: entry)
        let twice = PluginDigest.of(manifest: manifest, entry: entry)
        #expect(once == twice)
        #expect(once.count == 64)  // hex SHA-256
    }

    @Test("moving a byte between the two files changes the digest")
    func lengthPrefixed() {
        // Without length prefixes these two hash identically, and a manifest
        // could borrow a character from the code to keep its digest.
        let a = PluginDigest.of(manifest: Data("ab".utf8), entry: Data("c".utf8))
        let b = PluginDigest.of(manifest: Data("a".utf8), entry: Data("bc".utf8))
        #expect(a != b)
    }

    @MainActor
    @Test("an unknown plugin is pending, never ready")
    func unknownIsPending() throws {
        let root = try Self.temporaryRoot()
        _ = try Self.makePlugin(in: root)
        let found = PluginRegistry.scan(root: root, approved: [:])
        #expect(found.first?.state == .pendingApproval)
    }

    @MainActor
    @Test("approving the digest makes it ready")
    func approvedIsReady() throws {
        let root = try Self.temporaryRoot()
        _ = try Self.makePlugin(in: root)
        let digest = try #require(PluginRegistry.scan(root: root, approved: [:]).first?.contentHash)

        let found = PluginRegistry.scan(root: root, approved: ["stars": digest])
        #expect(found.first?.state == .ready)
    }

    @MainActor
    @Test("rewriting the code after approval revokes it")
    func rewrittenCodeIsModified() throws {
        let root = try Self.temporaryRoot()
        _ = try Self.makePlugin(in: root)
        let digest = try #require(PluginRegistry.scan(root: root, approved: [:]).first?.contentHash)

        // The attack the old `Set<String>` could not see: write something
        // benign, get a yes, then write something else.
        _ = try Self.makePlugin(
            in: root, body: "export async function fetchMetric() { return { value: 999 } }")

        let found = PluginRegistry.scan(root: root, approved: ["stars": digest])
        #expect(found.first?.state == .modified)
    }

    @MainActor
    @Test("widening allowedHosts after approval revokes it too")
    func rewrittenHostsIsModified() throws {
        let root = try Self.temporaryRoot()
        _ = try Self.makePlugin(in: root)
        let digest = try #require(PluginRegistry.scan(root: root, approved: [:]).first?.contentHash)

        // The more interesting half. The code is untouched; only the manifest
        // moved — and the manifest is what says where the user's API key may
        // be sent. A digest over the entry alone would have called this ready.
        _ = try Self.makePlugin(in: root, hosts: ["api.github.com", "evil.example.com"])

        let found = PluginRegistry.scan(root: root, approved: ["stars": digest])
        #expect(found.first?.state == .modified)
    }

    @MainActor
    @Test("a digest approved for one plugin does not approve another")
    func digestsAreNotTransferable() throws {
        let root = try Self.temporaryRoot()
        _ = try Self.makePlugin(in: root, id: "stars")
        _ = try Self.makePlugin(in: root, id: "forks")

        let stars = try #require(
            PluginRegistry.scan(root: root, approved: [:]).first { $0.id == "stars" }?.contentHash)

        // Keyed by id as well as digest, so approving one does not silently
        // bless an identical copy registered under another name.
        let found = PluginRegistry.scan(root: root, approved: ["stars": stars])
        #expect(found.first { $0.id == "stars" }?.state == .ready)
        #expect(found.first { $0.id == "forks" }?.state == .pendingApproval)
    }
}

/// Noticing that an agent has written a metric.
///
/// The MCP server writes into this directory while the app is running, so an
/// arrival happens *to* the app. Without this the metric sits in a folder
/// nobody is looking at while the agent says "enable it in Settings".
@MainActor
struct PluginArrivalTests {
    @Test("the first scan announces nothing")
    func firstScanIsSilent() throws {
        let root = try PluginIntegrityTests.temporaryRoot()
        _ = try PluginIntegrityTests.makePlugin(in: root, id: "stars")

        var announced: [[String]] = []
        let registry = PluginRegistry(root: root)
        registry.onAdded = { announced.append($0.map(\.id)) }
        registry.reload()

        // Everything is new at launch. A stack of banners for metrics
        // installed weeks ago is what teaches people to ignore banners.
        #expect(announced.isEmpty)
    }

    @Test("a metric written while the app is running is announced once")
    func arrivalIsAnnounced() throws {
        let root = try PluginIntegrityTests.temporaryRoot()
        let registry = PluginRegistry(root: root)
        var announced: [[String]] = []
        registry.onAdded = { announced.append($0.map(\.id)) }
        registry.reload()

        _ = try PluginIntegrityTests.makePlugin(in: root, id: "stars")
        registry.reload()
        #expect(announced == [["stars"]])

        // ...and not again on the next scan, which FSEvents fires freely.
        registry.reload()
        #expect(announced == [["stars"]])
    }

    @Test("a rewrite is not an arrival")
    func rewriteIsNotAnArrival() throws {
        let root = try PluginIntegrityTests.temporaryRoot()
        _ = try PluginIntegrityTests.makePlugin(in: root, id: "stars")
        let registry = PluginRegistry(root: root)
        var announced: [[String]] = []
        registry.onAdded = { announced.append($0.map(\.id)) }
        registry.reload()

        // `refresh_metric` rewrites the same id. That is a change to something
        // the user already knows about, and it has its own signal: the tile
        // stops being ready and says so.
        _ = try PluginIntegrityTests.makePlugin(
            in: root, id: "stars",
            body: "export async function fetchMetric() { return { value: 2 } }")
        registry.reload()
        #expect(announced.isEmpty)
    }

    @Test("several at once are announced together")
    func batched() throws {
        let root = try PluginIntegrityTests.temporaryRoot()
        let registry = PluginRegistry(root: root)
        var announced: [[String]] = []
        registry.onAdded = { announced.append($0.map(\.id)) }
        registry.reload()

        _ = try PluginIntegrityTests.makePlugin(in: root, id: "stars")
        _ = try PluginIntegrityTests.makePlugin(in: root, id: "forks")
        registry.reload()

        // One callback, not two — so the banner can say "2 widgets added"
        // rather than shoving two cards past the user in a second.
        #expect(announced.count == 1)
        #expect(Set(announced[0]) == ["stars", "forks"])
    }
}
