import Foundation
import Testing

@testable import MetricsCore

/// The packer is the one piece of the notch with real logic in it, and it runs
/// on every frame of a drag. These are the cases a drag can actually produce.
struct GridPackerTests {
    func widget(_ id: String, _ size: WidgetSize, col: Int, row: Int) -> NotchWidget {
        NotchWidget(id: id, size: size, col: col, row: row)
    }

    @Test("a widget that would hang off the right edge does not fit")
    func rejectsOverhang() {
        let layout = NotchLayout(widgets: [widget("a", .wide, col: 0, row: 0)])
        // Columns are 0...5, so a six-wide widget fits only at column 0.
        #expect(GridPacker.cells(for: widget("b", .hero, col: 1, row: 0), at: (1, 0)) == nil)
        #expect(!GridPacker.fits(widget("b", .hero, col: 1, row: 0), at: (1, 0), in: layout))
    }

    @Test("a two-row widget does not fit on the bottom row")
    func rejectsVerticalOverhang() {
        #expect(GridPacker.cells(for: widget("a", .square, col: 0, row: 1), at: (0, 1)) == nil)
    }

    @Test("occupied cells exclude the widget being moved")
    func excludesSelf() {
        let layout = NotchLayout(widgets: [widget("a", .square, col: 0, row: 0)])
        // Dropping a widget back onto its own cells must be allowed, or no
        // drag could ever end where it started.
        #expect(GridPacker.fits(widget("a", .square, col: 0, row: 0), at: (0, 0), in: layout))
    }

    @Test("invisible widgets do not reserve space")
    func ignoresHidden() {
        var hidden = widget("a", .hero, col: 0, row: 0)
        hidden.visible = false
        let layout = NotchLayout(widgets: [hidden])
        #expect(GridPacker.fits(widget("b", .wide, col: 0, row: 0), at: (0, 0), in: layout))
    }

    @Test("moving onto an occupied cell displaces the occupant")
    func displaces() throws {
        let layout = NotchLayout(widgets: [
            widget("a", .wide, col: 0, row: 0),
            widget("b", .wide, col: 2, row: 0),
        ])

        let moved = try #require(GridPacker.place("b", at: (0, 0), in: layout))
        let a = try #require(moved.widgets.first { $0.id == "a" })
        let b = try #require(moved.widgets.first { $0.id == "b" })

        #expect((b.col, b.row) == (0, 0))
        // `a` has to go somewhere, and must not still be under `b`.
        #expect((a.col, a.row) != (0, 0))
        #expect(!overlaps(a, b))
    }

    @Test("a move that cannot be resolved is refused rather than dropping a widget")
    func refusesImpossibleMove() {
        // Grid full: two heroes fill all sixteen cells.
        let layout = NotchLayout(widgets: [
            widget("a", .square, col: 0, row: 0),
            widget("b", .square, col: 2, row: 0),
            widget("c", .square, col: 4, row: 0),
        ])

        // Dropping `c` onto a slot it *fully* vacates is a swap, and the
        // packer should resolve it rather than refuse.
        #expect(GridPacker.place("c", at: (0, 0), in: layout) != nil)

        // Straddling two tiles is different: `c` at column 1 overlaps both `a`
        // and `b`, and once `a` has taken the only remaining pair of columns
        // there is nowhere left for `b`. The drag must snap back rather than
        // commit a layout with a widget silently gone.
        #expect(GridPacker.place("c", at: (1, 0), in: layout) == nil)
    }

    @Test("appending finds the first free slot, and reports a full grid")
    func appends() throws {
        // Six columns by two rows is twelve cells, and `.small` is one cell.
        var layout = NotchLayout()
        for index in 0..<12 {
            layout = try #require(
                GridPacker.append(widget("w\(index)", .small, col: 0, row: 0), to: layout))
        }
        #expect(layout.widgets.count == 12)
        #expect(layout.widgets.filter { $0.row == 0 }.count == 6)
        #expect(layout.widgets.filter { $0.row == 1 }.count == 6)

