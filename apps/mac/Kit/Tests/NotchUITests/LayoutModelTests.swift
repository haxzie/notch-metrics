import Testing

@testable import MetricsCore
@testable import NotchUI

/// The handle on the bottom edge drags rows in and out. The gesture itself is
/// a few lines; this is the behaviour behind it.
@MainActor
struct LayoutModelTests {
    func model(rows: Int = 2, widgets: [NotchWidget] = []) -> (NotchLayoutModel, Box) {
        let box = Box()
        let model = NotchLayoutModel(
            layout: NotchLayout(rows: rows, widgets: widgets),
            persist: { _ in box.saves += 1 })
        return (model, box)
    }

    final class Box: @unchecked Sendable {
        var saves = 0
    }

    @Test("adding a row works and is saved")
    func addsRow() {
        let (model, box) = model()
        #expect(model.setRows(3))
        #expect(model.layout.rows == 3)
        #expect(box.saves == 1)
    }

    @Test("the row count is clamped rather than refused at the ends")
    func clamps() {
        let (model, _) = model()
        model.setRows(99)
        #expect(model.layout.rows == NotchLayout.maxRows)
        model.setRows(-4)
        #expect(model.layout.rows == NotchLayout.minRows)
    }

    @Test("shrinking stops rather than dropping a widget off the grid")
    func refusesToOrphan() {
        // A widget sitting on the third row cannot survive a shrink to two,
        // so the handle simply stops — which is how a resize normally
        // communicates a limit. Silently deleting it would be the alternative.
        let (model, box) = model(
            rows: 3, widgets: [NotchWidget(id: "a", size: .small, col: 0, row: 2)])
        #expect(!model.setRows(2))
        #expect(model.layout.rows == 3)
        #expect(box.saves == 0)
    }

    @Test("a drag does not write a file on every frame")
    func doesNotPersistDuringDrag() {
        let (model, box) = model()
        // Each frame of a drag calls this; persisting per frame would mean
        // hundreds of writes for one gesture.
        model.setRows(3, commit: false)
        model.setRows(4, commit: false)
        #expect(model.layout.rows == 4)
        #expect(box.saves == 0)

        model.commitRows()
        #expect(box.saves == 1)
    }

    @Test("entering edit mode does not disturb the layout")
    func editingIsNonDestructive() {
        let (model, box) = model(widgets: [NotchWidget(id: "a", size: .square)])
        model.isEditing = true
        #expect(model.layout.widgets.count == 1)
        #expect(box.saves == 0)
    }

    @Test("a drag previews displacement without committing it")
    func previewsDrag() {
        let (model, box) = model(widgets: [
            NotchWidget(id: "a", size: .square, col: 0, row: 0),
            NotchWidget(id: "b", size: .square, col: 2, row: 0),
        ])

        model.beginDrag("b")
        model.dragMoved(to: (0, 0))

        // The preview shows the swap; the committed layout is untouched until
        // the gesture ends, which is what lets a cancelled drag snap back.
        #expect(model.displayed.widgets.first { $0.id == "b" }?.col == 0)
        #expect(model.layout.widgets.first { $0.id == "b" }?.col == 2)
        #expect(box.saves == 0)

        model.endDrag(commit: true)
        #expect(model.layout.widgets.first { $0.id == "b" }?.col == 0)
        #expect(box.saves == 1)
    }

    @Test("a cancelled drag leaves nothing behind")
    func cancelledDrag() {
        let (model, box) = model(widgets: [
            NotchWidget(id: "a", size: .square, col: 0, row: 0),
            NotchWidget(id: "b", size: .square, col: 2, row: 0),
        ])
        model.beginDrag("b")
        model.dragMoved(to: (0, 0))
        model.endDrag(commit: false)

        #expect(model.layout.widgets.first { $0.id == "b" }?.col == 2)
        #expect(model.displayed.widgets.first { $0.id == "b" }?.col == 2)
        #expect(box.saves == 0)
    }
}
