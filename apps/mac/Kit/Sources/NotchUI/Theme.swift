import SwiftUI

/// The brand gradient, taken from the app icon.
public enum NotchTheme {
    public static let gradientStart = Color(red: 0xD8 / 255, green: 0x19 / 255, blue: 0xC2 / 255)
    public static let gradientEnd = Color(red: 0xFF / 255, green: 0xC1 / 255, blue: 0x07 / 255)

    public static let brand = LinearGradient(
        colors: [gradientStart, gradientEnd], startPoint: .bottomLeading, endPoint: .topTrailing)

    /// A dark tint laid over the system material.
    ///
    /// The panel is frosted glass rather than flat black: it hangs off the
    /// bezel and should pick up what is behind it the way every other macOS
    /// surface does. But `.ultraThinMaterial` alone goes milky over a bright
    /// wallpaper and the white figures stop being legible, so a dark tint sits
    /// on top of it — enough to hold contrast, little enough to still read as
    /// glass.
    public static let surfaceTint = Color.black.opacity(0.55)
    public static let surfaceMaterial: Material = .ultraThinMaterial

    /// Tile fill and borders. Hairlines, because at this size a 1pt border at
    /// any real opacity reads as a box rather than an edge.
    public static let tileFill = Color.white.opacity(0.055)
    public static let tileStroke = Color.white.opacity(0.09)
    public static let panelStroke = Color.white.opacity(0.14)

    public static let primaryText = Color.white
    public static let secondaryText = Color.white.opacity(0.62)
    public static let tertiaryText = Color.white.opacity(0.38)
    public static let positive = Color(red: 0.26, green: 0.84, blue: 0.52)
    public static let negative = Color(red: 1.0, green: 0.38, blue: 0.38)

    /// Edit mode.
    ///
    /// The dotted grid is the only thing that tells a user the tiles snap, and
    /// the blue is macOS's own selection colour rather than a brand one — a
    /// drag target that uses the brand gradient reads as decoration, where
    /// system blue reads as "this is where it will go".
    public static let editDot = Color.white.opacity(0.22)
    public static let editHighlight = Color(nsColor: .systemBlue)

    /// Tints a tile from its index so a row is distinguishable at a glance
    /// without anybody having to choose colours.
    public static func accent(for index: Int) -> Color {
        let stops: [Color] = [
            gradientStart,
            Color(red: 0xF0 / 255, green: 0x4E / 255, blue: 0x8E / 255),
            Color(red: 0xF7 / 255, green: 0x7F / 255, blue: 0x4A / 255),
            gradientEnd,
        ]
        return stops[index % stops.count]
    }
}

/// Respects Reduce Motion, which matters more here than in most apps: the
/// notch expands under the pointer, unprompted, several times an hour.
public enum NotchMotion {
    public static func expansion(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.34, dampingFraction: 0.82)
    }

    public static func content(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -10))
    }
}

/// The brand mark, drawn rather than loaded.
///
/// Transcribed from `packages/ui/assets/logo.svg` so the Kit has no asset
/// catalogue of its own and SwiftUI previews work without the app target.
public struct NotchLogo: View {
    public var size: CGFloat

    public init(size: CGFloat = 16) {
        self.size = size
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 512
            var path = Path()

            // The rising arrow: a shaft that dips and rises, with a head in
            // the top-right corner. Stroked rather than filled, which is a
            // dozen points instead of the SVG's single long outline path.
            path.move(to: CGPoint(x: 61, y: 334))
            path.addLine(to: CGPoint(x: 150, y: 245))
            path.addCurve(
                to: CGPoint(x: 207, y: 245),
                control1: CGPoint(x: 166, y: 229), control2: CGPoint(x: 191, y: 229))
            path.addLine(to: CGPoint(x: 269, y: 307))
            path.addCurve(
                to: CGPoint(x: 324, y: 307),
                control1: CGPoint(x: 284, y: 322), control2: CGPoint(x: 309, y: 322))
            path.addLine(to: CGPoint(x: 451, y: 178))

            let transform = CGAffineTransform(scaleX: scale, y: scale)
            let shaft = path.applying(transform)

            let gradient = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [NotchTheme.gradientStart, NotchTheme.gradientEnd]),
                startPoint: CGPoint(x: 32 * scale, y: 348 * scale),
                endPoint: CGPoint(x: 480 * scale, y: 161 * scale))

            context.stroke(
                shaft, with: gradient,
                style: StrokeStyle(lineWidth: 58 * scale, lineCap: .round, lineJoin: .round))

            // The arrowhead: an L in the top-right, matching the SVG's
            // squared-off corner rather than a triangle.
            var head = Path()
            head.move(to: CGPoint(x: 354, y: 178))
            head.addLine(to: CGPoint(x: 451, y: 178))
            head.addLine(to: CGPoint(x: 451, y: 275))
            context.stroke(
                head.applying(transform), with: gradient,
                style: StrokeStyle(lineWidth: 58 * scale, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Notch Metrics")
    }
}

/// The snap grid, shown only while rearranging.
///
/// A dot at every cell corner rather than full gridlines: lines at this size
/// compete with the tile borders and the panel starts to look like a
/// spreadsheet. Dots read as "there is a grid here" and disappear behind the
/// content.
public struct DottedGrid: View {
    public let cellSize: CGSize
    public let spacing: CGFloat

    public init(cellSize: CGSize, spacing: CGFloat) {
        self.cellSize = cellSize
        self.spacing = spacing
    }

    public var body: some View {
        Canvas { context, size in
            let strideX = cellSize.width + spacing
            let strideY = cellSize.height + spacing
            guard strideX > 1, strideY > 1 else { return }

            let radius: CGFloat = 1
            var y = 0.0
            while y <= size.height + 0.5 {
                var x = 0.0
                while x <= size.width + 0.5 {
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(NotchTheme.editDot))
                    x += strideX
                }
                y += strideY
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
