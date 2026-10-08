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
    /// Artwork that already is the tile, so it is drawn to the edges.
    private var isFullBleed: Bool { mark != nil && ConnectorMarks.fullBleed.contains(app.id) }

    /// The tile behind the mark.
    ///
    /// Frosted glass for the marks drawn against a light background, rather
    /// than the near-white square they used to sit on. A row of white tiles in
    /// a dark panel reads as a line of headlights, and glass keeps them part
    /// of the same surface as everything around them.
    @ViewBuilder
    private var tileBackground: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        if usesLightTile {
            shape.fill(.ultraThinMaterial)
        } else {
            shape.fill(tile)
        }
    }

    private var tile: Color {
        // The luminance floor keeps a *white glyph* legible. A mark with its
        // own colours does not need it, and lifting Dodo Payments' black to
        // grey only makes the tile look washed out behind its lime.
        if ConnectorMarks.ownColour.contains(app.id) {
            return Color(hex: app.accentHex) ?? NotchTheme.tileFill(for: app)
        }
        return NotchTheme.tileFill(for: app)
    }

    public var body: some View {
        tileBackground
            .overlay(glyph)
            // Clipped here rather than on the glyph alone, so a full-bleed
            // mark takes the tile's corners instead of squaring them off.
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .overlay(
                // A hairline so a tile whose brand colour is close to the
                // window's own still has an edge.
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(Color.white.opacity(usesLightTile ? 0.16 : 0.12), lineWidth: 1)
            )
            .frame(width: size, height: size)
            .opacity(isEnabled ? 1 : 0.45)
            .saturation(isEnabled ? 1 : 0.4)
            .accessibilityHidden(true)
    }

    /// A white silhouette of the mark.
    ///
    /// Marks drawn for a light background have no contrast on glass as they
    /// are — Dodo's black, GitHub's black, Analytics' amber all vanish. Drawn
    /// as a template they take the foreground colour instead. `isTemplate` is
    /// set on a *copy*: the shared image from the catalogue is handed to every
    /// other caller too.
    private var templateMark: NSImage? {
        guard let copy = mark?.copy() as? NSImage else { return nil }
        copy.isTemplate = true
        return copy
    }

    @ViewBuilder
    private var glyph: some View {
        if usesLightTile, let mark = templateMark {
            Image(nsImage: mark)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: size * 0.6, height: size * 0.6)
        } else if let mark {
            Image(nsImage: mark)
                .resizable()
                .scaledToFit()
                // Full-colour marks carry their own padding in the artwork, so
                // they need less inset than a simple-icons glyph that bleeds
                // to its viewBox. A full-bleed mark carries the tile too.
                .frame(
                    width: size * (isFullBleed ? 1 : usesLightTile ? 0.62 : 0.54),
                    height: size * (isFullBleed ? 1 : usesLightTile ? 0.62 : 0.54))
        } else {
            Image(systemName: app.symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
