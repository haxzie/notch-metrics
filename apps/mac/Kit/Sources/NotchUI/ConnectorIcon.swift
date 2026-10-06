import AppKit
import MetricsCore
import SwiftUI

/// A connector's mark, on a tile.
///
/// Two treatments, because the marks come from two sources and each is
/// designed for a different background:
///
/// - A mark drawn for a **light** background (Google Analytics, Search
///   Console, GitHub) gets a near-white tile. Flattening Analytics' amber to
///   white turns it into a generic bar chart.
/// - Everything else sits on a tile of the brand's own colour: either a white
///   simple-icons glyph, or an official mark drawn for dark — Dodo Payments'
///   lime would disappear on white.
///
/// `ConnectorMarks.lightTile` is generated alongside the assets, so adding an
/// override cannot leave this rendering it the wrong way.
///
/// Committed into the asset catalogue rather than fetched from the assets
/// host: a logo arriving over the network makes the Integrations pane a
/// column of grey boxes on a bad connection, and recognising a logo is the
/// entire job of this view.
///
/// A connector with no mark falls back to its SF Symbol, in the white-on-brand
/// treatment, so the row still looks deliberate rather than broken.
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

    private var usesLightTile: Bool { ConnectorMarks.lightTile.contains(app.id) }

    private var tile: Color {
        // Not pure white: a hard #FFF square is brighter than anything else in
        // a dark window and the row reads as a line of headlights.
        if usesLightTile { return Color(white: 0.96) }
        // The luminance floor keeps a *white glyph* legible. A mark with its
        // own colours does not need it, and lifting Dodo Payments' black to
        // grey only makes the tile look washed out behind its lime.
        if ConnectorMarks.ownColour.contains(app.id) {
            return Color(hex: app.accentHex) ?? NotchTheme.tileFill(for: app)
        }
        return NotchTheme.tileFill(for: app)
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(tile)
            .overlay(glyph)
            .overlay(
                // A hairline so a tile whose brand colour is close to the
                // window's own still has an edge.
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(Color.white.opacity(usesLightTile ? 0.3 : 0.12), lineWidth: 1)
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
                // Full-colour marks carry their own padding in the artwork, so
                // they need less inset than a simple-icons glyph that bleeds
                // to its viewBox.
                .frame(width: size * (usesLightTile ? 0.62 : 0.54),
                       height: size * (usesLightTile ? 0.62 : 0.54))
        } else {
            Image(systemName: app.symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
