import Foundation
import MetricsCore
import SwiftUI
import Testing

@testable import NotchUI

/// The three distribution charts.
///
/// They draw one list's categories against each other, where `sparkline` and
/// `bars` draw a series over time. Most of them is drawing, which a test
/// cannot judge; what it can pin is the arithmetic underneath — shares that
/// sum to the whole, and a palette that never runs out.
@MainActor
struct DistributionTests {
    @Test("the distributions say they are distributions, and the others do not")
    func kindsAreClassified() {
        // The tile asks this instead of testing for three cases every time it
        // decides what to draw.
        #expect(ChartKind.split.isDistribution)
        #expect(ChartKind.ranked.isDistribution)
        #expect(ChartKind.pie.isDistribution)

        #expect(ChartKind.bars.isDistribution == false)
        #expect(ChartKind.sparkline.isDistribution == false)
        #expect(ChartKind.gauge.isDistribution == false)
        #expect(ChartKind.none.isDistribution == false)
    }

    @Test("a list defaults to ranked, whatever its unit")
    func listsDefaultToRanked() {
        // The list comes first: a percentage breakdown is still a
        // distribution, not a gauge, even though its unit is a ratio.
        #expect(ChartKind.defaultFor(unit: .count, supportsSeries: false, isList: true) == .ranked)
        #expect(ChartKind.defaultFor(unit: .ratio, supportsSeries: false, isList: true) == .ranked)

        // And a non-list is unaffected.
        #expect(ChartKind.defaultFor(unit: .ratio, supportsSeries: false) == .gauge)
        #expect(ChartKind.defaultFor(unit: .count, supportsSeries: true) == .sparkline)
    }

    @Test("each distribution asks for a tile it fits in")
    func preferredSizes() {
        // One divided bar is happy on a line; a bar *per category* needs a
        // line each, and a circle needs its height.
        #expect(ChartKind.split.preferredSize == .wide)
        #expect(ChartKind.ranked.preferredSize == WidgetSize(cols: 2, rows: 2))
        #expect(ChartKind.pie.preferredSize == .square)
    }

    @Test("shares are normalised so the bar fills its width")
    func sharesNormalise() {
        // A split bar shows proportion. One that stopped short would read as
        // "the rest is missing" rather than "this is the whole".
        let bar = SplitBar(shares: [3, 1])
        #expect(bar.normalised == [0.75, 0.25])
        #expect(abs(bar.normalised.reduce(0, +) - 1) < 0.0001)
    }

    @Test("nothing to draw is drawn as nothing, not as a crash")
    func emptyAndZero() {
        // Reachable: a window with no traffic returns rows that are all zero,
        // and dividing by that total is how a chart becomes a NaN.
        #expect(SplitBar(shares: []).normalised.isEmpty)
        #expect(SplitBar(shares: [0, 0]).normalised.isEmpty)
        #expect(PieChart(shares: [0, 0, 0]).normalised.isEmpty)
    }

    @Test("a negative value cannot eat another slice")
    func negativesAreClamped() {
        // A connector returning a negative is wrong, but the chart must not
        // compound it: a negative share would shrink the total and push the
        // others past 100%.
        let bar = SplitBar(shares: [1, -5, 1])
        #expect(bar.normalised == [0.5, 0, 0.5])
    }

    @Test("the palette wraps rather than running out")
    func paletteWraps() {
        // A list can be longer than the palette. Repeating is honest; a
        // transparent slice or an index crash is not.
        #expect(SliceColours.at(0) == SliceColours.all[0])
        #expect(SliceColours.at(SliceColours.all.count) == SliceColours.all[0])
        #expect(SliceColours.at(SliceColours.all.count + 2) == SliceColours.all[2])
        // Defensive: an index should never be negative, but modulo in Swift
        // keeps the sign and would crash on a subscript.
        #expect(SliceColours.at(-1) == SliceColours.all[SliceColours.all.count - 1])
    }

    @Test("ranked shows only the rows it has room for")
    func rankedTruncates() {
        // Unbounded, five categories at natural height overflowed a 2x2 and
        // pushed the tile taller than its neighbours — and spilled the
        // gallery preview past its padding.
        let rows = (1...5).map {
            RankedBars.Row(id: "\($0)", label: "m\($0)", detail: nil, share: 0.2)
        }
        #expect(RankedBars(rows: rows, maxRows: 3).visibleRows.count == 3)
        // Largest first, so what is dropped is the tail.
        #expect(RankedBars(rows: rows, maxRows: 3).visibleRows.first?.id == "1")

        // Fewer rows than the budget shows them all, and a nonsense budget
        // still shows one rather than an empty tile.
        #expect(RankedBars(rows: Array(rows.prefix(2)), maxRows: 4).visibleRows.count == 2)
        #expect(RankedBars(rows: rows, maxRows: 0).visibleRows.count == 1)
    }

