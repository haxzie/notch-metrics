import Foundation
import MetricsCore
import Testing

@testable import MetricsAPI

/// The Custom category in the widget browser.
///
/// Local apps are presented as the server's own `ConnectorEntry` so that the
/// gallery, the search field and the preview card need no second code path.
/// What has to hold is that nothing local is ever mistaken for something
/// served, because that decides whether a widget is refreshed by the Node
/// runner or by the Worker.
struct LocalCatalogueTests {
    static func app(id: String = "npm-stats", metrics: Int = 2) -> LocalCatalogue.LocalApp {
        LocalCatalogue.LocalApp(
            id: id,
            name: "npm stats",
            tagline: "Download counts.",
            metrics: (0..<metrics).map { index in
                MetricDescriptor(
                    id: "\(id)/metric_\(index)", label: "Metric \(index)", shortLabel: "M\(index)",
                    unit: .count, granularities: [.day], supportsSeries: false,
                    supportsCompare: false, methodology: "m")
            })
    }

    @Test("a local entry is tagged custom and knows it is local")
    func tagged() throws {
        let entry = try #require(LocalCatalogue.entries([Self.app()]).first)
        #expect(entry.category == LocalCatalogue.categoryId)
        #expect(entry.isLocal)
        // The id the manifest on disk uses, recoverable from the browser's id.
        #expect(entry.localId == "npm-stats")
    }

    @Test("a served connector is never mistaken for a local one")
    func servedIsNotLocal() throws {
        // The property the whole routing rests on. `isLocal` is derived from
        // the id prefix and not from `category`, so a server catalogue that
        // happened to label a group "custom" cannot send someone's Stripe
        // widget to a local script.
        let served = ConnectorEntry(
            id: "stripe", name: "Stripe", category: "custom", tagline: "Payments.",
            accentColor: "635BFF", authMode: "oauth", metrics: [], status: "available")
        #expect(served.isLocal == false)
    }

    @Test("a custom app cannot shadow a connector we ship")
    func noCollision() throws {
        // Someone's local app called `stripe` has to stay distinguishable from
        // ours, because the id is the key the refresh path looks up.
        let entry = try #require(LocalCatalogue.entries([Self.app(id: "stripe")]).first)
        #expect(entry.id != "stripe")
        #expect(entry.isLocal)
        #expect(entry.localId == "stripe")
    }

    @Test("the group is labelled Custom and holds every local app")
    func group() throws {
        let group = try #require(
            LocalCatalogue.group([Self.app(id: "a"), Self.app(id: "b")]))
        #expect(group.id == "custom")
        #expect(group.label == "Custom")
        #expect(group.connectors.count == 2)
    }

    @Test("an app offering nothing is not listed")
    func emptyAppsAreDropped() {
        // A row you can open to find an empty grid is a dead end, which is the
        // same rule the server-side categories are filtered by.
        #expect(LocalCatalogue.group([Self.app(metrics: 0)]) == nil)
        #expect(LocalCatalogue.group([]) == nil)
    }

    @Test("a local app is connectable, so the browser does not offer to connect it")
    func statusIsAvailable() throws {
        let entry = try #require(LocalCatalogue.entries([Self.app()]).first)
        // Not `coming_soon`, which would render "not ready to connect yet".
        // A custom app has nothing to connect to — its credentials are already
        // in the Keychain.
        #expect(entry.isConnectable)
        #expect(entry.connections.isEmpty)
    }

    @Test("local apps are findable by searching for custom")
    func searchable() {
        let entries = LocalCatalogue.entries([Self.app()])
        // What somebody types when they cannot remember what they called it.
        #expect(WidgetSearch.run("custom", over: entries).count == 1)
        #expect(WidgetSearch.run("local", over: entries).count == 1)
        #expect(WidgetSearch.run("npm", over: entries).count == 1)
        #expect(WidgetSearch.run("stripe", over: entries).isEmpty)
    }

    @Test("the declared icon reaches the view, not just the entry")
    func declaredIconReachesTheView() throws {
        // The bug this pins: the entry carried the icon and the gallery was
        // handed a MetricApp resolved from the catalogue instead, whose
        // `customIcon` is nil — so an app declaring `shippingbox.fill` still
        // drew the generic mark in the sidebar and on every card.
        let app = LocalCatalogue.LocalApp(
            id: "npm-stats", name: "npm stats", tagline: "t",
            metrics: Self.app().metrics,
            icon: .symbol(name: "shippingbox.fill", tint: "#CB3837"))
        let entry = try #require(LocalCatalogue.entries([app]).first)

        #expect(entry.metricApp.customIcon == .symbol(name: "shippingbox.fill", tint: "#CB3837"))
        #expect(entry.metricApp.name == "npm stats")
    }

    @Test("an app declaring no icon keeps the generic Custom treatment")
    func noIconKeepsGeneric() throws {
        let entry = try #require(LocalCatalogue.entries([Self.app()]).first)
        // Falls back to the catalogue's Custom app rather than inventing one,
        // so the symbol and accent stay in step with everything else custom.
        #expect(entry.metricApp.customIcon == nil)
        #expect(entry.metricApp.symbol == AppCatalog.resolve(AppCatalog.customId).symbol)
    }

    @Test("a served connector is unaffected")
    func servedKeepsItsOwnApp() {
        let served = ConnectorEntry(
            id: "stripe", name: "Stripe", category: "revenue", tagline: "Payments.",
            accentColor: "635BFF", authMode: "oauth", metrics: [], status: "available")
        // Resolved by id so its committed mark is found, and carrying no
        // custom icon at all.
        #expect(served.metricApp.id == "stripe")
        #expect(served.metricApp.customIcon == nil)
    }

    @Test("the category holds apps only, never a standalone metric")
    func appsOnly() throws {
        // Standalone single-metric plugins are no longer authored or managed:
        // they have no row in Settings, so a widget added for one could never
        // be approved. Listing them here would be offering a dead end.
        let group = try #require(LocalCatalogue.group([Self.app()]))
        #expect(group.connectors.allSatisfy { $0.isLocal })
        // Every metric is addressed as `app/metric`, which is what
        // `CustomMetricRef` unpacks — a bare id would be a standalone one.
        #expect(group.connectors.flatMap(\.metrics).allSatisfy { $0.id.contains("/") })
    }

    @Test("a list metric says so, so a preview can draw rows")
    func listMetricsAreMarked() {
        // The gallery used to infer this from a hardcoded table of metric ids.
        // That worked while every metric shipped with the app; a custom app's
        // list metric can never be in that table and there is no release in
        // which to add one, so every one of them previewed as a figure.
        let list = MetricDescriptor(
            id: "app/rows", label: "Rows", shortLabel: "Rows", unit: .count,
            granularities: [.day], supportsSeries: false, supportsCompare: false,
            methodology: "m", isList: true)
        #expect(list.isList == true)

        // Unset means unknown, not false: a server catalogue that has never
        // heard of the field must not make every served list draw as a number.
        let served = MetricDescriptor(
            id: "recent_payments", label: "Payments", shortLabel: "Payments", unit: .currency,
            granularities: [.day], supportsSeries: false, supportsCompare: false,
            methodology: "m")
        #expect(served.isList == nil)
    }
}
