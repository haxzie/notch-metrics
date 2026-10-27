import Foundation
import MetricsCore
import SwiftUI
import Testing

@testable import NotchUI

/// Which way a tile lays itself out.
///
/// A one-row tile stacked badly: the label took the top, the figure the
/// middle, and everything past the second column was empty. Wider than it is
/// tall, the natural reading is left-to-right — name, then number — which is
/// also how the list view already reads.
@MainActor
struct TileLayoutTests {
    static func tile(
        size: WidgetSize, chart: ChartKind = .sparkline, state: TileState = .loading
    ) -> WidgetTile {
        WidgetTile(
            widget: NotchWidget(
                id: "w", kind: .customMetric, appId: "custom", customMetricId: "app/m",
                title: "Session", size: size, chart: chart),
            app: AppCatalog.resolve(AppCatalog.customId),
            state: state)
    }

    static func series(items: [MetricListItem]? = nil) -> MetricSeries {
        MetricSeries(
            integrationId: nil, metric: "m", unit: .ratio, currency: nil, value: 0.18,
            previousValue: nil, delta: nil, points: [], granularity: .day, range: .month,
            from: "2026-10-01T00:00:00.000Z", to: "2026-10-26T00:00:00.000Z",
            format: MetricFormat(), generatedAt: "2026-10-26T00:00:00.000Z", stale: false,
            items: items)
    }

    @Test("a long one-row tile reads as a row")
    func wideRowsGoSideBySide() {
        // The sizes that left the right half of the tile empty.
        #expect(Self.tile(size: WidgetSize(cols: 3, rows: 1)).readsAsRow)
        #expect(Self.tile(size: WidgetSize(cols: 4, rows: 1)).readsAsRow)
        #expect(Self.tile(size: WidgetSize(cols: 6, rows: 1)).readsAsRow)
    }

    @Test("two columns is not wide enough for a row")
    func twoColumnsStayStacked() {
        // Room for a name or a figure, not both. Side by side, a 2x1
        // truncated everything to "Claude us…", "Out…" and "90…." — three
        // ellipses where there had been a readable tile.
        #expect(Self.tile(size: WidgetSize(cols: 2, rows: 1)).readsAsRow == false)
    }

    @Test("a tile with height keeps the stacked layout")
    func tallTilesStayStacked() {
        // Two rows or more have the room the gauge and the charts are drawn
        // for; stacking is right there and the row layout would waste it.
        #expect(Self.tile(size: .square).readsAsRow == false)
        #expect(Self.tile(size: WidgetSize(cols: 6, rows: 2)).readsAsRow == false)
    }

    @Test("a single square has no room for a row")
    func smallestStaysStacked() {
        // One column cannot hold a name and a figure side by side; the figure
        // would be squeezed to nothing.
        #expect(Self.tile(size: .small).readsAsRow == false)
    }

    @Test("a list keeps the stacked layout at every width")
    func listsNeverGoSideBySide() {
        // A list is already rows and has no headline figure to put on the
        // right. Treated as a row it rendered an empty tile — nothing on the
        // left but the name, and nothing on the right at all.
        let rows = [
            MetricListItem(
                id: "1", t: "2026-10-26T00:00:00.000Z", label: "Claude Code", detail: "100%",
                amount: nil, currency: nil, status: nil, state: nil)
        ]
        let list = Self.tile(
            size: WidgetSize(cols: 6, rows: 1), state: .value(Self.series(items: rows)))
        #expect(list.readsAsRow == false)

        // Unless it is drawn as a split bar, which is one object and sits on
        // a line happily — the text rows are what cannot share one.
        let split = Self.tile(
            size: WidgetSize(cols: 6, rows: 1), chart: .split,
            state: .value(Self.series(items: rows)))
        #expect(split.readsAsRow)

        // The same tile without rows does read as a row.
        let figure = Self.tile(
            size: WidgetSize(cols: 6, rows: 1), state: .value(Self.series()))
        #expect(figure.readsAsRow)
    }

    @Test("a wider row gives its chart more of the line")
    func chartWidthFollowsTheTile() {
        // Proportional, not fixed: a 2x1 has barely room for the figure, where
        // a 6x1 can give the chart half the line and still leave the name
        // space.
        #expect(
            Self.tile(size: WidgetSize(cols: 6, rows: 1)).rowChartWidth
                > Self.tile(size: WidgetSize(cols: 3, rows: 1)).rowChartWidth)
    }

    @Test("a list fills the height it is given")
    func listRowsAreMeasured() {
        // What this replaced was a formula: two rows, then three more per
        // extra tile row. It came out at five for every 2x2 whatever the
        // tile's real height, so a payments feed with more to show sat above
        // two rows of empty space.
        let tile = Self.tile(size: .square)
        let step = tile.listRowHeight + tile.listRowSpacing

        // Exactly three rows' worth fits three.
        #expect(tile.rowsThatFit(in: step * 3 - tile.listRowSpacing) == 3)
        // A sliver more does not buy a fourth.
        #expect(tile.rowsThatFit(in: step * 3) == 3)
        // A whole row more does.
        #expect(tile.rowsThatFit(in: step * 4 - tile.listRowSpacing) == 4)
    }

    @Test("a taller tile shows more rows")
    func tallerShowsMore() {
        // The property the formula was reaching for, now true by measurement
        // rather than by a constant that had to be kept in step by hand.
        let tile = Self.tile(size: .square)
        #expect(tile.rowsThatFit(in: 200) > tile.rowsThatFit(in: 100))
    }

    @Test("the first layout pass draws one row, not none")
    func beforeTheTileHasASize() {
        // Reachable on every open: the geometry reader reports zero until the
        // panel has laid out. Zero rows would flash an empty tile.
        #expect(Self.tile(size: .square).rowsThatFit(in: 0) == 1)
        #expect(Self.tile(size: .square).rowsThatFit(in: -10) == 1)
    }

    @Test("a row is never drawn half-clipped")
    func noPartialRows() {
        // A row cut in half reads as a rendering fault; a short list reads as
        // a short list.
        let tile = Self.tile(size: .square)
        let step = tile.listRowHeight + tile.listRowSpacing
        for extra in stride(from: 0.0, to: step, by: step / 5) {
            #expect(tile.rowsThatFit(in: step * 2 - tile.listRowSpacing + extra) == 2)
        }
    }
}