    @Test("a slice too thin to draw is widened instead of overlapping its neighbour")
    func donutFloorsTinySlices() {
        // What the ring did before: a round cap overhangs its arc by half the
        // stroke, so 23.15B / 4.26B / 0.59B drew the small two as blobs
        // through the big one. Every slice that exists gets at least a cap's
        // worth of arc now.
        let ring = PieChart(shares: [23.15, 4.26, 0.59, 0.02])
        let cap = 0.2
        let gap = Double.pi / 60
        let sweeps = ring.sweeps(cap: cap, gap: gap)

        #expect(sweeps.count == 4)
        #expect(sweeps.allSatisfy { $0 >= 2 * cap })
        // The gaps are taken out of the circle, not added to it, so the ring
        // closes exactly.
        let total = sweeps.reduce(0, +) + gap * 4
        #expect(abs(total - 2 * .pi) < 0.0001)
        // Still a ranking: what was biggest is still biggest.
        #expect(sweeps[0] > sweeps[1])
        #expect(sweeps[1] > sweeps[2])
    }

    @Test("a share of nothing is not drawn at all")
    func donutSkipsZeroes() {
        // A zero is not a small slice, and floorng it would invent a category.
        let sweeps = PieChart(shares: [1, 0, 1]).sweeps(cap: 0.2, gap: 0.05)
        #expect(sweeps[1] == 0)
        #expect(sweeps[0] > 0)
    }

    @Test("more slices than the ring can show fall back to equal arcs")
    func donutFallsBackToEqualArcs() {
        // Reachable with a thick ring and a long list: once every slice is at
        // its floor there is nothing left to take the excess from. Equal arcs
        // say "these are the categories" rather than overlapping.
        let shares = Array(repeating: 1.0, count: 40)
        let sweeps = PieChart(shares: shares).sweeps(cap: 0.3, gap: 0.01)
        #expect(sweeps.count == 40)
        #expect(Set(sweeps.map { ($0 * 1000).rounded() }).count == 1)
    }

    @Test("a lone slice is a closed ring")
    func donutSingleSlice() {
        // One category takes the whole circle. A notch in it would read as
        // missing data rather than as the whole, which is why the gap is
        // dropped at a count of one.
        let sweeps = PieChart(shares: [5]).sweeps(cap: 0.2, gap: 0)
        #expect(abs((sweeps.first ?? 0) - 2 * .pi) < 0.0001)
    }

    @Test("the key names as many slices as the tile has room for")
    func legendTruncates() {
        // Same bargain as the ranked bars: dropped from the tail rather than
        // squeezed, because six lines crushed into the height of three are
        // six unreadable ones. What is dropped is still in the bar.
        let rows = (1...6).map {
            SliceLegend.Row(id: "\($0)", label: "m\($0)", detail: nil, colourIndex: $0 - 1)
        }
        #expect(SliceLegend(rows: rows, maxRows: 3).visibleRows.count == 3)
        #expect(SliceLegend(rows: rows, maxRows: 3).visibleRows.first?.id == "1")
        #expect(SliceLegend(rows: Array(rows.prefix(2)), maxRows: 5).visibleRows.count == 2)
    }

    @Test("no room means no key, not one crushed line")
    func legendCanBeEmpty() {
        // A one-row tile, and the row layout. The bar stands alone there as
        // it always did, rather than stealing the line it needs.
        let rows = [SliceLegend.Row(id: "1", label: "m", detail: nil, colourIndex: 0)]
        #expect(SliceLegend(rows: rows, maxRows: 0).visibleRows.isEmpty)
    }

    @Test("a dot keeps its slice's colour even when the key is cut short")
    func legendColoursFollowTheBar() {
        // The reason a row carries its index rather than taking it from its
        // position: the visible rows are a prefix, and a dot out of step with
        // the bar would be worse than no key at all.
        let rows = (0..<8).map {
            SliceLegend.Row(id: "\($0)", label: "m", detail: nil, colourIndex: $0)
        }
        let visible = SliceLegend(rows: rows, maxRows: 3).visibleRows
        #expect(visible.map(\.colourIndex) == [0, 1, 2])
        #expect(SliceColours.at(visible[2].colourIndex) == SliceColours.all[2])
    }
}
