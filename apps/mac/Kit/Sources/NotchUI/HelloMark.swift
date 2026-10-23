import SwiftUI

/// Apple's "hello", written out stroke by stroke.
///
/// The greeting on the welcome screen is drawn rather than typed because no
/// font on the machine is this script, and shipping one for a single word is
/// 200 KB for six letters. A traced path also gets the writing animation for
/// free: `trim` on a stroked path is the whole effect.
///
/// The outline is from the open-source `apple-hello-effect` component
/// (https://dai.is-a.dev/components/apple-hello-effect), on a 638x200
/// viewBox. **Traced, not authored** — do not hand-tune a control point to fix
/// a curve that looks off, because the numbers are not independent of each
/// other and the only honest way back is to re-trace the whole glyph.
public struct HelloScript: Shape {
    /// The viewBox the curves below are expressed in. Everything scales off
    /// this, so the mark can be given any height.
    public static let aspectRatio: CGFloat = 638 / 200

    /// The original's stroke, as a fraction of the mark's height.
    ///
    /// Carried as a ratio rather than a constant: a line width that does not
    /// scale with the glyph turns the word into a blob at small sizes and a
    /// hairline at large ones.
    public static let strokeRatio: CGFloat = 14.8883 / 200

    public init() {}

    public func path(in rect: CGRect) -> Path {
        // Inset by half the stroke, which straddles the path on both sides.
        // Without this the ascender of the `h` and the tail of the final `o`
        // are clipped by the frame they are drawn to fit.
        let stroke = rect.height * Self.strokeRatio
        let box = rect.insetBy(dx: stroke / 2, dy: stroke / 2)
        let scale = min(box.width / 638, box.height / 200)

        var path = Path()
        glyph(into: &path)

        // Centred in whatever it was handed: the aspect ratio is fixed by the
        // caller's frame, not by this shape, and a mark pinned to the top-left
        // of a frame a point too tall reads as misaligned.
        let size = CGSize(width: 638 * scale, height: 200 * scale)
        return path.applying(
            CGAffineTransform(scaleX: scale, y: scale)
                .concatenating(
                    CGAffineTransform(
                        translationX: box.minX + (box.width - size.width) / 2,
                        y: box.minY + (box.height - size.height) / 2)))
    }

