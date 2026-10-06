import CoreGraphics
import Testing

@testable import MetricsCore
@testable import NotchUI

/// Resizing by handle. The gesture is a few lines; this is what it drives.
@MainActor
struct ResizeTests {
    final class Box: @unchecked Sendable { var saves = 0 }

    private func widget(_ id: String, _ size: WidgetSize, col: Int, row: Int) -> NotchWidget {
        NotchWidget(id: id, appId: "stripe", metric: "mrr", size: size, col: col, row: row)
    }

    private func model(
        rows: Int = 2, _ widgets: [NotchWidget]
    ) -> (NotchLayoutModel, Box) {
        let box = Box()
        let model = NotchLayoutModel(
            layout: NotchLayout(rows: rows, widgets: widgets),
            persist: { _ in box.saves += 1 })
        return (model, box)
    }

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

    @Test("dragging the trailing edge grows the widget")
    func growsRight() {
        let (model, _) = model([widget("a", .wide, col: 0, row: 0)])
        model.beginResize("a")
        #expect(model.resizeMoved(to: (col: 0, row: 0, cols: 4, rows: 1)))
        model.endResize(commit: true)

        let a = model.layout.widgets.first { $0.id == "a" }
        #expect(a?.size == WidgetSize(cols: 4, rows: 1))
        #expect(a?.col == 0)
    }

    @Test("dragging the leading edge moves the origin and keeps the far edge")
    func growsLeft() {
        let (model, _) = model([widget("a", .wide, col: 3, row: 0)])
        model.beginResize("a")
        // The right edge was at column 4; dragging the left handle to column 1
        // should span 1...4.
        #expect(model.resizeMoved(to: (col: 1, row: 0, cols: 4, rows: 1)))
        model.endResize(commit: true)

        let a = model.layout.widgets.first { $0.id == "a" }
        #expect(a?.col == 1)
        #expect(a?.size.cols == 4)
    }

    @Test("a resize into a neighbour is refused, and the widget keeps its size")
    func refusesOverlap() {
        let (model, _) = model([
            widget("a", .wide, col: 0, row: 0),
            widget("b", .wide, col: 2, row: 0),
        ])
        model.beginResize("a")
        // Four columns from zero runs straight through `b`.
        #expect(model.resizeMoved(to: (col: 0, row: 0, cols: 4, rows: 1)) == false)
        model.endResize(commit: true)

        #expect(model.layout.widgets.first { $0.id == "a" }?.size == .wide)
        #expect(overlaps(model.layout) == false)
    }

    @Test("a resize past the edge of the grid is refused")
    func refusesOffGrid() {
        let (model, _) = model([widget("a", .wide, col: 4, row: 0)])
        model.beginResize("a")
        #expect(model.resizeMoved(to: (col: 4, row: 0, cols: 4, rows: 1)) == false)
        #expect(model.resizeMoved(to: (col: 4, row: 0, cols: 2, rows: 3)) == false)
    }

    @Test("a cancelled resize leaves the layout untouched")
    func cancelRestores() {
        let (model, box) = model([widget("a", .wide, col: 0, row: 0)])
        model.beginResize("a")
        #expect(model.resizeMoved(to: (col: 0, row: 0, cols: 5, rows: 1)))
        model.endResize(commit: false)

        #expect(model.layout.widgets.first { $0.id == "a" }?.size == .wide)
        #expect(box.saves == 0)
    }

    @Test("the preview is what the grid draws while resizing")
    func previewDrivesTheGrid() {
        let (model, _) = model([widget("a", .wide, col: 0, row: 0)])
        #expect(model.displayedWithResize.widgets.first?.size == .wide)

        model.beginResize("a")
        _ = model.resizeMoved(to: (col: 0, row: 0, cols: 5, rows: 1))
        // Mid-gesture the committed layout is still the old one; only the
        // preview has grown, so a cancel has nothing to undo.
        #expect(model.displayedWithResize.widgets.first?.size.cols == 5)
        #expect(model.layout.widgets.first?.size == .wide)
    }

    @Test("resizing never pushes a neighbour out of the way")
    func neighboursNeverMove() {
        // A resize that shoves its neighbours is impossible to aim.
        let (model, _) = model([
            widget("a", .wide, col: 0, row: 0),
            widget("b", .wide, col: 2, row: 0),
        ])
        let before = model.layout.widgets.first { $0.id == "b" }

        model.beginResize("a")
        _ = model.resizeMoved(to: (col: 0, row: 0, cols: 3, rows: 1))
        model.endResize(commit: true)

        let after = model.layout.widgets.first { $0.id == "b" }
        #expect(after?.col == before?.col)
        #expect(after?.row == before?.row)
    }
}

/// The gate that decides when a handle drag recomputes the span.
@MainActor
struct ResizeGateTests {
    private let origin = CGPoint(x: 100, y: 100)

    @Test("a vertical handle ignores sideways movement entirely")
    func verticalIgnoresHorizontal() {
        // The reported bug: pulling the bottom handle down while the hand
        // drifts sideways retargeted the column.
        let wandered = CGPoint(x: 160, y: 102)
        #expect(ResizeGate.shouldReevaluate(anchor: .bottom, from: origin, to: wandered) == false)
        #expect(ResizeGate.shouldReevaluate(anchor: .top, from: origin, to: wandered) == false)
    }

    @Test("a horizontal handle ignores vertical movement entirely")
    func horizontalIgnoresVertical() {
        let wandered = CGPoint(x: 102, y: 160)
        #expect(ResizeGate.shouldReevaluate(anchor: .leading, from: origin, to: wandered) == false)
        #expect(ResizeGate.shouldReevaluate(anchor: .trailing, from: origin, to: wandered) == false)
    }

    @Test("movement on the controlled axis passes once it clears the threshold")
    func passesOnItsOwnAxis() {
        #expect(
            ResizeGate.shouldReevaluate(
                anchor: .bottom, from: origin, to: CGPoint(x: 100, y: 100 + ResizeGate.threshold)))
        #expect(
            ResizeGate.shouldReevaluate(
                anchor: .trailing, from: origin, to: CGPoint(x: 100 + ResizeGate.threshold, y: 100))
        )
    }

    @Test("a tremor below the threshold changes nothing")
    func ignoresTremor() {
        let tremor = CGPoint(x: 103, y: 104)
        for anchor in ResizeAnchor.allCases {
            #expect(ResizeGate.shouldReevaluate(anchor: anchor, from: origin, to: tremor) == false)
        }
    }

    @Test("a corner answers to either axis")
    func cornersTakeBoth() {
        #expect(
            ResizeGate.shouldReevaluate(
                anchor: .bottomTrailing, from: origin, to: CGPoint(x: 100, y: 120)))
        #expect(
            ResizeGate.shouldReevaluate(
                anchor: .bottomTrailing, from: origin, to: CGPoint(x: 120, y: 100)))
    }
}
