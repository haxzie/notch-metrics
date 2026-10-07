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

    @Test("shrinking hides a row rather than dropping the widget on it")
    func shrinkingScrollsRatherThanOrphans() {
        // Shrinking used to be refused outright when a widget sat on a row
        // that would disappear. The area scrolls now, so the handle only
        // changes how much is revealed — the widget is below the fold, not
        // gone, and `contentRows` still counts it.
        let (model, box) = model(
            rows: 3, widgets: [NotchWidget(id: "a", size: .small, col: 0, row: 2)])
        let shrank = model.setRows(2)
        #expect(shrank)
        #expect(model.layout.rows == 2)
        #expect(model.layout.contentRows == 3)
        #expect(model.layout.widgets[0].visible)
        #expect(box.saves == 1)
    }

    @Test("a full viewport grows to meet a new widget instead of refusing it")
    func addingGrowsTheViewport() {
        // Six 1x1 tiles fill a two-row grid's first row and then some; the
        // seventh used to have nowhere to go and `add` returned false, which
        // read in the UI as the button doing nothing.
        let (model, _) = model(
            rows: 1,
            widgets: (0..<6).map { NotchWidget(id: "w\($0)", size: .small, col: $0, row: 0) })

        let added = model.add(NotchWidget(id: "new", size: .small))
        #expect(added)
        #expect(model.layout.widgets.count == 7)
        #expect(model.layout.widgets.filter(\.visible).count == 7)
        // The viewport grew to show the row the new widget landed on.
        #expect(model.layout.rows == 2)
    }

    @Test("past the tallest viewport, adding keeps working and scrolls")
    func addingBeyondTheViewport() {
        let many = (0..<(6 * NotchLayout.maxRows)).map {
            NotchWidget(id: "w\($0)", size: .small, col: $0 % 6, row: $0 / 6)
        }
        let (model, _) = model(rows: NotchLayout.maxRows, widgets: many)

        let added = model.add(NotchWidget(id: "extra", size: .small))
        #expect(added)
        #expect(model.layout.widgets.first { $0.id == "extra" }?.visible == true)
        // The window cannot grow past its cap, so the content runs past it.
        #expect(model.layout.rows == NotchLayout.maxRows)
        #expect(model.layout.contentRows == NotchLayout.maxRows + 1)
    }

    @Test("the handle follows the pointer between detents and snaps on release")
    func handleDragIsContinuous() {
        let (model, box) = model(rows: 2)
        model.dragRows(to: 2.4)
        // Followed exactly while held: rounding every frame made the panel
        // jump a whole row under a pointer that was moving smoothly.
        #expect(model.visibleRows == 2.4)
        #expect(model.layout.rows == 2)
        #expect(box.saves == 0)

        model.endRowDrag()
        #expect(model.layout.rows == 2)

        model.dragRows(to: 2.6)
        model.endRowDrag()
        #expect(model.layout.rows == 3)
        #expect(model.visibleRows == 3)
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

        model.endRowDrag()
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
