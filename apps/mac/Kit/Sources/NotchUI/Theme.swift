import AppKit
import MetricsCore
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

    /// The app's own colour, from `MetricApp.accentHex`.
    ///
    /// Preferred over `accent(for:)` everywhere an app is known: two Stripe
    /// tiles should look like two Stripe tiles, not like tile one and tile two.
    public static func accent(for app: MetricApp) -> Color {
        Color(hex: app.accentHex) ?? gradientStart
    }

    /// The fill behind a connector's mark.
    ///
    /// Brand colours are chosen against a white page, so several of them
    /// (PostHog, Apple, Notion) are near-black and vanish into this window.
    /// Lifting anything below the floor keeps the tile a recognisable shape
    /// without moving the hue, which is what people actually recognise.
    public static func tileFill(for app: MetricApp) -> Color {
        guard let nsColor = NSColor(hex: app.accentHex)?
            .usingColorSpace(.sRGB) else { return gradientStart }

        // Rec. 709 luma. Close enough for "is this going to disappear", and
        // cheaper than a full perceptual conversion for a 30pt square.
        let luma =
            0.2126 * nsColor.redComponent
            + 0.7152 * nsColor.greenComponent
            + 0.0722 * nsColor.blueComponent

        let floor = 0.16
        guard luma < floor else { return Color(nsColor: nsColor) }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // A fully desaturated brand (pure black) has no hue to preserve, so it
        // becomes a neutral tile rather than an arbitrary colour.
        return Color(
            nsColor: NSColor(
                hue: hue,
                saturation: saturation,
                brightness: max(brightness, 0.28),
                alpha: alpha
            )
        )
    }

    /// The accent as a chart line or sparkline fill.
    ///
    /// A higher floor than `tileFill`. A tile only has to be a distinguishable
    /// shape, and 0.28 brightness behind a hairline border manages that; a
    /// 1.5pt line *is* the content, and Dodo Payments' `#111111` drew a
    /// near-black chart on a near-black tile — present, and unreadable.
    ///
    /// Brands with a usable colour are untouched, so a Lemon Squeezy chart
    /// stays Lemon Squeezy yellow.
    public static func chartTint(for app: MetricApp) -> Color {
        // The brand's own chart colour when it has one; the lift below is for
        // brands that only publish a dark primary.
        guard let nsColor = NSColor(hex: app.chartHex ?? app.accentHex)?
            .usingColorSpace(.sRGB)
        else { return gradientStart }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        guard brightness < 0.6 else { return Color(nsColor: nsColor) }

        // A brand with no hue to raise — pure black or grey — would otherwise
        // become an arbitrary tinted line, so it goes to a neutral light grey.
        if saturation < 0.15 {
            return Color(white: 0.72)
        }
        return Color(
            nsColor: NSColor(
                hue: hue, saturation: max(saturation, 0.5), brightness: 0.78, alpha: alpha))
    }

    /// Tints a tile from its index. Only for the case where no app is known.
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
    /// Opening. Deliberately under-damped so the panel overshoots a little and
    /// settles — the "gooey" part. A critically damped spring is technically
    /// smoother and reads as a window resizing rather than as something
    /// growing out of the bezel.
    public static func expansion(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.1)
            : .spring(response: 0.34, dampingFraction: 0.62)
    }

    /// Closing. Faster and almost fully damped: an overshoot on the way out
    /// means the notch is still wobbling after the pointer has gone, which
    /// reads as lag rather than as polish.
    public static func collapse(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.08)
            : .spring(response: 0.26, dampingFraction: 0.9)
    }

    /// The content inside. Scaled from the top edge so it appears to be
    /// squeezed out of the notch rather than cross-faded in behind it.
    public static func content(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
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

extension NSColor {
    /// `RRGGBB`, in sRGB.
    ///
    /// The AppKit twin of `Color(hex:)`, needed because luminance and HSB
    /// components are not reachable through SwiftUI's `Color`.
    convenience init?(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1)
    }
}

extension Color {
    /// `RRGGBB`, as stored in `MetricApp.accentHex`.
    ///
    /// Returns nil rather than black on a malformed value, so the caller can
    /// fall back to something visible — a black mark on a black panel is
    /// indistinguishable from a missing one.
    init?(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}
