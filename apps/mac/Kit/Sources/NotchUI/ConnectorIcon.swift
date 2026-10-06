import AppKit
import MetricsCore
import SwiftUI

/// A connector's mark, on a tile.
///
/// Two treatments, because the marks come from two sources and each is
/// designed for a different background:
///
/// - A **full-colour** official mark (Google Analytics, Search Console)
///   renders at its own colours on a near-white tile. These logos are drawn
///   for a white page, and flattening Analytics' amber to white turns it into
///   a generic bar chart.
/// - A **monochrome** simple-icons glyph renders white on a tile of the
///   brand's colour, which is the treatment those are drawn for.
///
/// `ConnectorMarks.fullColour` is generated alongside the assets, so adding
/// an override cannot leave this rendering it the wrong way.
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

    private var isFullColour: Bool { ConnectorMarks.fullColour.contains(app.id) }

    private var tile: Color {
        // Not pure white: a hard #FFF square is brighter than anything else in
        // a dark window and the row reads as a line of headlights.
        isFullColour ? Color(white: 0.96) : NotchTheme.tileFill(for: app)
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(tile)
            .overlay(glyph)
            .overlay(
                // A hairline so a tile whose brand colour is close to the
                // window's own still has an edge.
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .strokeBorder(Color.white.opacity(isFullColour ? 0.3 : 0.12), lineWidth: 1)
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
                .frame(width: size * (isFullColour ? 0.62 : 0.54),
                       height: size * (isFullColour ? 0.62 : 0.54))
        } else {
            Image(systemName: app.symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
