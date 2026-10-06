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
