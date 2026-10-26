import Foundation
import MetricsCore
import Testing

@testable import PluginRuntime

/// Decodes `contracts/fixtures/connector-manifest.json`.
///
/// The same bargain as `PluginManifestContractTests`, and for a stronger
/// reason: a connector manifest is written by an **agent** against a schema
/// published on npm, so the app and the author can drift apart without either
/// of them touching the other's code. A renamed field has to fail here, by
/// name, rather than at a user's launch as a decode error that empties the
/// Custom Apps list.
struct ConnectorManifestContractTests {
    static var fixture: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // PluginRuntimeTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // Kit
            .deletingLastPathComponent()  // mac
            .deletingLastPathComponent()  // apps
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("contracts/fixtures/connector-manifest.json")
    }

    static func manifest() throws -> ConnectorManifest {
        try JSONDecoder().decode(ConnectorManifest.self, from: Data(contentsOf: fixture))
    }

    @Test("the committed fixture decodes")
    func decodes() throws {
        let manifest = try Self.manifest()
        #expect(manifest.id == "linear")
        #expect(manifest.name == "Linear")
        #expect(manifest.entry == "connector.mjs")
        #expect(manifest.allowedHosts == ["api.linear.app"])
        #expect(manifest.auth.first?.key == "api_key")
        #expect(manifest.auth.first?.isSecret == true)
    }

    @Test("the fields the Custom Apps row draws are all present")
    func rowFields() throws {
        // Named individually rather than asserted as a blob, because this row
        // is the only place several of them are read — losing one would
        // otherwise show up as a gap in the UI and nowhere else.
        let manifest = try Self.manifest()
        #expect(manifest.displayVersion == "1.2.0")
        #expect(manifest.icon == .symbol(name: "chart.bar.doc.horizontal", tint: "#5E6AD2"))
        #expect(manifest.description.isEmpty == false)
        #expect(manifest.metrics.count == 1)
    }

    @Test("each icon arm decodes, and an unfamiliar one does not fail the manifest")
    func iconArms() throws {
        func decode(_ icon: [String: Any]) throws -> CustomAppIcon? {
            var object = try JSONSerialization.jsonObject(
                with: Data(contentsOf: Self.fixture)) as! [String: Any]
            object["icon"] = icon
            return try JSONDecoder().decode(
                ConnectorManifest.self,
                from: JSONSerialization.data(withJSONObject: object)).icon
        }

        #expect(try decode(["type": "symbol", "name": "shippingbox"])
            == .symbol(name: "shippingbox", tint: nil))
        #expect(try decode(["type": "emoji", "value": "📦"]) == .emoji("📦"))
        #expect(try decode(["type": "file", "path": "logo.png"]) == .file(name: "logo.png"))
        // A mark the app already ships, borrowed by the app it belongs to.
        #expect(try decode(["type": "app", "appId": "anthropic"]) == .app(id: "anthropic"))

        // An arm added after this build shipped. Kept as `unknown` rather than
        // refused, so a manifest from a newer core still loads and the app
        // simply draws its generic mark — the same asymmetry every other enum
        // crossing this boundary has.
        #expect(try decode(["type": "lottie", "url": "x"]) == .unknown)
    }

    @Test("a manifest from before version and icon existed still decodes")
    func olderManifestStillLoads() throws {
        // Both are optional on this side though defaulted in the schema. A
        // connector registered last week must not become `.invalid` because
        // the app learned two new fields.
        var object = try JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.fixture)) as! [String: Any]
        object.removeValue(forKey: "version")
        object.removeValue(forKey: "icon")

        let manifest = try JSONDecoder().decode(
            ConnectorManifest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(manifest.icon == nil)
        #expect(manifest.displayVersion == "1.0.0")
    }

    @Test("a metric shape added later does not invalidate the connector")
    func unknownShapeSurvives() throws {
        // The asymmetry the house rules ask for: strict on the server, an
        // `unknown` arm here. A connector built against a newer core must keep
        // its other metrics working rather than failing to decode entirely.
        var object = try JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.fixture)) as! [String: Any]
        var metrics = object["metrics"] as! [[String: Any]]
        metrics[0]["shape"] = ["kind": "histogram"]
        object["metrics"] = metrics

        let manifest = try JSONDecoder().decode(
            ConnectorManifest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(manifest.metrics.first?.shape.kindName == "histogram")
    }

    @Test("the refresh interval is floored at a minute")
    func refreshFloor() throws {
        #expect(try Self.manifest().effectiveRefreshInterval == 900)
    }

    @Test("an app declaring none asks for nothing")
    func noAuthMode() throws {
        func decode(_ patch: [String: Any]) throws -> ConnectorManifest {
            var object = try JSONSerialization.jsonObject(
                with: Data(contentsOf: Self.fixture)) as! [String: Any]
            for (k, v) in patch { object[k] = v }
            return try JSONDecoder().decode(
                ConnectorManifest.self, from: JSONSerialization.data(withJSONObject: object))
        }

        // A free or public API. No form, no Keychain read.
        let free = try decode(["authMode": "none", "auth": []])
        #expect(free.authMode == ConnectorAuthMode.none)
        #expect(free.requiresCredentials == false)

        // The fixture itself declares a key.
        #expect(try Self.manifest().requiresCredentials)
    }

    @Test("an auth mode added later does not read as needing nothing")
    func unknownAuthModeStillAsks() throws {
        // The dangerous direction. Treating an unfamiliar mode as `none` would
        // hide the form an app was relying on and leave its tiles waiting for
        // a credential nobody can enter, so the fields decide.
        var object = try JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.fixture)) as! [String: Any]
        object["authMode"] = "device_code"

        let manifest = try JSONDecoder().decode(
            ConnectorManifest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(manifest.authMode == .unknown)
        #expect(manifest.requiresCredentials)
    }

    @Test("a manifest with no authMode falls back to its fields")
    func derivedFromFields() throws {
        var object = try JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.fixture)) as! [String: Any]
        object.removeValue(forKey: "authMode")

        // With fields: asks.
        let asks = try JSONDecoder().decode(
            ConnectorManifest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(asks.authMode == nil)
        #expect(asks.requiresCredentials)

        // Without: does not. This is what every manifest written before the
        // field existed relies on.
        object["auth"] = []
        let quiet = try JSONDecoder().decode(
            ConnectorManifest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(quiet.requiresCredentials == false)
    }

    @Test("an aggregate over a window says so, and a reading taken now does not")
    func usesTimeWindow() throws {
        // What decides whether a tile's title carries "· 30d". Broader than
        // `supportsSeries` on purpose: a total draws no line and a list draws
        // rows, but change the window and both numbers change.
        #expect(ConnectorMetricShape.series(granularities: [.day], compare: false).usesTimeWindow)
        #expect(ConnectorMetricShape.total(granularities: [.day], compare: false).usesTimeWindow)
        #expect(ConnectorMetricShape.list(limit: 6).usesTimeWindow)

        // A reading taken now, and a shape this build has never heard of.
        // Unknown is false because a tile gaining a window it does not use is
        // the worse mistake.
        #expect(ConnectorMetricShape.scalar.usesTimeWindow == false)
        #expect(ConnectorMetricShape.unknown(kind: "histogram").usesTimeWindow == false)
    }
}
