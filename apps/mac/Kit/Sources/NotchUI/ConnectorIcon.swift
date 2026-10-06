import AppKit
import MetricsCore
import SwiftUI

/// A connector's mark: the vendor's logo, in white, on a tile of its brand
/// colour.
///
/// The marks are vendored from simple-icons by `scripts/sync-connector-icons.mjs`
/// and committed into the asset catalogue rather than fetched from the assets
/// host. A logo that arrives over the network makes the Integrations pane a
/// column of grey boxes on a bad connection, and recognising a logo is the
/// entire job of this view.
///
/// Four connectors have no mark in simple-icons and fall back to their SF
/// Symbol. That is why the fallback renders in the same white-on-brand tile:
/// the row should look deliberate, not broken.
public struct ConnectorIcon: View {
    public let app: MetricApp
    public var size: CGFloat
    /// Dimmed for connectors that cannot be connected yet.
    public var isEnabled: Bool

    public init(app: MetricApp, size: CGFloat = 28, isEnabled: Bool = true) {
        self.app = app
        self.size = size
        self.isEnabled = isEnabled
    }

    /// Looked up in the main bundle because the catalogue belongs to the app
    /// target, not to this package.
    private var mark: NSImage? { NSImage(named: "connector-\(app.id)") }

    private var tile: Color { NotchTheme.tileFill(for: app) }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(tile)
            .overlay(glyph)
            .overlay(
                // A hairline so a tile whose brand colour is close to the
                // window's own still has an edge.
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .frame(width: size, height: size)
            .opacity(isEnabled ? 1 : 0.45)
            .saturation(isEnabled ? 1 : 0.4)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        if let mark {
            Image(nsImage: mark)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.54, height: size * 0.54)
        } else {
            Image(systemName: app.symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
