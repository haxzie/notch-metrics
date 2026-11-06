import MetricsCore
import AppKit
import SwiftUI
import Testing

@testable import NotchUI

/// npm's mark and its chart have to agree, and both come from the catalogue
/// entry rather than from a fallback.
@Suite("npm accent")
struct NpmAccentTests {
    /// The bug this pins: `npm` was missing from `AppCatalog.builtIn`, so it
    /// fell through to the unknown-app fallback — titlecased to "Npm" and
    /// given the grey `8E8E93`. `chartTint` reads that grey as having no hue
    /// worth raising and flattens it to `Color(white: 0.72)`, so the
    /// sparkline came out white. One missing row, visible twice.
    @Test("resolves to npm's own name and red, not the unknown-app fallback")
    func resolved() {
        let app = AppCatalog.resolve("npm")
        #expect(app.name == "npm")
        #expect(app.accentHex.uppercased() == "CB3837")
    }

    /// Bright enough to be left alone: `chartTint` only lifts a brand that
    /// publishes a dark primary, and npm's red is well over the floor.
    @Test("draws the sparkline in npm's red rather than lifting or greying it")
    func tinted() throws {
        let app = AppCatalog.resolve("npm")

        // Compared as components, not as `Color`s. Two `Color`s wrapping the
        // same sRGB values are not `==` when one came from `Color(nsColor:)`
        // and the other from `Color(hex:)` — they carry different backing
        // providers, so the equality says nothing about what is drawn.
        let tint = try #require(NSColor(NotchTheme.chartTint(for: app)).usingColorSpace(.sRGB))
        #expect(Int((tint.redComponent * 255).rounded()) == 0xCB)
        #expect(Int((tint.greenComponent * 255).rounded()) == 0x38)
        #expect(Int((tint.blueComponent * 255).rounded()) == 0x37)
    }
}
