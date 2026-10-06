import MetricsCore
import SwiftUI

/// Converts between grid coordinates and points.
///
/// A value type shared by the renderer and the drag gesture, so the rectangle
/// a tile is drawn in and the rectangle a drop is tested against are computed
/// by the same code. Two implementations of this is how a widget ends up
/// landing one cell left of where it was released.
public struct GridGeometry: Equatable, Sendable {
    public let cellSize: CGSize
    public let spacing: CGFloat
    public let origin: CGPoint
    public let rows: Int

    public init(
        available: CGSize, rows: Int = NotchLayout.defaultRows,
        spacing: CGFloat = 10, origin: CGPoint = .zero
    ) {
        self.spacing = spacing
        self.origin = origin
        self.rows = max(1, rows)
        let totalSpacingX = spacing * CGFloat(NotchLayout.columns - 1)
        let totalSpacingY = spacing * CGFloat(self.rows - 1)
        self.cellSize = CGSize(
            width: max(1, (available.width - totalSpacingX) / CGFloat(NotchLayout.columns)),
            height: max(1, (available.height - totalSpacingY) / CGFloat(self.rows))
        )
    }

    /// One row's worth of height, including the gap above it. The handle drag
    /// converts a pointer offset into rows with this.
    public var rowStride: CGFloat { cellSize.height + spacing }

    public func rect(for widget: NotchWidget) -> CGRect {
        rect(col: widget.col, row: widget.row, size: widget.size)
    }

    public func rect(col: Int, row: Int, size: WidgetSize) -> CGRect {
        CGRect(
            x: origin.x + CGFloat(col) * (cellSize.width + spacing),
            y: origin.y + CGFloat(row) * (cellSize.height + spacing),
            width: CGFloat(size.cols) * cellSize.width + CGFloat(size.cols - 1) * spacing,
            height: CGFloat(size.rows) * cellSize.height + CGFloat(size.rows - 1) * spacing
        )
    }

    /// The cell a point falls in, clamped to the grid.
    ///
    /// Rounded rather than floored, so a tile dropped slightly past the midline
    /// of a cell snaps forward — which is what the eye expects, and what
    /// flooring gets subtly wrong on every drag.
    /// The cell a point is *inside*, floored and clamped.
    ///
    /// Distinct from `gridPoint`, which rounds because a dragged tile should
    /// snap forward past the midline. A resize handle wants the cell the
    /// pointer is actually over, inclusive — rounding there makes the last
    /// column unreachable and the first one sticky.
    public func cellIndex(at location: CGPoint) -> (col: Int, row: Int) {
        let col = Int(((location.x - origin.x) / (cellSize.width + spacing)).rounded(.down))
        let row = Int(((location.y - origin.y) / (cellSize.height + spacing)).rounded(.down))
        return (
            min(max(0, col), NotchLayout.columns - 1),
            min(max(0, row), rows - 1)
        )
    }

    public func gridPoint(at location: CGPoint) -> (col: Int, row: Int) {
        let col = Int(((location.x - origin.x) / (cellSize.width + spacing)).rounded())
        let row = Int(((location.y - origin.y) / (cellSize.height + spacing)).rounded())
        return (
            min(max(0, col), NotchLayout.columns - 1),
            min(max(0, row), rows - 1)
        )
    }

    public var contentSize: CGSize {
        CGSize(
            width: CGFloat(NotchLayout.columns) * cellSize.width
                + CGFloat(NotchLayout.columns - 1) * spacing,
            height: CGFloat(rows) * cellSize.height + CGFloat(rows - 1) * spacing
        )
    }
}

/// Owns the layout and the in-progress drag.
@MainActor
@Observable
public final class NotchLayoutModel {
    public private(set) var layout: NotchLayout
    /// A copy mutated during a drag so displacement animates live. Committing
    /// is just keeping it; cancelling is discarding it.
    public private(set) var preview: NotchLayout?
    public private(set) var draggingID: String?
    public var isEditing = false

    private let persist: @Sendable (NotchLayout) -> Void

    public init(layout: NotchLayout = NotchLayout(), persist: @escaping @Sendable (NotchLayout) -> Void = { _ in }) {
        self.layout = layout
        self.persist = persist
    }

    public var displayed: NotchLayout { preview ?? layout }

    /// Accepts a layout from disk or from the server.
    ///
    /// Repacked rather than trusted: an older `layout.json` was written
    /// against a different grid, and a `PUT /v1/widgets` from another Mac can
    /// carry anything. Overlapping tiles render on top of each other.
    public func replace(with layout: NotchLayout) {
        self.layout = GridPacker.reflow(layout)
    }

    public func beginDrag(_ id: String) {
        draggingID = id
        isEditing = true
        preview = layout
    }

