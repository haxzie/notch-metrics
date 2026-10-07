import SwiftUI

/// The notch silhouette: squared off against the screen edge at the top, with
/// the bottom corners rounded outward and the top corners curving *back up*
/// into the bezel.
///
/// The inverted top corners are what make it read as part of the hardware
/// rather than as a panel floating under it. Without them the shape looks like
/// a dropdown that has lost its parent.
///
/// Those ears are drawn **inside** `rect`, not past its edges: the body is
/// inset by `topCornerRadius` on the left and right and the fillets occupy the
/// inset. A path that overflowed its own bounds was silently clipped by the
/// `compositingGroup()` the shadow needs, which is how the ears disappeared
/// while the geometry still looked right. Callers therefore give the shape a
/// frame `2 × topCornerRadius` wider than the panel body.
public struct NotchShape: Shape {
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat

    public init(topCornerRadius: CGFloat = 10, bottomCornerRadius: CGFloat = 16) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    /// How much wider than the body a frame must be to hold both ears.
    public var horizontalOverhang: CGFloat { max(0, topCornerRadius) * 2 }

    /// Animating the radii keeps the fillet proportional as the panel grows,
    /// rather than snapping at the end of the expansion.
    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = max(0, min(topCornerRadius, rect.width / 2))
        let bodyMinX = rect.minX + top
        let bodyMaxX = rect.maxX - top
        let bottom = max(
            0, min(bottomCornerRadius, rect.height / 2, (bodyMaxX - bodyMinX) / 2))

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: bodyMinX, y: rect.minY + top),
            control: CGPoint(x: bodyMinX, y: rect.minY)
        )

        path.addLine(to: CGPoint(x: bodyMinX, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: bodyMinX + bottom, y: rect.maxY),
            control: CGPoint(x: bodyMinX, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: bodyMaxX - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bodyMaxX, y: rect.maxY - bottom),
            control: CGPoint(x: bodyMaxX, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: bodyMaxX, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: bodyMaxX, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
