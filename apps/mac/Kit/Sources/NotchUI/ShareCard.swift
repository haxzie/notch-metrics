import AppKit
import MetricsCore
import SwiftUI

/// Everything the share editor needs about one tile, taken at the moment the
/// share button was pressed.
///
/// A snapshot rather than a live reference into the notch's view model. The
/// editor is a picture of a number at a point in time: if the poll landed
/// while somebody was picking a background, the figure they had framed would
/// change under them — and the file they saved would not be the one they were
/// looking at.
public struct ShareRequest: Identifiable, Sendable {
    public let widget: NotchWidget
    public let app: MetricApp
    public let state: TileState
    public let connectionName: String?
    public let showsRange: Bool

    public var id: String { widget.id }

    public init(
        widget: NotchWidget, app: MetricApp, state: TileState,
        connectionName: String? = nil, showsRange: Bool = false
    ) {
        self.widget = widget
        self.app = app
        self.state = state
        self.connectionName = connectionName
        self.showsRange = showsRange
    }
}

/// An output size, named for where it is going.
///
/// Pixels, not points: these are the numbers the platforms document, and the
/// one thing somebody exporting for a story needs to be able to check.
public struct ShareFrame: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Where this size is for. Shown under the name, because "1080 × 1350" is
    /// not what anybody is actually choosing between.
    public let detail: String
    public let pixels: CGSize

    /// The card is laid out at half its pixel size and rendered at 2x, so one
    /// set of proportions serves both the preview and the file. Deriving the
    /// layout from the output rather than the other way round is what keeps
    /// the two from drifting.
    public var layoutSize: CGSize {
        CGSize(width: pixels.width / Self.renderScale, height: pixels.height / Self.renderScale)
    }

    public static let renderScale: CGFloat = 2

    public static let square = ShareFrame(
        id: "square", name: "Square", detail: "Instagram post",
        pixels: CGSize(width: 1080, height: 1080))
    public static let portrait = ShareFrame(
        id: "portrait", name: "Portrait", detail: "Instagram 4:5",
        pixels: CGSize(width: 1080, height: 1350))
    public static let story = ShareFrame(
        id: "story", name: "Story", detail: "Reels, TikTok",
        pixels: CGSize(width: 1080, height: 1920))
    public static let post = ShareFrame(
        id: "post", name: "Post", detail: "X, LinkedIn",
        pixels: CGSize(width: 1200, height: 675))
    public static let landscape = ShareFrame(
        id: "landscape", name: "Landscape", detail: "YouTube, slides",
        pixels: CGSize(width: 1920, height: 1080))

    public static let presets: [ShareFrame] = [.square, .portrait, .story, .post, .landscape]
}

/// What sits behind the tile.
///
/// Mostly pictures, and all of them dark. Two flat gradients looked like a
/// settings page rather than something anybody would post, and a light
/// background under a dark plate reads as a mistake — the plate is there
/// because `WidgetTile` is built for a dark surface, so the card is always
/// going to be dark in the middle and a pale frame fights it.
///
/// The pictures are the ones the Prequel editor offers behind a recording,
/// re-encoded here at 2200px — wide enough for the largest frame, a quarter
/// of the file size.
public struct ShareBackground: Identifiable, Hashable, Sendable {
    /// A gradient drawn from stops, or a picture from the app's asset
    /// catalogue. Two cases rather than two types, so the picker, the swatch
    /// and the card each handle "a background" once.
    public enum Fill: Hashable, Sendable {
        case gradient([Color])
        /// An image set in the main bundle. Looked up by name for the same
        /// reason `ConnectorIcon` does it: the catalogue belongs to the app
        /// target, not to this package.
        case asset(String)
    }

    public let id: String
    public let name: String
    public let fill: Fill