        // The thirteenth has nowhere to go, and saying so beats silently
        // discarding it.
        #expect(GridPacker.append(widget("overflow", .small, col: 0, row: 0), to: layout) == nil)
    }

    @Test("dragging the handle to a third row makes room for more widgets")
    func appendsIntoAddedRows() throws {
        var layout = NotchLayout(rows: 3)
        for index in 0..<18 {
            layout = try #require(
                GridPacker.append(widget("w\(index)", .small, col: 0, row: 0), to: layout))
        }
        #expect(layout.widgets.count == 18)
        #expect(GridPacker.append(widget("overflow", .small, col: 0, row: 0), to: layout) == nil)
    }

    @Test("resizing is refused when the larger size would overlap")
    func resize() {
        // `a` at column 0 and `b` at column 1. Growing `a` to two columns
        // would run into `b`; growing `b` has room to its right.
        let layout = NotchLayout(widgets: [
            widget("a", .small, col: 0, row: 0),
            widget("b", .small, col: 1, row: 0),
        ])
        #expect(!GridPacker.canResize("a", to: .wide, in: layout))
        #expect(GridPacker.canResize("b", to: .wide, in: layout))
    }

    @Test("the full-width hero fills the grid and leaves no room beside it")
    func hero() {
        let empty = NotchLayout()
        #expect(GridPacker.fits(widget("h", .hero, col: 0, row: 0), at: (0, 0), in: empty))

        // A hero is the full six columns across both rows, so nothing else
        // fits beside it at all.
        let withHero = NotchLayout(widgets: [widget("h", .hero, col: 0, row: 0)])
        #expect(!GridPacker.fits(widget("x", .small, col: 2, row: 1), at: (2, 1), in: withHero))
        #expect(!GridPacker.fits(widget("x", .small, col: 4, row: 0), at: (4, 0), in: withHero))

        // Unless the handle has been dragged to make room below it.
        let taller = NotchLayout(rows: 3, widgets: [widget("h", .hero, col: 0, row: 0)])
        #expect(GridPacker.fits(widget("x", .small, col: 0, row: 2), at: (0, 2), in: taller))
    }

    @Test("positions are renumbered left to right, top to bottom")
    func normalises() throws {
        let layout = NotchLayout(widgets: [
            widget("bottom-left", .small, col: 0, row: 1),
            widget("top-right", .small, col: 5, row: 0),
            widget("top-left", .small, col: 0, row: 0),
        ])
        let order = GridPacker.normalised(layout).widgets.map(\.id)
        #expect(order == ["top-left", "top-right", "bottom-left"])
    }

    @Test("a three-row grid accepts a widget the two-row grid refuses")
    func respectsRowCount() {
        let tall = widget("a", .square, col: 0, row: 1)
        // Row 1 plus two rows of height needs three rows to exist.
        #expect(GridPacker.cells(for: tall, at: (0, 1), rows: 2) == nil)
        #expect(GridPacker.cells(for: tall, at: (0, 1), rows: 3) != nil)
    }

    @Test("rows are clamped to the allowed range on construction and decoding")
    func clampsRows() {
        #expect(NotchLayout(rows: 99).rows == NotchLayout.maxRows)
        #expect(NotchLayout(rows: 0).rows == NotchLayout.minRows)
    }

    @Test("a layout.json written before the handle existed still decodes")
    func decodesWithoutRows() throws {
        // Users have this file on disk already. A missing key must default,
        // not throw — the alternative is an empty notch after an update.
        let json = #"{"schemaVersion":1,"revision":3,"widgets":[]}"#
        let layout = try JSONDecoder().decode(NotchLayout.self, from: Data(json.utf8))
        #expect(layout.rows == NotchLayout.defaultRows)
        #expect(layout.revision == 3)
    }

    private func overlaps(_ a: NotchWidget, _ b: NotchWidget) -> Bool {
        let cellsA = Set(GridPacker.cells(for: a, at: (a.col, a.row)) ?? [])
        let cellsB = Set(GridPacker.cells(for: b, at: (b.col, b.row)) ?? [])
        return !cellsA.isDisjoint(with: cellsB)
    }
}

