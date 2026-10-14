import CoreGraphics
import Testing

@testable import MetricsCore
@testable import NotchUI

/// `GridGeometry` is shared by the renderer and the drag gesture on purpose:
/// the rectangle a tile is *drawn* in and the one a drop is *tested* against
/// must come from the same code, or a widget lands one cell from where it was
/// released and nobody can reproduce it.
struct GridGeometryTests {
    let available = CGSize(width: 640, height: 120)

    @Test("a cell round-trips from rect back to grid point")
    func roundTrip() {
        let grid = GridGeometry(available: available)
        for col in 0..<NotchLayout.columns {
            for row in 0..<NotchLayout.defaultRows {
                let rect = grid.rect(col: col, row: row, size: .small)
                let back = grid.gridPoint(at: CGPoint(x: rect.minX, y: rect.minY))
                #expect(back.col == col, "column \(col) did not round-trip")
                #expect(back.row == row, "row \(row) did not round-trip")
            }
        }
    }

    @Test("a point past the midline snaps forward, not back")
    func roundsRatherThanFloors() {
        let grid = GridGeometry(available: available)
        let first = grid.rect(col: 0, row: 0, size: .small)
        let stride = first.width + grid.spacing

        // 60% of the way into the gap towards column 1 should read as column 1.
        let past = CGPoint(x: first.minX + stride * 0.6, y: first.minY)
        #expect(grid.gridPoint(at: past).col == 1)

        let before = CGPoint(x: first.minX + stride * 0.4, y: first.minY)
        #expect(grid.gridPoint(at: before).col == 0)
    }

    @Test("a point outside the grid clamps instead of returning a bad index")
    func clamps() {
        let grid = GridGeometry(available: available)
        let farRight = grid.gridPoint(at: CGPoint(x: 10_000, y: 10_000))
        #expect(farRight.col == NotchLayout.columns - 1)
        #expect(farRight.row == grid.rows - 1)

        let negative = grid.gridPoint(at: CGPoint(x: -500, y: -500))
        #expect(negative.col == 0)
        #expect(negative.row == 0)
    }

    @Test("a wide widget's rect spans its cells plus the spacing between them")
    func spansSpacing() {
        let grid = GridGeometry(available: available)
        let small = grid.rect(col: 0, row: 0, size: .small)
        let wide = grid.rect(col: 0, row: 0, size: .wide)
        #expect(wide.width == small.width * 2 + grid.spacing)
    }

    @Test("the grid scales with the row count the handle sets")
    func scalesWithRows() {
        // The handle on the bottom edge drags rows in and out, so a cell's
        // height depends on how many there are — not on a constant.
        let two = GridGeometry(available: available, rows: 2)
        let four = GridGeometry(available: available, rows: 4)
        #expect(four.cellSize.height < two.cellSize.height)
        #expect(abs(four.contentSize.height - available.height) < 0.01)
        #expect(four.rows == 4)
    }

    @Test("content fills the space it was given")
    func fills() {
        let grid = GridGeometry(available: available)
        #expect(abs(grid.contentSize.width - available.width) < 0.01)
        #expect(abs(grid.contentSize.height - available.height) < 0.01)
    }

    @Test("a zero-sized container does not produce a divide by zero")
    func degenerate() {
        // GeometryReader reports .zero for a frame before first layout, and a
        // NaN cell size propagates into every offset in the view tree.
        let grid = GridGeometry(available: .zero)
        #expect(grid.cellSize.width >= 1)
        #expect(grid.cellSize.height >= 1)
        #expect(!grid.rect(col: 0, row: 0, size: .small).origin.x.isNaN)
    }
}

struct DownsamplerTests {
    @Test("a short series is returned untouched")
    func passesThrough() {
        let points = (0..<5).map { CGPoint(x: Double($0), y: Double($0)) }
        #expect(SeriesDownsampler.lttb(points, to: 10).count == 5)
    }

    @Test("downsampling keeps the endpoints and the requested count")
    func keepsEndpoints() {
        let points = (0..<500).map { CGPoint(x: Double($0), y: Double($0 % 7)) }
        let sampled = SeriesDownsampler.lttb(points, to: 40)
        #expect(sampled.count == 40)
        #expect(sampled.first == points.first)
        #expect(sampled.last == points.last)
    }

    @Test("a spike survives downsampling")
    func keepsSpikes() {
        // The reason this is LTTB and not every-nth sampling: naive sampling
        // lands between two spikes and draws a flat line through the month
        // that had the outage in it.
        var values = [Double](repeating: 1, count: 400)
        values[173] = 500
        let points = values.enumerated().map { CGPoint(x: Double($0.offset), y: $0.element) }
        let sampled = SeriesDownsampler.lttb(points, to: 30)
        #expect(sampled.contains { $0.y == 500 })
    }
}

/// The handle drag reports rows as a fraction, so every size derived from it
/// has to be rounded somewhere. If it is not, the panel's bottom edge spends
/// the whole gesture on half pixels and the 1pt stroke along it shimmers.
struct ViewportHeightTests {
    @Test("every height a drag can ask for is a whole number of points")
    func wholePoints() {
        for step in 0...80 {
            let rows = 1 + CGFloat(step) / 10
            let height = NotchWidgetCanvas.viewportHeight(rows: rows)
            #expect(height == height.rounded(), "\(rows) rows gave \(height)")
        }
    }

    @Test("rounding never takes a point away from the row it is showing")
    func neverRoundsDown() {
        for rows in [1.0, 1.5, 2.0, 2.5, 3.0, 4.75] as [CGFloat] {
            #expect(
                NotchWidgetCanvas.viewportHeight(rows: rows)
                    >= NotchWidgetCanvas.canvasHeight(rows: rows) + NotchWidgetCanvas.editInset * 2)
        }
    }

    @Test("a taller viewport is never shorter than a shorter one")
    func monotonic() {
        var last = CGFloat.zero
        for step in 0...80 {
            let height = NotchWidgetCanvas.viewportHeight(rows: 1 + CGFloat(step) / 10)
            #expect(height >= last)
            last = height
        }
    }
}