    /// Runs the packer against a copy, so the user sees the rearrangement
    /// that dropping here would cause before they commit to it.
    ///
    /// A drop is an *index* in reading order, not a pair of coordinates. The
    /// grid flows, so "put it here" means "put it after these" — and
    /// everything else reflows around it rather than being shoved into
    /// whatever cell happened to be free.
    public func dragMoved(to origin: (col: Int, row: Int)) {
        guard let draggingID else { return }
        let index = GridPacker.index(at: origin, in: layout, excluding: draggingID)
        preview = GridPacker.move(draggingID, toIndex: index, in: layout)
    }

    public func endDrag(commit: Bool) {
        if commit, let preview {
            layout = preview
            persist(layout)
        }
        preview = nil
        draggingID = nil
    }

    /// Switches between the grid and the list.
    ///
    /// Leaves edit mode on the way: the two views have different affordances —
    /// the grid resizes tiles, the list removes rows — and staying in edit
    /// mode across the switch leaves handles on screen that do nothing.

    /// Sets the number of grid rows, dropping the preview used while dragging.
    ///
    /// Shrinking is refused when a widget would be left off the grid rather
    /// than silently dropping it — the handle just stops, which is the normal
    /// way a resize communicates a limit.
    @discardableResult
    public func setRows(_ rows: Int, commit: Bool = true) -> Bool {
        let wanted = rows.clamped(to: NotchLayout.minRows...NotchLayout.maxRows)
        guard wanted != layout.rows else { return true }

        var next = layout
        next.rows = wanted
        let fits = next.widgets.allSatisfy { widget in
            GridPacker.cells(for: widget, at: (widget.col, widget.row), rows: wanted) != nil
        }
        guard fits else { return false }

        layout = next
        if commit { persist(layout) }
        return true
    }

    /// Writes the row count reached by a drag.
    ///
    /// The drag itself passes `commit: false` on every frame — persisting a
    /// file per frame would be absurd — so the gesture ending is what saves.
    public func commitRows() {
        persist(layout)
    }

    public func resize(_ id: String, to size: WidgetSize) {
        guard GridPacker.canResize(id, to: size, in: layout),
              let index = layout.widgets.firstIndex(where: { $0.id == id })
        else { return }
        layout.widgets[index].size = size
        layout = GridPacker.reflow(layout)
        persist(layout)
    }

    // MARK: - Resizing by handle

    /// The widget being resized, and what it looked like before.
    public private(set) var resizingID: String?
    private var resizeOriginal: (col: Int, row: Int, size: WidgetSize)?

    public private(set) var resizePreview: NotchLayout?

    /// What the grid should draw: the in-progress resize, then the in-progress
    /// drag, then the committed layout.
    public var displayedWithResize: NotchLayout { resizePreview ?? displayed }

    public func beginResize(_ id: String) {
        guard let widget = layout.widgets.first(where: { $0.id == id }) else { return }
        resizingID = id
        resizeOriginal = (widget.col, widget.row, widget.size)
        resizePreview = layout
    }

    /// Applies a resize expressed in grid cells.
    ///
    /// Takes the whole target rectangle rather than a delta, because dragging
    /// a top or left handle moves the origin as well as the span, and
    /// expressing that as two separate mutations lets the tile flicker
    /// through an invalid intermediate.
    ///
    /// A target that would overlap or leave the grid is ignored rather than
    /// clamped to something else: the tile simply stops at the last legal
    /// size, which is how every resize in every other app behaves.
    @discardableResult
    public func resizeMoved(to rect: (col: Int, row: Int, cols: Int, rows: Int)) -> Bool {
        guard let id = resizingID else { return false }

        let size = WidgetSize(cols: rect.cols, rows: rect.rows)
        guard rect.col >= 0, rect.row >= 0, rect.col + size.cols <= NotchLayout.columns
        else { return false }

        var candidate = layout
        guard let index = candidate.widgets.firstIndex(where: { $0.id == id }) else { return false }
        candidate.widgets[index].size = size

        // The grid flows, so a resize does not have to find empty space — it
        // takes the space it wants and everything after it reflows around the
        // new shape. Refusing when a neighbour was in the way meant resizing
        // only worked on the last widget in the grid, which is to say it
        // mostly did not work.
        let reflowed = GridPacker.reflow(candidate)

        // The one thing still worth refusing: a span that cannot fit the grid
        // at all, which would push the widget itself into the hidden pile.
        guard reflowed.widgets.first(where: { $0.id == id })?.visible == true else { return false }

        resizePreview = reflowed
        return true
    }

    public func endResize(commit: Bool) {
        defer {
            resizingID = nil
            resizeOriginal = nil
            resizePreview = nil
        }
        guard commit, let preview = resizePreview else { return }
        layout = preview
        persist(layout)
    }

    public func remove(_ id: String) {
        layout.widgets.removeAll { $0.id == id }
        // Reflowed, so removing a tile closes the hole it leaves rather than
        // stranding the ones after it.
        layout = GridPacker.reflow(layout)
        persist(layout)
    }

    public func add(_ widget: NotchWidget) -> Bool {
        guard let next = GridPacker.append(widget, to: layout) else { return false }
        layout = next
        persist(layout)
        return true
    }
}
