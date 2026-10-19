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
    /// Which set it belongs to. The picker groups by this — twenty pictures
    /// in one flat menu is a scroll, not a choice.
    public let category: String
    public let fill: Fill

    /// The sets, in the order the picker lists them.
    public struct Group: Identifiable, Hashable, Sendable {
        public let id: String
        public let label: String
        public let backgrounds: [ShareBackground]
    }

    public static let groups: [Group] = [
        Group(id: "aurora", label: "Aurora", backgrounds: aurora),
        Group(id: "haze", label: "Haze", backgrounds: haze),
        Group(id: "anime", label: "Anime", backgrounds: anime),
    ]

    public static let presets: [ShareBackground] = groups.flatMap(\.backgrounds)

    /// What the editor opens on. Named rather than `presets[0]`, so adding a
    /// set or reordering the list cannot silently change what every share
    /// starts as.
    public static let initial: ShareBackground = aurora[0]

    static let aurora: [ShareBackground] = [
        ShareBackground(
            id: "aurora-aurora", name: "Aurora", category: "aurora",
            fill: .asset("share-bg-aurora-aurora")),
        ShareBackground(
            id: "aurora-blush", name: "Blush", category: "aurora",
            fill: .asset("share-bg-aurora-blush")),
        ShareBackground(
            id: "aurora-cobalt", name: "Cobalt", category: "aurora",
            fill: .asset("share-bg-aurora-cobalt")),
        ShareBackground(
            id: "aurora-dusk", name: "Dusk", category: "aurora",
            fill: .asset("share-bg-aurora-dusk")),
        ShareBackground(
            id: "aurora-ember", name: "Ember", category: "aurora",
            fill: .asset("share-bg-aurora-ember")),
        ShareBackground(
            id: "aurora-indigo", name: "Indigo", category: "aurora",
            fill: .asset("share-bg-aurora-indigo")),
        ShareBackground(
            id: "aurora-iris", name: "Iris", category: "aurora",
            fill: .asset("share-bg-aurora-iris")),
        ShareBackground(
            id: "aurora-lilac", name: "Lilac", category: "aurora",
            fill: .asset("share-bg-aurora-lilac")),
        ShareBackground(
            id: "aurora-nebula", name: "Nebula", category: "aurora",
            fill: .asset("share-bg-aurora-nebula")),
        ShareBackground(
            id: "aurora-sage", name: "Sage", category: "aurora",
            fill: .asset("share-bg-aurora-sage")),
    ]

    /// The horizon set.
    ///
    /// A band of light across a dark field, which is the one shape that puts
    /// the bright part of the picture *below* the tile rather than behind
    /// it. The plate lands on the dark half and the signature sits in the
    /// glow, with no wallpaper needing to be dimmed to make either legible.
    static let haze: [ShareBackground] = [
        ShareBackground(
            id: "haze-amber", name: "Amber", category: "haze",
            fill: .asset("share-bg-haze-amber")),
        ShareBackground(
            id: "haze-amethyst", name: "Amethyst", category: "haze",
            fill: .asset("share-bg-haze-amethyst")),
        ShareBackground(
            id: "haze-citrus", name: "Citrus", category: "haze",
            fill: .asset("share-bg-haze-citrus")),
        ShareBackground(
            id: "haze-fuchsia", name: "Fuchsia", category: "haze",
            fill: .asset("share-bg-haze-fuchsia")),
        ShareBackground(
            id: "haze-harvest", name: "Harvest", category: "haze",
            fill: .asset("share-bg-haze-harvest")),
        ShareBackground(
            id: "haze-heather", name: "Heather", category: "haze",
            fill: .asset("share-bg-haze-heather")),
        ShareBackground(
            id: "haze-marigold", name: "Marigold", category: "haze",
            fill: .asset("share-bg-haze-marigold")),
        ShareBackground(
            id: "haze-nightfall", name: "Nightfall", category: "haze",
            fill: .asset("share-bg-haze-nightfall")),
        ShareBackground(
            id: "haze-smoke", name: "Smoke", category: "haze",
            fill: .asset("share-bg-haze-smoke")),
        ShareBackground(
            id: "haze-solstice", name: "Solstice", category: "haze",
            fill: .asset("share-bg-haze-solstice")),
    ]

    static let anime: [ShareBackground] = [
        ShareBackground(
            id: "anime-bloom", name: "Bloom", category: "anime",
            fill: .asset("share-bg-anime-bloom")),
        ShareBackground(
            id: "anime-blossom", name: "Blossom", category: "anime",
            fill: .asset("share-bg-anime-blossom")),
        ShareBackground(
            id: "anime-cumulus", name: "Cumulus", category: "anime",
            fill: .asset("share-bg-anime-cumulus")),
        ShareBackground(
            id: "anime-daybreak", name: "Daybreak", category: "anime",
            fill: .asset("share-bg-anime-daybreak")),
        ShareBackground(
            id: "anime-monsoon", name: "Monsoon", category: "anime",
            fill: .asset("share-bg-anime-monsoon")),
        ShareBackground(
            id: "anime-skyline", name: "Skyline", category: "anime",
            fill: .asset("share-bg-anime-skyline")),
        ShareBackground(
            id: "anime-stardust", name: "Stardust", category: "anime",
            fill: .asset("share-bg-anime-stardust")),
        ShareBackground(
            id: "anime-summit", name: "Summit", category: "anime",
            fill: .asset("share-bg-anime-summit")),
    ]
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
    /// The chart the card draws, when it is not the widget's own. The user's
    /// widget is never touched — see `tileWidget`.
    public let chart: ChartKind?
    /// The card's size in points. The export multiplies this by
    /// `ShareFrame.renderScale`.
    public let size: CGSize

    public init(
        request: ShareRequest, widgetSize: WidgetSize, background: ShareBackground,
        chart: ChartKind? = nil, size: CGSize
    ) {
        self.request = request
        self.widgetSize = widgetSize
        self.background = background
        self.chart = chart
        self.size = size
    }

    /// The one span every card is drawn at.
    ///
    /// Fixed rather than offered. A share card holds a single tile with
    /// nothing to pack around it, so the span is a composition decision, not
    /// the user's: 2x2 is the only one that fits a figure, a label and a
    /// chart at a size worth posting. A 1x1 came out a stamp in the middle
    /// of a 1080px square and a 6x2 left a letterbox of wallpaper above and
    /// below it.
    public static let cardSpan: WidgetSize = .square

    private var unit: CGFloat { min(size.width, size.height) }

    /// What the tile may occupy. The ceiling on height is the lower of the
    /// two: in a story frame 62% of the height is taller than the tile's own
    /// aspect allows, and letting it grow into that space would blow the
    /// figure up to the width of the card.
    private var allowance: CGSize {
        CGSize(width: size.width * 0.68, height: size.height * 0.5)
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
        let plate = CGSize(width: natural.width * scale, height: natural.height * scale)
        let radius = tileCornerRadius * scale

        // Three layers: the picture, the same picture blurred and showing
        // only through the plates, then the content.
        //
        // The blurred copy is what makes the plates glass. `.ultraThinMaterial`
        // cannot do it here — a real material samples the *window* behind it,
        // and `ImageRenderer` does not draw one at all, so the exported card
        // had flat black rectangles where the frost was supposed to be. A
        // second copy of the background, blurred and masked to the plates,
        // is the same effect built out of things the renderer does draw.
        //
        // Both copies are given the card's frame and clipped *inside* the
        // stack. A ZStack takes the size of its largest child, and a `.fill`
        // image reports a size larger than the card in whichever axis its
        // aspect ratio overflows — left to itself the stack grew past the
        // card and pushed the signature below the crop, on those wallpapers
        // and no others. Clipped to the card first, neither copy can move
        // anything.
        ZStack {
            backdrop

            backdrop
                .blur(radius: unit * 0.05)
                .mask(frost(plate: plate, radius: radius))

            layout(
                tile: WidgetTile(
                    widget: tileWidget,
                    app: request.app,
                    state: request.state,
                    connectionName: request.connectionName,
                    showsRange: request.showsRange
                )
                .frame(width: natural.width, height: natural.height)
                .scaleEffect(scale)
                .frame(width: plate.width, height: plate.height)
                // The tint sits *behind the tile itself*, at the tile's own
                // shape, rather than on a second rounded plate around it. It
                // is not decoration: `WidgetTile` fills itself with 5.5%
                // white, which is a tile over the notch's smoked glass and an
                // invisible rectangle over a bright gradient — the figures
                // would be white on yellow. Over the blurred copy it is the
                // tint half of the glass, dark enough that a pale wallpaper
                // cannot wash the figure out.
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color.black.opacity(0.62))
                )
                .overlay(
                    // The lip a real material has. Without it the plate's
                    // edge disappears wherever the blur behind it happens to
                    // match the picture around it.
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: max(1, unit * 0.0022))
                )
                .shadow(color: .black.opacity(0.38), radius: unit * 0.04, y: unit * 0.014),
                signature: signature)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// The picture, sized and cropped to the card.
    private var backdrop: some View {
        ShareBackgroundView(background)
            .frame(width: size.width, height: size.height)
            .clipped()
    }

    /// Where the card is glass, in white on nothing.
    ///
    /// Built from the same `layout` as the content, so the holes are the
    /// plates — not a second set of coordinates that has to be kept in step
    /// with the first. `hidden()` keeps the signature's size and draws none
    /// of it, which is exactly what a mask wants: the capsule behind it is
    /// the shape, the words inside it are not.
    private func frost(plate: CGSize, radius: CGFloat) -> some View {
        layout(
            tile: RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white)
                .frame(width: plate.width, height: plate.height),
            signature: signatureContent
                .hidden()
                .padding(.horizontal, unit * 0.038)
                .padding(.vertical, unit * 0.022)
                .background(Capsule().fill(Color.white)))
    }

    /// Where the tile and the signature sit on the card.
    ///
    /// One function, used by the content and by the mask that frosts it. Two
    /// copies of this arithmetic is how a blurred patch ends up a few points
    /// below the plate it belongs to.
    private func layout(tile: some View, signature: some View) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            tile
            Spacer(minLength: 0)
            signature
                .padding(.bottom, unit * 0.07)
        }
        .frame(width: size.width, height: size.height)
    }

    /// `WidgetTile`'s own corner radius, which the surface behind it has to
    /// match exactly or the dark shows as a lip around two of the corners.
    /// A literal for the same reason `ShareTileMetrics` uses them — the tile's
    /// are private — and the tile is scaled, so this is too.
    private var tileCornerRadius: CGFloat {
        widgetSize.cols == 1 && widgetSize.rows == 1 ? 12 : 16
    }

    /// The widget as the card draws it, at the size and chart the editor
    /// picked.
    ///
    /// The user's own widget is left alone: resizing the tile for a
    /// screenshot, or drawing it as bars for one, must not change the grid
    /// they are about to go back to.
    private var tileWidget: NotchWidget {
        var copy = request.widget
        copy.size = widgetSize
        if let chart { copy.chart = chart }
        return copy
    }

    /// The two credits, with no pill around them.
    ///
    /// Separate from `signature` so the frost mask can lay out the same
    /// content hidden and take the capsule's size from it, rather than
    /// guessing at a height.
    private var signatureContent: some View {
        HStack(spacing: unit * 0.026) {
            HStack(spacing: unit * 0.018) {
                ConnectorIcon(app: request.app, size: unit * 0.042)
                Text(request.app.name)
                    .font(.system(size: unit * 0.032, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
            }

            // A hairline, not a bullet or a dash: the two marks are both
            // logo-plus-name, and without a rule between them the eye reads
            // four things in a row rather than two credits.
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: max(1, unit * 0.0022), height: unit * 0.042)

            HStack(spacing: unit * 0.018) {
                NotchLogo(size: unit * 0.042)
                Text("Notch Metrics")
                    .font(.system(size: unit * 0.032, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
        }
    }

    private var signature: some View {
        signatureContent
            .padding(.horizontal, unit * 0.038)
            .padding(.vertical, unit * 0.022)
            // The tint over the blurred copy the mask lets through here. Not
            // `.ultraThinMaterial`: a real material samples the *window*
            // behind it and `ImageRenderer` does not draw one at all, so the
            // exported pill came out as a hole.
            .background(Capsule().fill(Color.black.opacity(0.42)))
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: max(1, unit * 0.0022))
            )
            // A photograph is not uniformly dark, and the signature sits over
            // whatever the bottom of the picture happens to be.
            .shadow(color: .black.opacity(0.3), radius: unit * 0.02, y: unit * 0.006)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(request.app.name), Notch Metrics")
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
        chart: ChartKind? = nil, frame: ShareFrame
    ) -> Data? {
        let card = ShareCard(
            request: request, widgetSize: widgetSize, background: background, chart: chart,
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

    /// The background itself, as it will appear behind the card. Not a
    /// template: the colour *is* the information.
    /// The chart choice, as the system's own glyph. Unlike the other three
    /// this needs no drawing — "a line", "bars" and "no chart" are exactly
    /// what SF Symbols is for.
    public static func chart(_ kind: ChartKind) -> NSImage {
        let name: String
        switch kind {
        case .none: name = "number"
        case .sparkline: name = "chart.xyaxis.line"
        case .bars: name = "chart.bar.fill"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        return image
    }

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