    public static let presets: [ShareBackground] = [
        ShareBackground(
            id: "brand", name: "Brand",
            fill: .gradient([NotchTheme.gradientStart, NotchTheme.gradientEnd])),
        ShareBackground(
            id: "ink", name: "Ink", fill: .gradient([hex(0x0A_0A_0C), hex(0x1C_1C_20)])),
        ShareBackground(id: "dune", name: "Dune", fill: .asset("share-bg-dune")),
        ShareBackground(id: "monterey", name: "Monterey", fill: .asset("share-bg-monterey")),
        ShareBackground(id: "facet", name: "Facet", fill: .asset("share-bg-facet")),
        ShareBackground(id: "indigo", name: "Indigo", fill: .asset("share-bg-indigo")),
        ShareBackground(id: "cobalt", name: "Cobalt", fill: .asset("share-bg-cobalt")),
        ShareBackground(id: "iris", name: "Iris", fill: .asset("share-bg-iris")),
        ShareBackground(id: "caustic", name: "Caustic", fill: .asset("share-bg-caustic")),
        ShareBackground(id: "ember", name: "Ember", fill: .asset("share-bg-ember")),
    ]

    private static func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

/// A background, filling whatever it is given.
///
/// `scaledToFill` and a clip, so a 3:2 picture behind a 9:16 story crops
/// rather than letterboxing — a black band down the side of an exported card
/// is worse than losing the edge of a gradient nobody is reading.
public struct ShareBackgroundView: View {
    public let background: ShareBackground

    public init(_ background: ShareBackground) {
        self.background = background
    }

    public var body: some View {
        switch background.fill {
        case .gradient(let stops):
            LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
        case .asset(let name):
            if let image = NSImage(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // A missing asset must not export a transparent card. Near
                // black is the right fallback: every picture in the set is
                // dark, so the plate and the signature still read.
                Color(white: 0.06)
            }
        }
    }
}

/// The notch's own cell, for a tile drawn outside the notch.
///
/// A share card has no grid to take its cell size from, so it carries a copy.
/// Fixed rather than derived from the user's screen: the exported image must
/// not come out a different shape on a 14" MacBook than on a 6K display.
public enum ShareTileMetrics {
    static let cellWidth: CGFloat = 128
    // Literals, not reads of `NotchWidgetCanvas` — its statics are isolated to
    // the main actor as a View's are, and this type is used from wherever a
    // card is laid out. Kept equal to the canvas's own 84 and 10 so a tile on
    // a card has the proportions it has in the notch.
    static let rowHeight: CGFloat = 84
    static let spacing: CGFloat = 10

    /// The size the notch would draw this span at — the same proportions, so
    /// the figure, the label and the chart keep the relationship they have on
    /// screen.
    public static func size(for widget: WidgetSize) -> CGSize {
        CGSize(
            width: CGFloat(widget.cols) * cellWidth + CGFloat(widget.cols - 1) * spacing,
            height: CGFloat(widget.rows) * rowHeight + CGFloat(widget.rows - 1) * spacing)
    }

    /// What the size picker offers, widest span last.
    ///
    /// A subset of every span the grid allows. A share card has one tile on
    /// it, so the spans that only matter for packing — 3x1, 5x2 — are noise
    /// in a picker; these five cover a number, a number with a chart, and a
    /// banner.
    public static let large = WidgetSize(cols: 4, rows: 2)
    public static let presets: [WidgetSize] = [.small, .wide, .square, large, .hero]

    public static func label(for size: WidgetSize) -> String {
        if size == .small { return "Small" }
        if size == .wide { return "Wide" }
        if size == .square { return "Square" }
        if size == large { return "Large" }
        if size == .hero { return "Hero" }
        return size.rawValue
    }
}

/// The thing that gets exported: a tile on a background, signed.
///
/// Laid out entirely in fractions of `size`, with no absolute padding
/// anywhere. That is what lets one view serve a 540pt preview and a
/// 1920x1080 PNG — `ImageRenderer` only changes the scale, so a card that
/// looked right on screen cannot come out of the file with the footer in a
/// different place.
public struct ShareCard: View {
    public let request: ShareRequest
    public let widgetSize: WidgetSize
    public let background: ShareBackground
    /// The card's size in points. The export multiplies this by
    /// `ShareFrame.renderScale`.
    public let size: CGSize

    public init(
        request: ShareRequest, widgetSize: WidgetSize, background: ShareBackground, size: CGSize
    ) {
        self.request = request
        self.widgetSize = widgetSize
        self.background = background
        self.size = size
    }

