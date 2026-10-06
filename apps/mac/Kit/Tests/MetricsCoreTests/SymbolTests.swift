import AppKit
import Testing

@testable import MetricsCore

/// Every symbol in the catalogue must actually exist in SF Symbols.
///
/// A name that does not resolve renders as *nothing* — no glyph, no warning,
/// no crash. The connector row just has a blank where its icon should be, and
/// it looks like a loading bug rather than a typo. There is no way to catch
/// that by reading the code, so it is caught here.
struct SymbolTests {
    @Test("every app in the catalogue has a real SF Symbol")
    func symbolsResolve() {
        for app in AppCatalog.builtIn {
            let image = NSImage(systemSymbolName: app.symbol, accessibilityDescription: nil)
            #expect(image != nil, "\(app.id) uses a symbol that does not exist: \(app.symbol)")
        }
    }

    @Test("the fallback symbol resolves too")
    func fallbackResolves() {
        // The one every unrecognised connector gets. If this is wrong, every
        // app the server adds before the next release renders blank.
        let fallback = AppCatalog.resolve("something-brand-new")
        #expect(NSImage(systemSymbolName: fallback.symbol, accessibilityDescription: nil) != nil)
    }

    @Test("every accent parses as a colour")
    func accentsParse() {
        for app in AppCatalog.builtIn {
            #expect(UInt32(app.accentHex, radix: 16) != nil, "\(app.id): \(app.accentHex)")
            #expect(app.accentHex.count == 6, "\(app.id): \(app.accentHex)")
        }
    }
}