    /// The word in viewBox coordinates.
    ///
    /// Two subpaths, in writing order: the `h`'s ascender, then everything
    /// else in one unbroken stroke. `trim` walks them in that order, which is
    /// what makes the animation read as handwriting rather than as two
    /// pieces appearing at once.
    private func glyph(into path: inout Path) {
        // The ascender.
        path.move(to: CGPoint(x: 8.69214, y: 166.553))
        path.addCurve(
            to: CGPoint(x: 89.8191, y: 98.0295),
            control1: CGPoint(x: 36.2393, y: 151.239),
            control2: CGPoint(x: 61.3409, y: 131.548))
        path.addCurve(
            to: CGPoint(x: 120.122, y: 31.0026),
            control1: CGPoint(x: 109.203, y: 75.1488),
            control2: CGPoint(x: 119.625, y: 49.0228))
        path.addCurve(
            to: CGPoint(x: 101.759, y: 7.43883),
            control1: CGPoint(x: 120.37, y: 17.6036),
            control2: CGPoint(x: 113.836, y: 7.43883))
        path.addCurve(
            to: CGPoint(x: 74.7122, y: 40.9363),
            control1: CGPoint(x: 88.3598, y: 7.43883),
            control2: CGPoint(x: 79.9231, y: 17.6036))
        path.addCurve(
            to: CGPoint(x: 54.1166, y: 190.356),
            control1: CGPoint(x: 69.005, y: 66.5793),
            control2: CGPoint(x: 64.7866, y: 96.0036))

        // The body: h, e, l, l, o and the flick off the end.
        path.move(to: CGPoint(x: 55.1624, y: 181.135))
        path.addCurve(
            to: CGPoint(x: 107.963, y: 98.0479),
            control1: CGPoint(x: 60.6251, y: 133.114),
            control2: CGPoint(x: 81.4118, y: 98.0479))
        path.addCurve(
            to: CGPoint(x: 131.071, y: 128.817),
            control1: CGPoint(x: 123.844, y: 98.0479),
            control2: CGPoint(x: 133.937, y: 110.703))
        path.addCurve(
            to: CGPoint(x: 125.408, y: 163.06),
            control1: CGPoint(x: 129.457, y: 139.487),
            control2: CGPoint(x: 127.587, y: 150.405))
        path.addCurve(
            to: CGPoint(x: 152.122, y: 191.348),
            control1: CGPoint(x: 122.869, y: 178.941),
            control2: CGPoint(x: 130.128, y: 191.348))
        path.addCurve(
            to: CGPoint(x: 237.097, y: 145.915),
            control1: CGPoint(x: 184.197, y: 191.348),
            control2: CGPoint(x: 219.189, y: 173.523))
        path.addCurve(
            to: CGPoint(x: 245.928, y: 119.884),
            control1: CGPoint(x: 243.198, y: 136.509),
            control2: CGPoint(x: 245.68, y: 128.073))
        path.addCurve(
            to: CGPoint(x: 222.851, y: 93.8296),
            control1: CGPoint(x: 246.176, y: 104.996),
            control2: CGPoint(x: 237.739, y: 93.8296))
        path.addCurve(
            to: CGPoint(x: 189.6, y: 142.465),
            control1: CGPoint(x: 203.992, y: 93.8296),
            control2: CGPoint(x: 189.6, y: 115.17))
        path.addCurve(
            to: CGPoint(x: 239.208, y: 192.341),
            control1: CGPoint(x: 189.6, y: 171.745),
            control2: CGPoint(x: 205.481, y: 192.341))
        path.addCurve(
            to: CGPoint(x: 359.199, y: 75.8585),
            control1: CGPoint(x: 285.066, y: 192.341),
            control2: CGPoint(x: 335.86, y: 137.292))
        path.addCurve(
            to: CGPoint(x: 368.26, y: 31.1512),
            control1: CGPoint(x: 365.788, y: 58.513),
            control2: CGPoint(x: 368.26, y: 42.4065))
        path.addCurve(
            to: CGPoint(x: 352.131, y: 7.55823),
            control1: CGPoint(x: 368.26, y: 17.8057),
            control2: CGPoint(x: 364.042, y: 7.55823))
        path.addCurve(
            to: CGPoint(x: 325.829, y: 30.9129),
            control1: CGPoint(x: 340.469, y: 7.55823),
            control2: CGPoint(x: 332.777, y: 16.6141))
        path.addCurve(
            to: CGPoint(x: 309.203, y: 98.4549),
            control1: CGPoint(x: 317.688, y: 47.4967),
            control2: CGPoint(x: 311.667, y: 71.4162))
        path.addCurve(
            to: CGPoint(x: 349.936, y: 191.348),
            control1: CGPoint(x: 303, y: 166.301),
            control2: CGPoint(x: 316.896, y: 191.348))
        path.addCurve(
            to: CGPoint(x: 457.286, y: 75.6686),
            control1: CGPoint(x: 390, y: 191.348),
            control2: CGPoint(x: 434.542, y: 135.534))
        path.addCurve(
            to: CGPoint(x: 466.275, y: 31.1512),
            control1: CGPoint(x: 463.803, y: 58.513),
            control2: CGPoint(x: 466.275, y: 42.4065))
        path.addCurve(
            to: CGPoint(x: 450.146, y: 7.55823),
            control1: CGPoint(x: 466.275, y: 17.8057),
            control2: CGPoint(x: 462.057, y: 7.55823))
        path.addCurve(
            to: CGPoint(x: 423.844, y: 30.9129),
            control1: CGPoint(x: 438.484, y: 7.55823),
            control2: CGPoint(x: 430.792, y: 16.6141))
        path.addCurve(
            to: CGPoint(x: 407.218, y: 98.4549),
            control1: CGPoint(x: 415.703, y: 47.4967),
            control2: CGPoint(x: 409.682, y: 71.4162))
        path.addCurve(
            to: CGPoint(x: 444.416, y: 191.348),
            control1: CGPoint(x: 401.015, y: 166.301),
            control2: CGPoint(x: 414.911, y: 191.348))
        path.addCurve(
            to: CGPoint(x: 499.471, y: 138.402),
            control1: CGPoint(x: 473.874, y: 191.348),
            control2: CGPoint(x: 489.877, y: 165.67))
        path.addCurve(
            to: CGPoint(x: 544.935, y: 94.8221),
            control1: CGPoint(x: 508.955, y: 111.447),
            control2: CGPoint(x: 520.618, y: 94.8221))
        path.addCurve(
            to: CGPoint(x: 580.916, y: 137.75),
            control1: CGPoint(x: 565.035, y: 94.8221),
            control2: CGPoint(x: 580.916, y: 109.71))
        path.addCurve(
            to: CGPoint(x: 535.362, y: 192.341),
            control1: CGPoint(x: 580.916, y: 168.768),
            control2: CGPoint(x: 560.792, y: 192.093))
        path.addCurve(
            to: CGPoint(x: 499.774, y: 147.179),
            control1: CGPoint(x: 512.984, y: 192.589),
            control2: CGPoint(x: 498.285, y: 174.475))
        path.addCurve(
            to: CGPoint(x: 543.943, y: 94.8221),
            control1: CGPoint(x: 501.511, y: 116.907),
            control2: CGPoint(x: 519.873, y: 94.8221))
        path.addCurve(
            to: CGPoint(x: 578.682, y: 107.725),
            control1: CGPoint(x: 557.839, y: 94.8221),
            control2: CGPoint(x: 569.51, y: 100.999))
        path.addCurve(
            to: CGPoint(x: 630.047, y: 96.7186),
            control1: CGPoint(x: 603.549, y: 125.866),
            control2: CGPoint(x: 622.709, y: 114.656))
    }
}

/// The greeting itself: the script, stroked in the brand gradient, writing
/// itself once when it appears.
public struct HelloMark: View {
    /// Drives the stroke. Animating `trim` is what writes the word; animating
    /// opacity would only fade a finished one in.
    @State private var progress: CGFloat = 0

    /// Honoured rather than ignored: this is a two-second animation of a
    /// moving line across the whole panel, which is the exact thing the
    /// setting is asking us not to do.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let height: CGFloat

    public init(height: CGFloat = 76) {
        self.height = height
    }

    public var body: some View {
        HelloScript()
            .trim(from: 0, to: progress)
            .stroke(
                NotchTheme.brand,
                style: StrokeStyle(
                    lineWidth: height * HelloScript.strokeRatio,
                    lineCap: .round, lineJoin: .round))
            .frame(width: height * HelloScript.aspectRatio, height: height)
            .onAppear {
                guard !reduceMotion else {
                    progress = 1
                    return
                }
                // Eased at both ends and a touch slow: a pen lifts at the end
                // of a word, and a linear sweep reads as a progress bar.
                withAnimation(.easeInOut(duration: 1.9)) { progress = 1 }
            }
    }
}
