import AppKit
import MetricsCore
import SwiftUI

/// A connector's mark, on a tile.
///
/// Three treatments, because the marks come from two sources and each is
/// designed for a different background:
///
/// - A **monochrome** mark drawn for a light background (GitHub) is drawn
///   as a white silhouette on frosted glass. It loses nothing, and a row of
///   near-white squares in a dark panel reads as headlights.
/// - A **multicolour** mark drawn for a light background (Google Analytics,
///   Search Console) keeps a near-white tile and its own colours. Flattening
///   Analytics' two ambers to white turns it into a generic bar chart — which
///   is what happened when these briefly shared GitHub's treatment.
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
    /// An icon shipped by a **custom app**, read from its own directory.
    ///
    /// The asset catalogue is committed at build time, so a connector we ship
    /// has its mark compiled in — and an app written on the user's machine
    /// last night cannot possibly be in there. Without this, every custom app
    /// everywhere drew the generic `{}` however good an icon it shipped.
    public var fileURL: URL?

    public init(
        app: MetricApp, size: CGFloat = 28, isEnabled: Bool = true, fileURL: URL? = nil
    ) {
        self.app = app
        self.size = size
        self.isEnabled = isEnabled
        self.fileURL = fileURL
    }

    /// Looked up in the main bundle because the catalogue belongs to the app
    /// target, not to this package — or loaded from disk for a custom app.
    ///
    /// `ConnectorMarks` is keyed by the ids we ship, so a file-backed mark
    /// matches none of the treatments below and lands in the default one: its
    /// own colours on the app's accent tile, which is what an author who
    /// supplied a square icon expects.
    private var mark: NSImage? {
        if let url = fileURL ?? app.customIconFile { return Self.cached(url) }
        // A borrowed mark is looked up by the app it names, not by the custom
        // app's own id — which has no mark and never will.
        if let borrowed = declared?.borrowedAppId {
            return NSImage(named: "connector-\(borrowed)")
        }
        return NSImage(named: "connector-\(app.id)")
    }

    /// The app a borrowed mark belongs to, for its treatment and its colour.
    ///
    /// `ConnectorMarks` is keyed by the ids we ship, so a borrowed mark has to
    /// be looked up under *that* id or it lands in the wrong treatment —
    /// GitHub's black silhouette drawn in colour on a dark tile, say.
    private var borrowedApp: MetricApp? {
        declared?.borrowedAppId.map { AppCatalog.resolve($0) }
    }

    /// What a custom app declared, if this is one.
    ///
    /// An `unknown` arm — a manifest from a newer core — is treated as no icon
    /// at all, which falls through to the generic Custom mark rather than
    /// drawing a blank tile.
    private var declared: CustomAppIcon? {
        guard let icon = app.customIcon, icon != .unknown else { return nil }
        return icon
    }

    /// Whether this is drawing an author-supplied image rather than a mark we
    /// ship. Both treatments below branch on it.
    private var isFileBacked: Bool { fileURL != nil || app.customIconFile != nil }

    /// Which id the mark treatments are keyed by.
    private var markId: String { borrowedApp?.id ?? app.id }

    /// The tile colour an author asked for, when they asked for one.
    private var declaredTint: Color? {
        guard case let .symbol(_, tint) = declared, let tint else { return nil }
        return Color(hex: tint)
    }

    /// Decoded once per path.
    ///
    /// SwiftUI rebuilds a row on every hover and every scroll tick, and
    /// decoding a PNG off disk on each of those made the gallery stutter with
    /// a handful of custom apps in it.
    private static func cached(_ url: URL) -> NSImage? {
        if let hit = iconCache.object(forKey: url.path as NSString) { return hit }
        guard let image = NSImage(contentsOf: url) else { return nil }
        iconCache.setObject(image, forKey: url.path as NSString)
        return image
    }

    private static let iconCache = NSCache<NSString, NSImage>()

    private var usesLightTile: Bool {
        !isFileBacked && ConnectorMarks.lightTile.contains(markId)
    }
    /// Silhouetted on glass rather than drawn in colour on a light tile.
    private var usesTemplate: Bool {
        usesLightTile && ConnectorMarks.monochrome.contains(markId)
    }
    /// Artwork that already is the tile, so it is drawn to the edges.
    /// A custom app's icon is drawn to the edges: it is a square image the
    /// author chose, not a glyph meant to sit inside a brand tile.
    private var isFullBleed: Bool {
        guard mark != nil else { return false }
        return isFileBacked || ConnectorMarks.fullBleed.contains(markId)
    }

    /// The tile behind the mark.
    ///
    /// Frosted glass for a silhouetted mark, so it stays part of the same
    /// surface as everything around it. A colour mark drawn for light gets
    /// the near-white its artwork assumes — not pure white, which is brighter
    /// than anything else in the panel.
    @ViewBuilder
    private var tileBackground: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        if usesTemplate {
            shape.fill(.ultraThinMaterial)
        } else if usesLightTile {
            shape.fill(Color(white: 0.96))
        } else {
            shape.fill(tile)
        }
    }

    private var tile: Color {
        // The luminance floor keeps a *white glyph* legible. A mark with its
        // own colours does not need it, and lifting Dodo Payments' black to
        // grey only makes the tile look washed out behind its lime.
        if let declaredTint { return declaredTint }
        // A borrowed mark brings its own colour: that is most of the point of
        // borrowing it, and a Claude logo on the generic magenta would look
        // like neither.
        if let borrowedApp {
            return Color(hex: borrowedApp.accentHex) ?? NotchTheme.tileFill(for: borrowedApp)
        }
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
                    .strokeBorder(Color.white.opacity(usesTemplate ? 0.16 : 0.12), lineWidth: 1)
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
        if usesTemplate, let mark = templateMark {
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
        } else if case let .emoji(value) = declared {
            // Sized against the tile rather than set in points, so it matches
            // a symbol at every call site from 16pt to the share card's 60.
            Text(value)
                .font(.system(size: size * 0.56))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        } else if case let .symbol(name, _) = declared, Self.symbolExists(name) {
            Image(systemName: name)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        } else {
            // The app's own symbol: `curlybraces` for a custom app, whatever
            // the catalogue says otherwise. Reached when a manifest names a
            // symbol this version of macOS does not have, which is why the
            // name is checked rather than trusted.
            Image(systemName: app.symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    /// Whether this macOS has the named symbol.
    ///
    /// `Image(systemName:)` renders *nothing* for a name it does not know —
    /// no placeholder, no warning — so a manifest naming a symbol added in a
    /// later macOS would draw an empty tile. Checked through AppKit, which
    /// does report the miss, and cached because the answer cannot change
    /// while the app is running.
    private static func symbolExists(_ name: String) -> Bool {
        if let known = symbolCache.object(forKey: name as NSString) { return known.boolValue }
        let exists = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        symbolCache.setObject(NSNumber(value: exists), forKey: name as NSString)
        return exists
    }

    private static let symbolCache = NSCache<NSString, NSNumber>()
}
