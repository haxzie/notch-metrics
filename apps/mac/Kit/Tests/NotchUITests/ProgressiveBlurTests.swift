import SwiftUI
import Testing

@testable import NotchUI

/// The blurred bands at the two edges of the widgets grid.
///
/// Most of this is drawing, which a test cannot judge. What it can pin is the
/// arithmetic the ramp is built from: the layers have to cover the band
/// between them, and the radius has to climb towards the edge the band is
/// pinned to rather than away from it.
@MainActor
struct ProgressiveBlurTests {
    @Test("the layers cover the band between them")
    func spansCoverTheBand() {
        // A gap would be a visible stripe of unblurred content inside the
        // ramp, which reads as a rendering fault rather than as a gradient.
        let blur = ProgressiveBlur(edge: .top, layers: 6)
        #expect(blur.span(0).start == 0)
        #expect(blur.span(5).end == 1)

        for index in 0..<5 {
            // Each layer starts no later than the next one, and every layer
            // runs to the solid end, so together they overlap rather than
            // tile. The overlap is what makes the mask add up to a ramp.
            #expect(blur.span(index).start < blur.span(index + 1).start)
            #expect(blur.span(index).end == 1)
        }
    }

    @Test("the radius climbs towards the solid edge")
    func radiusRamps() {
        let blur = ProgressiveBlur(edge: .top, maxRadius: 8, layers: 6)
        let radii = (0..<6).map(blur.radius)

        #expect(radii == radii.sorted())
        #expect(radii.last == 8)
        // Squared, so the near end stays readable. A linear ramp blurred the
        // middle of the band as much as a real falloff blurs its edge.
        #expect(radii[0] < 8 / 6)
    }

    @Test("a single layer is still a band and not a crash")
    func degenerate() {
        // Reachable through the initialiser, and the `max(1,)` is what keeps
        // `ForEach(0..<layers)` from an empty range.
        let blur = ProgressiveBlur(edge: .bottom, layers: 0)
        #expect(blur.layers == 1)
        #expect(blur.radius(0) == blur.maxRadius)
    }

    @Test("both edges ramp from their own side")
    func edgesAreSymmetric() {
        // Same arithmetic either way round; only the gradient's direction
        // differs. If these ever disagree, one edge is ramping backwards.
        let top = ProgressiveBlur(edge: .top, maxRadius: 8, layers: 6)
        let bottom = ProgressiveBlur(edge: .bottom, maxRadius: 8, layers: 6)
        #expect((0..<6).map(top.radius) == (0..<6).map(bottom.radius))
    }
}
