import Foundation
import SwiftUI
import MetricsCore
import Testing

@testable import NotchUI

/// The gauge chart kind.
///
/// Most of a gauge is drawing, which a test cannot judge. What it can pin is
/// the contract around it: that the kind survives the wire, that it is the one
/// chart a metric with no history can carry, and that a value outside its
/// bound does not wrap into a smaller-looking one.
struct GaugeTests {
    @Test("the kind round-trips through the layout")
    func roundTrips() throws {
        // `layout.json` is written by this app and read back on every launch,
        // so a chart kind that does not survive a round trip loses the user's
        // choice at the next restart.
        let widget = NotchWidget(
            id: "w", kind: .customMetric, appId: "custom", customMetricId: "app/used",
            title: "Used", size: .wide, chart: .gauge)
        let data = try JSONEncoder().encode(widget)
        #expect(try JSONDecoder().decode(NotchWidget.self, from: data).chart == .gauge)
        // Spelled as the schema spells it, not as Swift names the case.
        #expect(String(data: data, encoding: .utf8)?.contains("gauge") == true)
    }

    @Test("a fraction past the bound fills the arc rather than wrapping")
    func clampsAboveOne() {
        // A limit can legitimately be exceeded — a 5-hour window can report
        // 105%. An arc that wrapped past its own start would draw 105% as a
        // sliver and read as *less* than 95%.
        #expect(GaugeArc(fraction: 1.4, tint: .red) { EmptyView() }.displayFraction == 1)
        #expect(GaugeArc(fraction: -0.2, tint: .red) { EmptyView() }.displayFraction == 0)
        #expect(GaugeArc(fraction: 0.18, tint: .red) { EmptyView() }.displayFraction == 0.18)
    }

    @Test("a gauge is the default chart for a ratio, and only for a ratio")
    func defaultsForRatios() {
        // Discoverability, not preference: a chart reachable only through a
        // picker is one most people never find, and the gauge is the only
        // chart a scalar metric can carry at all.
        #expect(ChartKind.defaultFor(unit: .ratio, supportsSeries: false) == .gauge)
        #expect(ChartKind.defaultFor(unit: .ratio, supportsSeries: true) == .gauge)

        // Everything else keeps what it had: a series gets a line, a bare
        // figure gets nothing.
        #expect(ChartKind.defaultFor(unit: .count, supportsSeries: true) == .sparkline)
        #expect(ChartKind.defaultFor(unit: .count, supportsSeries: false) == .none)
        #expect(ChartKind.defaultFor(unit: .currency, supportsSeries: true) == .sparkline)
    }

    @Test("a gauge asks for a tile it fits in")
    func wantsHeight() {
        // A semicircle is twice as wide as it is tall. On a 2x1 tile the arc
        // collapses to a sliver with the figure sitting on top of it, which is
        // what it did before this: the default size is part of the chart kind,
        // not a separate thing each caller remembers.
        //
        // Every kind asks for the same tile now, so this is really one
        // assertion about the gauge and three about the rule not having
        // grown an exception. `DistributionTests` covers the rule itself.
        #expect(ChartKind.gauge.preferredSize == .square)
        #expect(ChartKind.sparkline.preferredSize == .square)
        #expect(ChartKind.bars.preferredSize == .square)
        #expect(ChartKind.none.preferredSize == .square)
    }

    @Test("the arc and the figure agree on where the centre is")
    func geometryIsShared() {
        // These were two separate expressions, and on any tile that was not
        // square the label's idea of the centre drifted from the arc's.
        let wide = GaugeArc<EmptyView>.geometry(in: CGSize(width: 200, height: 60), lineWidth: 8)
        #expect(wide.centre.x == 100)
        // Short and wide: bounded by height, not by half the width.
        #expect(wide.radius == 52)

        let tall = GaugeArc<EmptyView>.geometry(in: CGSize(width: 80, height: 200), lineWidth: 8)
        // Narrow and tall: bounded by half the width instead.
        #expect(tall.radius == 36)

        // A frame too small for the stroke gives no arc rather than a
        // negative radius, which would draw inside out.
        #expect(GaugeArc<EmptyView>.geometry(in: CGSize(width: 4, height: 4), lineWidth: 8).radius == 0)
    }
}
