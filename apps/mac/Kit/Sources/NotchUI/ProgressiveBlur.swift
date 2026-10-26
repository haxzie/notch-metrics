import SwiftUI

/// A band whose blur ramps from nothing to full across its own height.
///
/// For the two edges of the widgets grid. The grid scrolls, and before this
/// a tile crossing the header or the bottom handle was simply cut off at a
/// hard line: readable text one pixel, gone the next. A ramp reads as the
/// content passing underneath, which is what is actually happening.
///
/// ## Why it is built out of layers
///
/// A single blurred rectangle has one radius everywhere, so it hides the
/// content at the far edge of the band as much as the near one. What is
/// wanted is a *gradient* of radius, and neither SwiftUI nor Core Animation
/// exposes one publicly. `CAFilter(type: "variableBlur")` does exactly this
/// and is private API, which this app will not ship: it is signed, notarised
/// and distributed outside the App Store, and a private symbol is the kind of
/// thing that passes review once and fails an OS update later.
///
/// So the ramp is approximated. Several bands are stacked, each blurred a
/// little more than the last and each masked to a shorter run, and the sum of
/// their masks is a smooth curve. Six layers is where the stepping stops
/// being visible at these heights; more costs a compositing pass each and
/// buys nothing.
///
/// Rules this follows, which are the ones everybody gets wrong:
///
/// - **No opaque background.** An opaque header defeats the point: there is
///   nothing to see through it, so the ramp may as well be a solid bar.
/// - **No clipping of the content underneath.** The band draws *over* the
///   grid. Clipping the grid to exclude it would remove the very thing the
///   blur is meant to reveal.
public struct ProgressiveBlur: View {
    public enum Edge {
        case top
        case bottom
    }

    public let edge: Edge
    /// The blur radius at the solid end of the ramp.
    public let maxRadius: CGFloat
    public let layers: Int

    public init(edge: Edge, maxRadius: CGFloat = 8, layers: Int = 6) {
        self.edge = edge
        self.maxRadius = maxRadius
        self.layers = max(1, layers)
    }

    /// Where layer `index` starts and ends, as fractions of the band.
    ///
    /// Each layer covers the run from its own position to the solid end, so
    /// the layers overlap and their masks add up. The near edge is therefore
    /// covered by one layer and the far edge by all of them, which is the
    /// ramp.
    func span(_ index: Int) -> (start: CGFloat, end: CGFloat) {
        let step = 1 / CGFloat(layers)
        return (CGFloat(index) * step, 1)
    }

    /// The radius for layer `index`. Squared, so the ramp is gentle where the
    /// content is still meant to be readable and steep near the edge, which
    /// is how a real depth-of-field falls off.
    func radius(_ index: Int) -> CGFloat {
        let t = CGFloat(index + 1) / CGFloat(layers)
        return maxRadius * t * t
    }

    public var body: some View {
        ZStack {
            ForEach(0..<layers, id: \.self) { index in
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .blur(radius: radius(index), opaque: false)
                    .mask(gradient(for: index))
            }
        }
        // One group, so the stacked layers composite together rather than
        // each one blending against the tile behind it in turn.
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private func gradient(for index: Int) -> some View {
        let (start, _) = span(index)
        // Black is opaque in a mask. The solid end of the ramp is whichever
        // edge the band is pinned to.
        let stops: [Gradient.Stop] = [
            .init(color: .clear, location: 0),
            .init(color: .black, location: min(1, start + 1 / CGFloat(layers))),
            .init(color: .black, location: 1),
        ]
        return LinearGradient(
            stops: stops,
            startPoint: edge == .top ? .bottom : .top,
            endPoint: edge == .top ? .top : .bottom)
    }
}
