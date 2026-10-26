import Foundation
import Testing

@testable import MetricsCore

/// Every metric in the notch belongs to an app, so the catalogue has to have
/// an answer for any id — including ones this build predates.
struct AppCatalogTests {
    @Test("a known app resolves to its own name and mark")
    func known() {
        let stripe = AppCatalog.resolve("stripe")
        #expect(stripe.name == "Stripe")
        #expect(stripe.accentHex == "635BFF")
    }

    @Test("resolution is case-insensitive")
    func caseInsensitive() {
        #expect(AppCatalog.resolve("Stripe").id == "stripe")
        #expect(AppCatalog.resolve("GOOGLE-ANALYTICS").name == "Google Analytics")
    }

    @Test("an unknown app is titlecased rather than dropped")
    func unknownIsRendered() {
        // The alternative — hiding the row, or failing the layout — is how one
        // unfamiliar value from a newer server blanks a whole notch.
        let linear = AppCatalog.resolve("linear-issues")
        #expect(linear.id == "linear-issues")
        #expect(linear.name == "Linear Issues")
        #expect(!linear.symbol.isEmpty)
        #expect(linear.accentHex.count == 6)
    }

    @Test("nil and empty resolve to something renderable")
    func missing() {
        for id in [nil, ""] as [String?] {
            let app = AppCatalog.resolve(id)
            #expect(!app.name.isEmpty)
            #expect(!app.symbol.isEmpty)
        }
    }

    @Test("a server manifest overrides the built-in entry")
    func overrides() {
        // Providers ship without an app release, so the server's name and
        // colour have to win over whatever this build was compiled with.
        let override = MetricApp(
            id: "stripe", name: "Stripe (EU)", symbol: "eurosign", accentHex: "000000")
        #expect(AppCatalog.resolve("stripe", overrides: ["stripe": override]).name == "Stripe (EU)")
    }

    @Test("every built-in entry has a usable accent")
    func accentsParse() {
        for app in AppCatalog.builtIn {
            #expect(app.accentHex.count == 6, "\(app.id)")
            #expect(UInt32(app.accentHex, radix: 16) != nil, "\(app.id)")
        }
    }
}

struct WidgetAppTests {
    @Test("a widget reports the app it declares")
    func declared() {
        let widget = NotchWidget(appId: "google-analytics", metric: "active_subscribers")
        #expect(widget.app().name == "Google Analytics")
    }

    @Test("a layout written before apps existed still decodes")
    func backCompatible() throws {
        // Users have this file on disk. A missing appId must infer something
        // usable, not throw — the alternative is an empty notch after update.
        let json = """
            {"schemaVersion":1,"revision":2,"widgets":[
              {"id":"a","kind":"custom_metric","integrationId":null,"metric":null,
               "customMetricId":"stars","title":"Stars","size":"1x1","col":0,"row":0,
               "position":0,"granularity":"day","range":"30d","chart":"none","visible":true},
              {"id":"b","kind":"provider_metric","integrationId":"int_1","metric":"mrr",
               "customMetricId":null,"title":"MRR","size":"2x1","col":1,"row":0,
               "position":1,"granularity":"day","range":"30d","chart":"none","visible":true}
            ]}
            """
        let layout = try JSONDecoder().decode(NotchLayout.self, from: Data(json.utf8))
        #expect(layout.widgets[0].appId == AppCatalog.customId)
        #expect(layout.widgets[1].appId == AppCatalog.unknownId)
    }


}

/// A custom app's icon, which cannot be in the asset catalogue.
struct CustomAppIconTests {
    @Test("a local id with no override still resolves to Custom, not to unknown")
    func localFallsBackToCustom() {
        // The registry rescans asynchronously and a widget is drawn before it
        // finishes, so this gap is reached on every launch. Grey "app.dashed"
        // there would be a visible flicker on something already known to be
        // custom.
        let app = AppCatalog.resolve("local.npm-stats")
        #expect(app.symbol == AppCatalog.resolve(AppCatalog.customId).symbol)
        #expect(app.accentHex == AppCatalog.resolve(AppCatalog.customId).accentHex)
    }

    @Test("an unknown id that is not local keeps the generic treatment")
    func othersAreUnchanged() {
        // The fallback is scoped to the `local.` prefix. A typo in a served
        // app id must not silently render as a custom app.
        #expect(AppCatalog.resolve("not-a-real-app").symbol == "app.dashed")
    }

