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

    @Test("dragging the leading edge changes the span, and the flow places it")
    func growsLeft() {
        let (model, _) = model([widget("a", .wide, col: 3, row: 0)])
        model.beginResize("a")
        #expect(model.resizeMoved(to: (col: 1, row: 0, cols: 4, rows: 1)))
        model.endResize(commit: true)

        let a = model.layout.widgets.first { $0.id == "a" }
        #expect(a?.size.cols == 4)
        // The column is not the handle's to set. In a flow the position comes
        // from the order, so the only widget flows to the start.
        #expect(a?.col == 0)
    }

    @Test("growing into a neighbour pushes it along rather than being refused")
    func resizeMakesRoom() {
        // Refusing when anything was in the way meant resizing only worked on
        // the last widget in the grid, which is to say it mostly did not.
        let (model, _) = model([
            widget("a", .wide, col: 0, row: 0),
            widget("b", .wide, col: 2, row: 0),
        ])
        model.beginResize("a")
        #expect(model.resizeMoved(to: (col: 0, row: 0, cols: 4, rows: 1)))
        model.endResize(commit: true)

        #expect(model.layout.widgets.first { $0.id == "a" }?.size.cols == 4)
        #expect(model.layout.widgets.first { $0.id == "b" }?.col == 4)
        #expect(overlaps(model.layout) == false)
    }

    @Test("a resize past the side of the grid is refused")
    func refusesOffGrid() {
        let (model, _) = model([widget("a", .wide, col: 4, row: 0)])
        model.beginResize("a")
        // Width is still a wall: there is no seventh column to grow into.
        #expect(model.resizeMoved(to: (col: 4, row: 0, cols: 8, rows: 1)) == false)
    }

    @Test("a span taller than the viewport is clamped, not refused")
    func clampsTallSpans() {
        // Height stopped being a wall when the area began to scroll. The
        // viewport is no longer the bound — the flow behind it is far taller —
        // so the only limit left is WidgetSize's own, and passing it clamps.
        // Refusing instead would make the bottom handle stick for a reason
        // nothing on screen explains.
        let (model, _) = model([widget("a", .wide, col: 0, row: 0)])
        model.beginResize("a")
        #expect(model.resizeMoved(to: (col: 0, row: 0, cols: 6, rows: 9)))
        model.endResize(commit: true)

        #expect(model.layout.widgets.first { $0.id == "a" }?.size.rows == WidgetSize.maxRows)
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

    @Test("neighbours keep their order while they make room")
    func orderSurvivesAResize() {
        // They move, but they do not reshuffle: the grid is a flow, so what a
        // resize changes is where the others land, never the order they are in.
        let (model, _) = model([
            widget("a", .wide, col: 0, row: 0),
            widget("b", .wide, col: 2, row: 0),
            widget("c", .wide, col: 4, row: 0),
        ])
        model.beginResize("a")
        _ = model.resizeMoved(to: (col: 0, row: 0, cols: 4, rows: 1))
        model.endResize(commit: true)

        let order = model.layout.widgets.sorted { $0.position < $1.position }.map(\.id)
        #expect(order == ["a", "b", "c"])
        #expect(overlaps(model.layout) == false)
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