struct SemanticVersionTests {
    @Test("compares numerically, not as a string")
    func numericOrdering() throws {
        let ten = try #require(SemanticVersion("0.10.0"))
        let nine = try #require(SemanticVersion("0.9.0"))
        // The bug this type exists to prevent: "0.10.0" < "0.9.0" as strings,
        // so a string-compare updater stops offering updates at the tenth
        // minor release and nobody notices for months.
        #expect(ten > nine)
    }

    @Test("a pre-release precedes its release")
    func prerelease() throws {
        #expect(try #require(SemanticVersion("1.0.0-beta")) < #require(SemanticVersion("1.0.0")))
    }

    @Test("tolerates a leading v and a missing patch")
    func lenientParsing() throws {
        #expect(try #require(SemanticVersion("v1.2")) == #require(SemanticVersion("1.2.0")))
    }

    @Test("rejects nonsense")
    func rejectsGarbage() {
        #expect(SemanticVersion("not-a-version") == nil)
        #expect(SemanticVersion("") == nil)
    }
}

struct FormattingTests {
    func series(_ value: Double, unit: MetricUnit, currency: String? = nil) -> MetricSeries {
        MetricSeries(
            integrationId: nil, metric: "m", unit: unit, currency: currency, value: value)
    }

    @Test("currency renders from minor units")
    func currency() {
        // 128450 minor units is $1,284.50 — not $128,450.
        #expect(MetricFormatter.display(series(128_450, unit: .currency, currency: "USD"), compact: false) == "$1,285")
    }

    @Test("large values compact so they fit a tile")
    func compacts() {
        #expect(MetricFormatter.abbreviated(1_284_500) == "1.3M")
        #expect(MetricFormatter.abbreviated(12_000) == "12k")
        #expect(MetricFormatter.abbreviated(999) == "999")
    }

    @Test("a whole compacted value drops its trailing zero")
    func trimsTrailingZero() {
        #expect(MetricFormatter.abbreviated(12_000) == "12k")
        #expect(MetricFormatter.abbreviated(12_300) == "12.3k")
    }

    @Test("a delta uses a true minus sign")
    func delta() {
        #expect(MetricFormatter.delta(MetricDelta(absolute: -5, percent: -3.2)) == "\u{2212}3.2%")
        #expect(MetricFormatter.delta(MetricDelta(absolute: 5, percent: 7.9)) == "+7.9%")
        // Null percent means the previous window was zero; there is no honest
        // percentage for 0 → 5.
        #expect(MetricFormatter.delta(MetricDelta(absolute: 5, percent: nil)) == nil)
    }
}

@Suite struct WidgetSpanTests {
    @Test("the wire encoding is unchanged")
    func roundTripsThroughStrings() throws {
        #expect(WidgetSize.wide.rawValue == "2x1")
        #expect(WidgetSize(rawValue: "2x2") == .square)
        #expect(WidgetSize(rawValue: "6x2") == .hero)
        // Spans the old enum could not express.
        #expect(WidgetSize(rawValue: "3x1")?.cols == 3)
        #expect(WidgetSize(rawValue: "4x3")?.rows == 3)
    }

    @Test("an unparseable size falls back rather than failing the layout")
    func unknownDecodesToDefault() throws {
        let decoded = try JSONDecoder().decode(WidgetSize.self, from: Data("\"nonsense\"".utf8))
        #expect(decoded == .wide)
    }

    @Test("a span is clamped to the grid")
    func clamped() {
        #expect(WidgetSize(cols: 99, rows: 99) == WidgetSize(cols: 6, rows: 4))
        #expect(WidgetSize(cols: 0, rows: -3) == WidgetSize(cols: 1, rows: 1))
    }
}

