import Foundation
import MetricsCore
import Testing

@testable import NotchUI

/// App names and icons published before the notch exists.
///
/// Every other `update(_:)` on the controller is called repeatedly from a
/// refresh loop, so one dropped before the view is built costs a few seconds.
/// These are published once at launch — and `start()` runs afterwards, so the
/// value went nowhere and every custom tile drew the generic mark under the
/// name "Custom" until something else happened to republish.
@MainActor
struct AppOverridesTests {
    @Test("overrides published before the view is built are not lost")
    func heldUntilTheViewExists() {
        let model = NotchLayoutModel(layout: NotchLayout(rows: 2, widgets: []), persist: { _ in })
        let controller = NotchWindowController(model: model)

        let app = MetricApp(
            id: "local.npm-downloads", name: "npm downloads", symbol: "curlybraces",
            accentHex: "D819C2",
            customIcon: .symbol(name: "shippingbox.fill", tint: "#CB3837"))
        controller.update(appOverrides: ["local.npm-downloads": app])

        // Nothing has been built yet; the value has to survive that.
        controller.start()
        defer { controller.close() }

        let resolved = AppCatalog.resolve(
            "local.npm-downloads", overrides: controller.effectiveAppOverrides)
        #expect(resolved.name == "npm downloads")
        #expect(resolved.customIcon == .symbol(name: "shippingbox.fill", tint: "#CB3837"))
    }
}