    private var unit: CGFloat { min(size.width, size.height) }

    /// What the tile may occupy. The ceiling on height is the lower of the
    /// two: in a story frame 62% of the height is taller than the tile's own
    /// aspect allows, and letting it grow into that space would blow the
    /// figure up to the width of the card.
    private var allowance: CGSize {
        CGSize(width: size.width * 0.84, height: size.height * 0.62)
    }

    /// How far the tile is scaled from the size the notch draws it at.
    ///
    /// Unclamped upwards on purpose: a 1x1 tile is 128pt wide and would be a
    /// postage stamp in the middle of a 1080px square. Scaling the whole tile
    /// — rather than re-deriving its font sizes — is what keeps the exported
    /// card recognisably the same widget.
    private var tileScale: CGFloat {
        let natural = ShareTileMetrics.size(for: widgetSize)
        return min(allowance.width / natural.width, allowance.height / natural.height)
    }

    public var body: some View {
        let natural = ShareTileMetrics.size(for: widgetSize)
        let scale = tileScale

        ZStack {
            ShareBackgroundView(background)

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // The dark plate under the tile is not decoration. `WidgetTile`
                // fills itself with 5.5% white, which is a tile over the
                // notch's smoked glass and an invisible rectangle over a
                // bright gradient — the figures would be white on yellow. The
                // plate restores the surface the tile was designed against,
                // and happens to make the card read as a piece of the app.
                WidgetTile(
                    widget: tileWidget,
                    app: request.app,
                    state: request.state,
                    connectionName: request.connectionName,
                    showsRange: request.showsRange
                )
                .frame(width: natural.width, height: natural.height)
                .scaleEffect(scale)
                .frame(width: natural.width * scale, height: natural.height * scale)
                .padding(unit * 0.045)
                .background(
                    RoundedRectangle(cornerRadius: unit * 0.055, style: .continuous)
                        .fill(Color.black.opacity(0.58))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: unit * 0.055, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: max(1, unit * 0.0025))
                )
                .shadow(color: .black.opacity(0.32), radius: unit * 0.045, y: unit * 0.016)

                Spacer(minLength: 0)

                signature
                    .padding(.bottom, unit * 0.07)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// The widget as the card draws it, at the size the editor picked.
    ///
    /// The user's own widget is left alone: resizing the tile for a screenshot
    /// must not rearrange the grid they are about to go back to.
    private var tileWidget: NotchWidget {
        var copy = request.widget
        copy.size = widgetSize
        return copy
    }

    private var signature: some View {
        HStack(spacing: unit * 0.018) {
            NotchLogo(size: unit * 0.042)
            Text("Notch Metrics")
                .font(.system(size: unit * 0.032, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
                // Every background in the set is dark, but a photograph is
                // not uniformly dark — the signature sits over whatever the
                // bottom of the picture happens to be, so it carries its own
                // shadow rather than trusting the backdrop.
                .shadow(color: .black.opacity(0.45), radius: unit * 0.012, y: unit * 0.003)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notch Metrics")
    }
}

/// Renders a card to a PNG.
///
/// `ImageRenderer` rather than a bitmap of the on-screen view: the preview is
/// scaled to whatever space the window has, and `cacheDisplay(in:)` would
/// export that size. The renderer draws the card again at the frame's real
/// pixel size, so the file is 1080 wide because it was asked for 1080 — not
/// because the window happened to be.
@MainActor
public enum ShareExport {
    public static func png(
        request: ShareRequest, widgetSize: WidgetSize, background: ShareBackground,
        frame: ShareFrame
    ) -> Data? {
        let card = ShareCard(
            request: request, widgetSize: widgetSize, background: background,
            size: frame.layoutSize)
        let renderer = ImageRenderer(content: card)
        renderer.scale = ShareFrame.renderScale
        // Opaque: a card is a background edge to edge, and an alpha channel
        // on it only costs file size — and trips the "PNG with transparency"
        // warnings some upload flows show.
        renderer.isOpaque = true
        guard let cgImage = renderer.cgImage else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        bitmap.size = frame.pixels
        return bitmap.representation(using: .png, properties: [:])
    }

    /// A filename somebody can find again, derived from what the tile says.
    public static func suggestedName(for request: ShareRequest) -> String {
        let title = request.widget.baseTitle
        let slug =
            "\(request.app.name) \(title)"
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { partial, character in
                // Collapsed rather than left as a run: "notch---mrr.png" looks
                // like a bug in the name, not a name with punctuation in it.
                if character == "-", partial.last == "-" { return }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(slug.isEmpty ? "notch-metric" : slug).png"
    }
}

/// Little pictures for the editor's menus.
///
/// `NSImage`, not a SwiftUI shape. A menu row on macOS is text plus an image
/// and nothing else — a `RoundedRectangle` placed in one is silently dropped,
/// which is why the frame and background menus were three columns of
/// indistinguishable words. Drawing the preview into an image is the only way
/// to get it in front of the choice.
@MainActor
public enum ShareMenuIcon {
    /// An empty rectangle in the frame's own proportions. Template, so it
    /// picks up the menu's text colour and stays legible when a row is
    /// highlighted.
    public static func aspect(_ frame: ShareFrame) -> NSImage {
        let box = CGSize(width: 16, height: 16)
        let longest = max(frame.pixels.width, frame.pixels.height)
        let size = CGSize(
            width: 13 * frame.pixels.width / longest,
            height: 13 * frame.pixels.height / longest)
        let image = NSImage(size: box, flipped: false) { _ in
            let rect = CGRect(
                x: (box.width - size.width) / 2, y: (box.height - size.height) / 2,
                width: size.width, height: size.height)
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.6, dy: 0.6), xRadius: 2, yRadius: 2)
            path.lineWidth = 1.2
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// A filled block in the span's proportions, on the same 6x2 footing the
    /// grid uses — so Wide and Hero are told apart by shape rather than by
    /// reading "2x1" and "6x2".
    public static func span(_ size: WidgetSize) -> NSImage {
        // A box wide enough for the widest span. Square cells rather than the
        // grid's 128x84 ones: at a 16pt icon the real proportions made a 1x1
        // a speck and a 2x2 a vertical sliver, and telling the five apart
        // matters more here than reproducing the cell's aspect.
        let box = CGSize(width: 21, height: 14)
        let cell: CGFloat = 2.6
        let gap: CGFloat = 0.9
        let width = CGFloat(size.cols) * cell + CGFloat(size.cols - 1) * gap
        let height = CGFloat(size.rows) * cell + CGFloat(size.rows - 1) * gap
        let image = NSImage(size: box, flipped: false) { _ in
            let rect = CGRect(
                x: (box.width - width) / 2, y: (box.height - height) / 2,
                width: width, height: height)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The background itself, as it will appear behind the card. Not a
    /// template: the colour *is* the information.
    public static func swatch(_ background: ShareBackground) -> NSImage {
        let box = CGSize(width: 18, height: 14)
        let source: NSImage? = {
            if case .asset(let name) = background.fill { return NSImage(named: name) }
            return nil
        }()
        let stops: [NSColor] = {
            if case .gradient(let colours) = background.fill { return colours.map { NSColor($0) } }
            return []
        }()
        return NSImage(size: box, flipped: false) { _ in
            let rect = CGRect(origin: .zero, size: box).insetBy(dx: 0.5, dy: 0.5)
            let clip = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            clip.addClip()
            if let source {
                // Centre-cropped, like the card does it, so the swatch is a
                // sample of what you will actually get rather than the
                // picture squashed to a different shape.
                let scale = max(rect.width / source.size.width, rect.height / source.size.height)
                let drawn = CGSize(
                    width: source.size.width * scale, height: source.size.height * scale)
                source.draw(
                    in: CGRect(
                        x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                        width: drawn.width, height: drawn.height))
            } else {
                NSGradient(colors: stops)?.draw(in: rect, angle: -45)
            }
            NSColor.white.withAlphaComponent(0.25).setStroke()
            clip.lineWidth = 1
            clip.stroke()
            return true
        }
    }
}