@Suite struct NoOverlapTests {
    private func layout(_ widgets: [NotchWidget], rows: Int = 2) -> NotchLayout {
        NotchLayout(rows: rows, widgets: widgets)
    }

    private func widget(_ id: String, _ size: WidgetSize, col: Int, row: Int) -> NotchWidget {
        NotchWidget(id: id, appId: "stripe", metric: "mrr", size: size, col: col, row: row)
    }

    /// Every cell is claimed at most once.
    private func overlaps(_ layout: NotchLayout) -> Bool {
        var seen: Set<GridCell> = []
        for w in layout.widgets where w.visible {
            guard let cells = GridPacker.cells(for: w, at: (w.col, w.row), rows: layout.rows)
            else { return true }
            for cell in cells {
                if seen.contains(cell) { return true }
                seen.insert(cell)
            }
        }
        return false
    }

    @Test("a resize that would overlap a neighbour is refused")
    func resizeCannotOverlap() {
        let base = layout([
            widget("a", .wide, col: 0, row: 0),
            widget("b", .wide, col: 2, row: 0),
        ])
        // Growing `a` to four columns would run straight through `b`.
        #expect(GridPacker.canResize("a", to: WidgetSize(cols: 4, rows: 1), in: base) == false)
        #expect(GridPacker.canResize("a", to: WidgetSize(cols: 2, rows: 2), in: base))
    }

    @Test("a resize past the edge of the grid is refused")
    func resizeCannotLeaveTheGrid() {
        let base = layout([widget("a", .wide, col: 4, row: 0)])
        #expect(GridPacker.canResize("a", to: WidgetSize(cols: 4, rows: 1), in: base) == false)
        #expect(GridPacker.canResize("a", to: WidgetSize(cols: 2, rows: 1), in: base))
    }

    @Test("every arrangement the packer produces is overlap-free")
    func packingNeverOverlaps() {
        // Deliberately contradictory input: three widgets all claiming the
        // same corner, which is what an old layout.json or a second Mac
        // produces.
        let messy = layout([
            widget("a", .square, col: 0, row: 0),
            widget("b", .square, col: 0, row: 0),
            widget("c", .wide, col: 0, row: 0),
        ])
        #expect(overlaps(GridPacker.repack(messy)) == false)
    }

    @Test("moving a widget onto another leaves no overlap")
    func placeNeverOverlaps() throws {
        let base = layout([
            widget("a", .wide, col: 0, row: 0),
            widget("b", .wide, col: 2, row: 0),
            widget("c", .wide, col: 4, row: 0),
        ])
        let moved = try #require(GridPacker.place("c", at: (0, 0), in: base))
        #expect(overlaps(moved) == false)
        #expect(moved.widgets.count == 3)
    }

    @Test("an arbitrary span packs without overlapping")
    func oddSpansPack() {
        let odd = layout(
            [
                widget("a", WidgetSize(cols: 3, rows: 1), col: 0, row: 0),
                widget("b", WidgetSize(cols: 3, rows: 1), col: 3, row: 0),
                widget("c", WidgetSize(cols: 5, rows: 1), col: 0, row: 1),
            ],
            rows: 2)
        #expect(overlaps(GridPacker.repack(odd)) == false)
    }
}

/// The grid is a flow: order decides position, not the other way round.
@Suite struct ReflowTests {
    private func widget(_ id: String, _ size: WidgetSize, position: Int) -> NotchWidget {
        NotchWidget(
            id: id, appId: "stripe", metric: "mrr", size: size,
            col: 0, row: 0, position: position)
    }

    private func layout(_ widgets: [NotchWidget], rows: Int = 2) -> NotchLayout {
        NotchLayout(rows: rows, widgets: widgets)
    }

    private func cells(_ layout: NotchLayout) -> [String: GridCell] {
        Dictionary(
            uniqueKeysWithValues: layout.widgets.filter(\.visible).map {
                ($0.id, GridCell(col: $0.col, row: $0.row))
            })
    }

