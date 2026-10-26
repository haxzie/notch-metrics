import SwiftUI
import Testing

@testable import NotchUI

/// The fade across the handle's band.
///
/// The band's height *is* the ramp, so the arithmetic is short and the ways
/// it can go wrong are few: a ramp that starts in the wrong place leaves the
/// hard line it exists to remove, and one that is too long fades a row that
/// should be solid.
@MainActor
struct GridEdgeSofteningTests {
    @Test("the ramp spans exactly the band")
    func rampMatchesTheBand() {
        // Solid until the band begins, clear at the bottom edge. Anything
        // else and the last row either ends early or survives past the handle.
        let stops = GridEdgeSoftening(bandHeight: 24).stops(in: 300)
        #expect(stops.count == 3)
        #expect(stops[0].location == 0)
        #expect(abs(stops[1].location - (300 - 24) / 300) < 0.001)
        #expect(stops[2].location == 1)
    }

    @Test("a short grid keeps its row")
    func shortGridIsClamped() {
        // A one-row grid under a tall band. Unclamped the ramp would start
        // above the row's middle and dim content that is nowhere near the
        // handle.
        let stops = GridEdgeSoftening(bandHeight: 90).stops(in: 100)
        #expect(stops[1].location >= 0.5)
    }

    @Test("the stops never run backwards")
    func monotonic() {
        // A gradient whose stops go backwards renders as a hard band, which
        // is the exact artefact this removes.
        for height in stride(from: 0, through: 500, by: 17) {
            let locations = GridEdgeSoftening(bandHeight: 24).stops(in: CGFloat(height))
                .map(\.location)
            #expect(locations == locations.sorted(), "height \(height)")
            #expect(locations.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }, "height \(height)")
        }
    }

    @Test("a zero-height viewport is survivable")
    func degenerate() {
        // The first layout pass, before the panel has a size.
        let locations = GridEdgeSoftening(bandHeight: 24).stops(in: 0).map(\.location)
        #expect(locations == locations.sorted())
    }

    @Test("no band means no fade")
    func withoutABand() {
        // Defensive: the modifier is only applied to the grid, which always
        // has a band, but a zero height must read as "solid throughout"
        // rather than as a ramp over the whole grid.
        let stops = GridEdgeSoftening(bandHeight: 0).stops(in: 300)
        #expect(stops[1].location == 1)
    }
}