    @Test("an override carries the declared icon through to every surface")
    func overrideCarriesIcon() {
        let overrides = [
            "local.npm-stats": MetricApp(
                id: "local.npm-stats", name: "npm stats", symbol: "curlybraces",
                accentHex: "D819C2",
                customIcon: .symbol(name: "shippingbox", tint: "#FF6B00"))
        ]
        let app = AppCatalog.resolve("local.npm-stats", overrides: overrides)
        #expect(app.name == "npm stats")
        #expect(app.customIcon == .symbol(name: "shippingbox", tint: "#FF6B00"))
    }

    @Test("an app with no icon reports none rather than a blank one")
    func noIconIsNil() {
        // Nil, so `ConnectorIcon` falls through to the asset catalogue and
        // then to the symbol.
        #expect(AppCatalog.resolve(AppCatalog.customId).customIcon == nil)
        #expect(AppCatalog.resolve(AppCatalog.customId).customIconFile == nil)
    }

    @Test("a file icon resolves inside its own directory, and only there")
    func fileIconIsContained() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("icon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: root.appendingPathComponent("logo.png"))

        #expect(CustomAppIcon.file(name: "logo.png").fileURL(in: root)?.lastPathComponent
            == "logo.png")
        // Refused before the file system is asked, so a name that escapes the
        // directory cannot be read even if it got past the schema.
        #expect(CustomAppIcon.file(name: "../../etc/passwd").fileURL(in: root) == nil)
        // Named but absent resolves to nothing rather than a URL that fails to
        // decode into a broken-image box.
        #expect(CustomAppIcon.file(name: "missing.png").fileURL(in: root) == nil)
        // The other arms have no file at all.
        #expect(CustomAppIcon.emoji("📦").fileURL(in: root) == nil)
        #expect(CustomAppIcon.symbol(name: "shippingbox", tint: nil).fileURL(in: root) == nil)
    }

    @Test("a borrowed mark names the app it belongs to")
    func borrowedMark() {
        // The icon and the tile colour both come from that one app, so a
        // connector built against a known service looks like that service
        // without shipping a copy of its logo that drifts from ours.
        #expect(CustomAppIcon.app(id: "anthropic").borrowedAppId == "anthropic")

        // The other arms borrow nothing, and must not be mistaken for an app
        // id — looking one up would resolve to the grey unknown app.
        #expect(CustomAppIcon.symbol(name: "gauge", tint: nil).borrowedAppId == nil)
        #expect(CustomAppIcon.emoji("📦").borrowedAppId == nil)
        #expect(CustomAppIcon.file(name: "logo.png").borrowedAppId == nil)
        #expect(CustomAppIcon.unknown.borrowedAppId == nil)
    }

    @Test("Claude resolves to the mark and colour the app already ships")
    func claudeIsKnown() {
        // What "the right icon and colour" actually resolves to. The mark is
        // in the asset catalogue as connector-anthropic; this pins the id and
        // the accent that find it.
        let claude = AppCatalog.resolve("anthropic")
        #expect(claude.name == "Claude")
        #expect(claude.accentHex == "D97757")
    }

    @Test("a borrowed mark brings its colours, not just its logo")
    func borrowedColours() {
        // The bug this pins: the icon resolved the borrowed mark while the
        // colour stayed the generic Custom magenta, so a Claude logo sat on a
        // pink tile and drew a pink gauge. Two callers built this struct and
        // only one of them knew about the borrow.
        let claude = MetricApp.custom(
            id: "local.claude-usage", name: "Claude usage",
            icon: .app(id: "anthropic"))
        #expect(claude.accentHex == AppCatalog.resolve("anthropic").accentHex)
        #expect(claude.accentHex != AppCatalog.resolve(AppCatalog.customId).accentHex)
        // The name stays the custom app's own: borrowing a mark is not
        // claiming to be that app.
        #expect(claude.name == "Claude usage")
    }

    @Test("an app borrowing nothing keeps the Custom colours")
    func unborrowedKeepsGeneric() {
        let generic = AppCatalog.resolve(AppCatalog.customId)
        for icon in [CustomAppIcon.symbol(name: "gauge", tint: nil), .emoji("📦"), .unknown] {
            let app = MetricApp.custom(id: "local.x", name: "X", icon: icon)
            #expect(app.accentHex == generic.accentHex)
            #expect(app.symbol == generic.symbol)
        }
        #expect(MetricApp.custom(id: "local.x", name: "X", icon: nil).accentHex == generic.accentHex)
    }
}