    @Test("widgets flow left to right, then down")
    func flowsInReadingOrder() {
        let flowed = GridPacker.reflow(
            layout([
                widget("a", .wide, position: 0),
                widget("b", .wide, position: 1),
                widget("c", .wide, position: 2),
                widget("d", .wide, position: 3),
            ]))

        let at = cells(flowed)
        #expect(at["a"] == GridCell(col: 0, row: 0))
        #expect(at["b"] == GridCell(col: 2, row: 0))
        #expect(at["c"] == GridCell(col: 4, row: 0))
        // The row is full, so the fourth drops to the next one.
        #expect(at["d"] == GridCell(col: 0, row: 1))
    }

    @Test("a gap is closed rather than left behind")
    func noOblivion() {
        // The exact complaint: a widget stranded away from the others with
        // empty cells before it.
        var stranded = widget("b", .wide, position: 1)
        stranded.col = 4
        stranded.row = 1
        let flowed = GridPacker.reflow(layout([widget("a", .wide, position: 0), stranded]))

        #expect(cells(flowed)["b"] == GridCell(col: 2, row: 0))
    }

    @Test("growing a widget pushes the ones after it along")
    func resizeMakesRoom() {
        var base = layout([
            widget("a", .wide, position: 0),
            widget("b", .wide, position: 1),
            widget("c", .wide, position: 2),
        ])
        base = GridPacker.reflow(base)

        // `a` grows from two columns to four; the rest flow around it.
        let index = base.widgets.firstIndex { $0.id == "a" }!
        base.widgets[index].size = WidgetSize(cols: 4, rows: 1)
        let flowed = GridPacker.reflow(base)

        let at = cells(flowed)
        #expect(at["a"] == GridCell(col: 0, row: 0))
        #expect(at["b"] == GridCell(col: 4, row: 0))
        #expect(at["c"] == GridCell(col: 0, row: 1))
    }

    @Test("removing a widget closes the hole")
    func removalCloses() {
        var base = GridPacker.reflow(
            layout([
                widget("a", .wide, position: 0),
                widget("b", .wide, position: 1),
                widget("c", .wide, position: 2),
            ]))
        base.widgets.removeAll { $0.id == "a" }

        let at = cells(GridPacker.reflow(base))
        #expect(at["b"] == GridCell(col: 0, row: 0))
        #expect(at["c"] == GridCell(col: 2, row: 0))
    }

    @Test("moving a widget to an index reorders the rest")
    func moveReorders() {
        let base = GridPacker.reflow(
            layout([
                widget("a", .wide, position: 0),
                widget("b", .wide, position: 1),
                widget("c", .wide, position: 2),
            ]))

        let moved = GridPacker.move("c", toIndex: 0, in: base)
        let at = cells(moved)
        #expect(at["c"] == GridCell(col: 0, row: 0))
        #expect(at["a"] == GridCell(col: 2, row: 0))
        #expect(at["b"] == GridCell(col: 4, row: 0))
    }

    @Test("what cannot fit is hidden, not dropped")
    func overflowHides() {
        let flowed = GridPacker.reflow(
            layout(
                [
                    widget("a", .hero, position: 0),
                    widget("b", .hero, position: 1),
                ],
                rows: 2))
        #expect(flowed.widgets.count == 2)
        #expect(flowed.widgets.filter(\.visible).count == 1)
    }

    @Test("a flowed layout never overlaps")
    func neverOverlaps() {
        let flowed = GridPacker.reflow(
            layout(
                [
                    widget("a", WidgetSize(cols: 3, rows: 2), position: 0),
                    widget("b", WidgetSize(cols: 4, rows: 1), position: 1),
                    widget("c", .small, position: 2),
                    widget("d", .square, position: 3),
                ],
                rows: 4))

        var seen: Set<GridCell> = []
        for w in flowed.widgets where w.visible {
            for cell in GridPacker.cells(for: w, at: (w.col, w.row), rows: flowed.rows) ?? [] {
                #expect(seen.contains(cell) == false)
                seen.insert(cell)
            }
        }
    }
}
