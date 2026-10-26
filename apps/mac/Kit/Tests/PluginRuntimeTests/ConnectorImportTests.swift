import Foundation
import MetricsCore
import Testing

@testable import PluginRuntime

/// Loading an app from a folder the user picked.
///
/// "Load app" is the one way a connector arrives without an agent, so it is
/// the one path where the thing being installed was chosen by a file picker
/// rather than written by something that had already read the schema.
struct ConnectorImportTests {
    static func temporaryRoot(_ label: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("connector-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// A source folder as a user's project would leave it.
    @discardableResult
    static func makeSource(
        in root: URL, folder: String = "my-linear-thing", id: String = "linear",
        version: String = "1.2.0", icon: String? = "icon.png", entry: String = "connector.mjs",
        writeEntry: Bool = true
    ) throws -> URL {
        let dir = root.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var manifest: [String: Any] = [
            "schemaVersion": 1, "id": id, "name": "Linear",
            "description": "Issues from a Linear workspace.",
            "appId": "custom", "version": version,
            "auth": [["key": "api_key", "label": "API key", "type": "secret", "required": true]],
            "allowedHosts": ["api.linear.app"],
            "metrics": [
                [
                    "id": "open_issues", "label": "Open issues", "shortLabel": "Open",
                    "unit": "count", "shape": ["kind": "scalar"],
                    "methodology": "Issues in backlog and started states.",
                ],
                [
                    "id": "completed", "label": "Completed", "shortLabel": "Done",
                    "unit": "count",
                    "shape": ["kind": "series", "granularities": ["day"], "compare": true],
                    "methodology": "Issues moved to done in the window.",
                ],
            ],
            "refreshIntervalSeconds": 900, "timeoutMs": 8000, "entry": entry,
            "createdAt": "2026-10-05T12:00:00.000Z", "updatedAt": "2026-10-05T12:00:00.000Z",
        ]
        if let icon {
            manifest["icon"] = ["type": "file", "path": icon]
            try Data("png".utf8).write(to: dir.appendingPathComponent(icon))
        }

        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: dir.appendingPathComponent("manifest.json"))
        if writeEntry {
            try Data("export async function fetchMetric() {}".utf8)
                .write(to: dir.appendingPathComponent(entry))
        }
        return dir
    }

    @Test("the installed folder is named by the manifest, not by the folder picked")
    func idComesFromTheManifest() throws {
        let source = try Self.temporaryRoot("src")
        let root = try Self.temporaryRoot("root")
        try Self.makeSource(in: source, folder: "my-linear-thing", id: "linear")

        let manifest = try ConnectorImport.install(
            from: source.appendingPathComponent("my-linear-thing"), into: root)

        // Everything else keys off the directory name, so installing under the
        // folder the user happened to pick would approve it under one id and
        // run it under another.
        #expect(manifest.id == "linear")
        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("linear/manifest.json").path))
    }

    @Test("the source folder is left alone")
    func sourceSurvives() throws {
        let source = try Self.temporaryRoot("src")
        let root = try Self.temporaryRoot("root")
        let dir = try Self.makeSource(in: source)
        try ConnectorImport.install(from: dir, into: root)

        // A copy, never a move. The user is still working in that project.
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("manifest.json").path))
    }

    @Test("a folder with no manifest is refused before anything is written")
    func refusesAFolderThatIsNotAConnector() throws {
        let source = try Self.temporaryRoot("src")
        let root = try Self.temporaryRoot("root")
        let empty = source.appendingPathComponent("not-a-connector")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        #expect(throws: ConnectorImport.Failure.self) {
            try ConnectorImport.install(from: empty, into: root)
        }
        // Nothing half-installed: a directory left behind here would show up
        // in the list for ever as a broken app the user never added.
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test("a manifest whose entry file is missing is refused")
    func refusesAMissingEntry() throws {
        let source = try Self.temporaryRoot("src")
        let root = try Self.temporaryRoot("root")
        let dir = try Self.makeSource(in: source, writeEntry: false)

        #expect(throws: ConnectorImport.Failure.self) {
            try ConnectorImport.install(from: dir, into: root)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test("installing over an existing app needs saying so twice")
    func refusesToReplaceSilently() throws {
        let source = try Self.temporaryRoot("src")
        let root = try Self.temporaryRoot("root")
        let dir = try Self.makeSource(in: source)
        try ConnectorImport.install(from: dir, into: root)

        #expect(throws: ConnectorImport.Failure.alreadyInstalled(id: "linear")) {
            try ConnectorImport.install(from: dir, into: root)
        }
        // ...and goes through when the caller has asked a human first.
        try ConnectorImport.install(from: dir, into: root, replacing: true)
    }

    @Test("an installed app is found by the registry, pending approval")
    @MainActor
    func installedAppsAppearPending() throws {
        let source = try Self.temporaryRoot("src")
        let root = try Self.temporaryRoot("root")
        try ConnectorImport.install(from: try Self.makeSource(in: source), into: root)

        let found = ConnectorRegistry.scan(root: root, approved: [:])
        let app = try #require(found.first)
        #expect(app.id == "linear")
        #expect(app.state == .pendingApproval)
        // The six things the row draws.
        #expect(app.displayName == "Linear")
        #expect(app.manifest?.description == "Issues from a Linear workspace.")
        #expect(app.manifest?.displayVersion == "1.2.0")
        #expect(app.metricCount == 2)
        #expect(app.iconURL != nil)
        #expect(app.displayPath.hasSuffix("/linear"))
    }

    @Test("an icon the manifest names but does not ship resolves to nothing")
    @MainActor
    func missingIconIsNil() throws {
        let source = try Self.temporaryRoot("src")
        let root = try Self.temporaryRoot("root")
        let dir = try Self.makeSource(in: source, icon: nil)
        // Name an icon that was never written.
        let manifestURL = dir.appendingPathComponent("manifest.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
            as! [String: Any]
        object["icon"] = ["type": "file", "path": "logo.png"]
        try JSONSerialization.data(withJSONObject: object).write(to: manifestURL)

        try ConnectorImport.install(from: dir, into: root)
        let app = try #require(ConnectorRegistry.scan(root: root, approved: [:]).first)
        // Nil rather than a URL that 404s into a broken-image box.
        #expect(app.iconURL == nil)
    }

    @Test("a folder disagreeing with its manifest id is refused")
    @MainActor
    func folderMustMatchManifest() throws {
        // Reachable without the importer: a directory copied in by hand, or
        // renamed after install. The scan has to catch it too, because
        // approval is recorded against the directory name.
        let root = try Self.temporaryRoot("root")
        try Self.makeSource(in: root, folder: "renamed", id: "linear")

        let app = try #require(ConnectorRegistry.scan(root: root, approved: [:]).first)
        guard case let .invalid(reason) = app.state else {
            Issue.record("expected invalid, got \(app.state)")
            return
        }
        #expect(reason.contains("renamed"))
        #expect(reason.contains("linear"))
    }

    @Test("widening what an app asks for revokes its approval")
    @MainActor
    func wideningRevokes() throws {
        let source = try Self.temporaryRoot("src")
        let root = try Self.temporaryRoot("root")
        try ConnectorImport.install(from: try Self.makeSource(in: source), into: root)

        let grants = try #require(ConnectorRegistry.scan(root: root, approved: [:]).first?.grants)
        let approved = ["linear": grants.canonical]
        #expect(ConnectorRegistry.scan(root: root, approved: approved).first?.state == .ready)

        // Widening allowedHosts with the code untouched. The manifest is what
        // says where the user's API key may be sent, so it counts as a change.
        let manifestURL = root.appendingPathComponent("linear/manifest.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
            as! [String: Any]
        object["allowedHosts"] = ["api.linear.app", "evil.example.com"]
        try JSONSerialization.data(withJSONObject: object).write(to: manifestURL)

        let widened = try #require(ConnectorRegistry.scan(root: root, approved: approved).first)
        #expect(widened.state == .modified)
        // And says which host, because "this app has changed" is not a
        // question anyone can answer.
        #expect(widened.newGrants == ["reach evil.example.com"])
    }

    @Test("rewriting the code alone does not")
    @MainActor
    func codeChangeKeepsApproval() throws {
        // The reason the gate moved off a content digest. Every cosmetic edit
        // — an icon, a version bump, a longer timeout — used to revoke
        // approval and show a button nobody could answer except by saying
        // yes, which is how you teach someone to say yes to the one that
        // mattered.
        let source = try Self.temporaryRoot("src")
        let root = try Self.temporaryRoot("root")
        try ConnectorImport.install(from: try Self.makeSource(in: source), into: root)

        let before = try #require(ConnectorRegistry.scan(root: root, approved: [:]).first)
        let approved = ["linear": before.grants.canonical]

        try "export default { fetchMetric: () => ({}) }\n".write(
            to: root.appendingPathComponent("linear/connector.mjs"), atomically: true,
            encoding: .utf8)
        let manifestURL = root.appendingPathComponent("linear/manifest.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
            as! [String: Any]
        object["version"] = "9.9.9"
        object["timeoutMs"] = 20000
        try JSONSerialization.data(withJSONObject: object).write(to: manifestURL)

        let after = try #require(ConnectorRegistry.scan(root: root, approved: approved).first)
        #expect(after.state == .ready)
        // The content digest still moves, so the scheduler notices a rewrite
        // and re-runs rather than waiting out the interval.
        #expect(after.contentHash != before.contentHash)
    }

    @Test("narrowing what an app asks for is not a question")
    @MainActor
    func narrowingIsSilent() throws {
        let source = try Self.temporaryRoot("src")
        let root = try Self.temporaryRoot("root")
        try ConnectorImport.install(from: try Self.makeSource(in: source), into: root)

        // Approved for two hosts; now wants one. Nothing is being handed over
        // that was not already agreed to, so interrupting would be noise.
        let approved = [
            "linear": ConnectorGrants(
                hosts: ["api.linear.app", "example.com"], hostCredentials: [],
                secrets: ["api_key"]
            ).canonical
        ]
        #expect(ConnectorRegistry.scan(root: root, approved: approved).first?.state == .ready)
    }

    @Test("an approval recorded as a digest by an older build is migrated, not re-asked")
    @MainActor
    func legacyApprovalMigrates() throws {
        let source = try Self.temporaryRoot("src")
        let root = try Self.temporaryRoot("root")
        try ConnectorImport.install(from: try Self.makeSource(in: source), into: root)

        // What a build before `ConnectorGrants` wrote: a content SHA, which
        // records no grants. The user enabled this app; an upgrade is not a
        // reason to ask them again, so the grants on disk are adopted.
        let digest = try #require(
            ConnectorRegistry.scan(root: root, approved: [:]).first?.contentHash)
        let app = try #require(
            ConnectorRegistry.scan(root: root, approved: ["linear": digest]).first)
        #expect(app.state == .ready)

        // And the registry offers the replacement, so the digest is rewritten
        // as grants once rather than re-derived on every launch — which is
        // what makes the *next* widening comparable against something.
        let registry = ConnectorRegistry(root: root, approved: ["linear": digest])
        registry.start()
        #expect(registry.legacyApprovals == ["linear": app.grants.canonical])

        // Nothing to migrate once it is stored.
        let migrated = ConnectorRegistry(root: root, approved: ["linear": app.grants.canonical])
        migrated.start()
        #expect(migrated.legacyApprovals.isEmpty)
    }

    @Test("a migrated app is still checked against the next widening")
    @MainActor
    func migrationDoesNotBlindTheGate() throws {
        // The thing the silent migration must not cost: adopting the grants
        // on disk is a one-off, and the app is held to them afterwards.
        let source = try Self.temporaryRoot("src")
        let root = try Self.temporaryRoot("root")
        try ConnectorImport.install(from: try Self.makeSource(in: source), into: root)

        let adopted = try #require(
            ConnectorRegistry.scan(root: root, approved: [:]).first?.grants)

        let manifestURL = root.appendingPathComponent("linear/manifest.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
            as! [String: Any]
        object["hostCredentials"] = ["claude_code_oauth"]
        try JSONSerialization.data(withJSONObject: object).write(to: manifestURL)

        let app = try #require(
            ConnectorRegistry.scan(root: root, approved: ["linear": adopted.canonical]).first)
        #expect(app.state == .modified)
        #expect(app.newGrants == ["use your Claude Code sign-in"])
    }
}
