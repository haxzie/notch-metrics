import MetricsCore
import SwiftUI

/// Carries the rendered panel size back up to the controller.
struct PanelSizeKey: PreferenceKey {
    static let defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

public enum NotchPresentation: Equatable, Sendable {
    case collapsed
    /// Reserved for the always-on compact metric. Nothing renders it yet — the
    /// collapsed notch is deliberately invisible — but the state exists so
    /// adding it later is a view, not a refactor of the whole presentation
    /// machinery.
    case hinting
    case expanded
}

/// What the panel hosts.
///
/// The canvas is always `NotchPanel.maxSize`; only the content inside it
/// changes. Expansion is therefore a SwiftUI layout animation with no window
/// resize anywhere in it.
public struct NotchContentView: View {
    @Bindable public var model: NotchLayoutModel
    @Bindable public var view: NotchViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isResizing = false
    @State private var rowsAtDragStart = NotchLayout.defaultRows

    public init(model: NotchLayoutModel, view: NotchViewModel) {
        self.model = model
        self.view = view
    }

    private var presentation: NotchPresentation { view.presentation }
    private var geometry: NotchGeometry { view.geometry }
    private var states: [String: TileState] { view.states }
    private var appOverrides: [String: MetricApp] { view.appOverrides }
    private var isPinned: Bool { view.isPinned }
    private var onOpenSettings: () -> Void { view.onOpenSettings }
    private var onTogglePin: () -> Void { view.onTogglePin }
    private var onClose: () -> Void { view.onClose }

    public var body: some View {
        VStack(spacing: 0) {
            panel
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The controller already wraps the state change in a transaction, so
        // this is the fallback for changes that arrive from SwiftUI's side —
        // the resize handle, a widget being removed.
        .animation(
            presentation == .expanded
                ? NotchMotion.expansion(reduceMotion: reduceMotion)
                : NotchMotion.collapse(reduceMotion: reduceMotion),
            value: presentation)
    }

    private var panel: some View {
        let shape = NotchShape(
            topCornerRadius: presentation == .expanded ? 12 : 0,
            bottomCornerRadius: presentation == .expanded ? 26 : notchBottomRadius
        )

        return ZStack(alignment: .top) {
            // Frosted glass, then a dark tint over it. The material alone goes
            // milky over a bright wallpaper and the white figures stop being
            // readable; the tint restores contrast while keeping the blur.
            shape
                .fill(NotchTheme.surfaceMaterial)
                .overlay(shape.fill(NotchTheme.surfaceTint))
                .overlay(shape.stroke(NotchTheme.panelStroke, lineWidth: 1))
                .compositingGroup()
                .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
                // Collapsed, the shape is drawn at exactly the notch's size and
                // fully transparent, so the hardware notch looks untouched.
                .opacity(presentation == .expanded ? 1 : (geometry.hasNotch ? 0 : 0.95))

            if presentation == .expanded {
                expandedContent
                    .transition(NotchMotion.content(reduceMotion: reduceMotion))
            }
        }
        .frame(
            width: presentation == .expanded ? expandedSize.width : collapsedSize.width,
            height: presentation == .expanded ? expandedSize.height : collapsedSize.height
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PanelSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PanelSizeKey.self) { size in
            // Back to the controller, which uses it to decide when the
            // pointer has left.
            MainActor.assumeIsolated { view.visiblePanelSize = size }
        }
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            header
            content
            grabber
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.displayed.display {
        case .grid:
            NotchWidgetCanvas(model: model, states: states, appOverrides: appOverrides)
                .padding(.horizontal, 16)
        case .list:
            NotchListView(model: model, states: states, appOverrides: appOverrides)
                .padding(.horizontal, 10)
        }
    }

    /// Brand on the left, controls on the right, the camera housing between.
    ///
    /// The header is exactly as tall as the physical notch and the middle of
    /// it is deliberately empty — that span is occupied by hardware, and
    /// anything placed there is invisible.
    private var header: some View {
        HStack(spacing: 7) {
            NotchLogo(size: 17)
            Text("Notch Metrics")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.secondaryText)

            Spacer(minLength: 0)
            // The width of the camera housing, kept clear.
            Color.clear.frame(width: geometry.hasNotch ? geometry.notchRect.width : 0)
            Spacer(minLength: 0)

            // No edit-mode hint here. The header's right half sits under the
            // camera housing on a notched display, so the text was half
            // hidden on exactly the machines this app is for — and the
            // selection outline and handles say what to do without words.
            if hiddenCount > 0 {
                // The grid ran out of room. Saying so — and offering the view
                // that has room — beats silently showing fewer numbers than
                // the user added.
                Button {
                    model.setDisplay(.list)
                } label: {
                    Text("+\(hiddenCount) more")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NotchTheme.secondaryText)
                .help("Show them all in the list view")
                .transition(.opacity)
            }

            headerButton(
                model.displayed.display.toggled.symbol,
                // Shows the mode it switches *to*, which is the only reading
                // of a single-button toggle that does not need a legend.
                help: "Switch to \(model.displayed.display.toggled.label.lowercased()) view",
                action: { model.setDisplay(model.layout.display.toggled) })
            headerButton(
                model.isEditing ? "checkmark" : "pencil",
                help: model.isEditing ? "Done" : "Edit layout",
                active: model.isEditing,
                action: toggleEditing)
            headerButton("slider.horizontal.3", help: "Settings", action: onOpenSettings)
            headerButton("xmark", help: "Close", action: onClose)
        }
        .padding(.horizontal, 16)
        .frame(height: max(34, geometry.hasNotch ? geometry.notchRect.height + 6 : 34))
    }

    private func headerButton(
        _ symbol: String, help: String, active: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(active ? NotchTheme.editHighlight.opacity(0.22) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? NotchTheme.editHighlight : NotchTheme.secondaryText)
        .help(help)
    }

    /// Widgets the grid could not find room for. Always zero in list view,
    /// which has no fixed capacity.
    private var hiddenCount: Int {
        guard model.displayed.display == .grid else { return 0 }
        return model.displayed.widgets.count { !$0.visible }
    }

    /// Entering edit mode pins the notch open.
    ///
    /// Without that, the first drag that takes the pointer towards the edge
    /// ends the hover and collapses the panel mid-gesture — so rearranging
    /// would be impossible for exactly the users most likely to try it.
    private func toggleEditing() {
        let next = !model.isEditing
        model.isEditing = next
        if next != isPinned { onTogglePin() }
    }

    /// The handle at the bottom edge. Drag it down to add a row of widgets,
    /// up to remove one.
    ///
    /// Rows rather than free pixels: the notch is a grid, and a height that
    /// does not correspond to a whole number of rows leaves a strip of empty
    /// glass under the last tile. Snapping also means the drag has detents,
    /// which is what makes it feel like a control rather than a scrollbar.
    private var grabber: some View {
        Capsule()
            .fill(isResizing ? NotchTheme.editHighlight : Color.white.opacity(0.22))
            .frame(width: isResizing ? 56 : 44, height: 4)
            .padding(.vertical, 8)
            // The hit area is the full width and taller than the capsule: a
            // 44x4 target is below every sane minimum, and this is the only
            // way to change the height.
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                // A resize cursor is the only thing that says "this is a
                // handle" before the user has already tried dragging it.
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(resizeGesture)
            .animation(.easeOut(duration: 0.14), value: isResizing)
            .accessibilityLabel("Resize")
            .accessibilityValue("\(model.displayed.rows) rows")
            .accessibilityAdjustableAction { direction in
                model.setRows(model.layout.rows + (direction == .increment ? 1 : -1))
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !isResizing {
                    isResizing = true
                    rowsAtDragStart = model.layout.rows
                }
                // Half a row of travel flips to the next detent, so the handle
                // tracks the pointer rather than lagging a full row behind it.
                let stride = NotchWidgetCanvas.rowHeight + NotchWidgetCanvas.rowSpacing
                let delta = Int((value.translation.height / stride).rounded())
                model.setRows(rowsAtDragStart + delta, commit: false)
            }
            .onEnded { _ in
                isResizing = false
                model.commitRows()
            }
    }


    private var collapsedSize: CGSize {
        geometry.hasNotch
            ? CGSize(width: geometry.notchRect.width, height: geometry.notchRect.height)
            // No notch: a small visible pill, because there is nothing on the
            // bezel to aim at and an invisible trigger would be undiscoverable.
            : CGSize(width: 120, height: 6)
    }

    /// Sized to its content, not to the window.
    ///
    /// The *panel* is always NotchPanel.maxSize — that is what keeps expansion
    /// free of a window resize. The visible shape inside it has to stop where
    /// the content does, or the notch hangs a strip of empty black down the
    /// screen below the last row of tiles.
    private var expandedSize: CGSize {
        let header = max(34, geometry.hasNotch ? geometry.notchRect.height + 6 : 34)
        // The two modes are different shapes, so the panel cannot assume the
        // grid's. A list of six rows in a four-row-tall notch was leaving a
        // hand's width of empty glass under the last one.
        let body =
            switch model.displayed.display {
            case .grid: NotchWidgetCanvas.canvasHeight(rows: model.displayed.rows)
            case .list: NotchListView.height(for: model.displayed, overrides: appOverrides)
            }
        let content = body + Self.grabberHeight
        return CGSize(
            width: min(NotchPanel.maxSize.width, max(560, geometry.notchRect.width + 480)),
            height: min(NotchPanel.maxSize.height, header + content)
        )
    }

    static let grabberHeight: CGFloat = 19

    private var notchBottomRadius: CGFloat { geometry.hasNotch ? 8 : 3 }
}

/// The widget grid.
///
/// Manual frames in a `ZStack`, not a custom `Layout` conformance. `Layout` is
/// the right tool when positions are *derived* — a flow, a masonry. Here they
/// are explicit state the user drags, and the gesture needs the same frame
/// maths anyway, so a `Layout` would mean duplicating `GridGeometry` inside
/// `placeSubviews` while giving nothing for hit testing or the displacement
/// preview.
public struct NotchWidgetCanvas: View {
    @Bindable public var model: NotchLayoutModel
    public let states: [String: TileState]
    public let appOverrides: [String: MetricApp]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Live pointer offset for the tile being dragged.
    ///
    /// The tile used to be drawn only at whole grid cells, so it jumped a
    /// cell at a time while the pointer moved smoothly — which is what made
    /// dragging feel jittery. It now follows the cursor exactly, and the grid
    /// snap is what happens to *everything else*.
    @State private var dragTranslation: CGSize = .zero
    /// Where the dragged tile started, so it is drawn relative to that rather
    /// than to the preview layout it is busy rearranging.
    @State private var dragOrigin: CGPoint = .zero
    /// The last cell handed to the packer. Re-running it on every mouse-move
    /// restarts the displacement animation ~120 times a second, which is the
    /// other half of the jitter.
    @State private var lastCell: GridCell?
    @State private var selectedID: String?

    public init(
        model: NotchLayoutModel,
        states: [String: TileState],
        appOverrides: [String: MetricApp] = [:]
    ) {
        self.model = model
        self.states = states
        self.appOverrides = appOverrides
    }

    public var body: some View {
        GeometryReader { proxy in
            let grid = GridGeometry(available: proxy.size, rows: model.displayed.rows)
            let layout = model.displayedWithResize

            ZStack(alignment: .topLeading) {
                if model.isEditing {
                    // A darker surface behind the tiles, so edit mode reads as
                    // a different place rather than the same panel with specks
                    // on it. Inset outwards so the dots run past the tiles
                    // rather than stopping flush against the outermost one.
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            DottedGrid(pitch: 11, opacity: 0.1)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )
                        .frame(
                            width: grid.contentSize.width + 16,
                            height: grid.contentSize.height + 16)
                        .offset(x: -8, y: -8)
                        .transition(.opacity)
                }

                // A notch with nothing in it has to say so. There used to be
                // three seeded Stripe tiles here instead, which meant every
                // new user's notch was full of an app they had never
                // connected, each tile reading "Connect Stripe".
                if layout.widgets.isEmpty {
                    EmptyNotch()
                        .frame(width: grid.contentSize.width, height: grid.contentSize.height)
                }

                // Filtered, because `repack` marks what it could not place as
                // not visible rather than dropping it. Rendering those draws
                // them all at the origin, on top of each other and of the
                // tiles that did fit — which reads as a rendering fault.
                ForEach(layout.widgets.filter(\.visible)) { widget in
                    let isDragging = model.draggingID == widget.id
                    let frame = grid.rect(for: widget)
                    // The dragged tile is positioned from where it started
                    // plus the pointer offset. Using its *preview* frame would
                    // animate it to the cell it is hovering while it is also
                    // following the cursor — two movements fighting.
                    let x = isDragging ? dragOrigin.x + dragTranslation.width : frame.minX
                    let y = isDragging ? dragOrigin.y + dragTranslation.height : frame.minY

                    WidgetTile(
                        widget: widget,
                        app: widget.app(overrides: appOverrides),
                        state: states[widget.id] ?? .loading,
                        isEditing: model.isEditing
                    )
                    .frame(width: frame.width, height: frame.height)
                    // Inside the animation below, deliberately. Applied after
                    // `.animation` the outline is outside its scope, so it
                    // jumps to the destination frame while the tile is still
                    // gliding there — selection and tile visibly out of step
                    // for the length of every move.
                    .overlay {
                        if model.isEditing, selectedID == widget.id {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(NotchTheme.editHighlight, lineWidth: 1.5)
                                ResizeHandles(
                                    onChanged: { anchor, point in
                                        resize(widget, anchor: anchor, to: point, grid: grid)
                                    },
                                    onEnded: { model.endResize(commit: true) })
                            }
                        }
                    }
                    .offset(x: x, y: y)
                    .scaleEffect(isDragging ? 1.04 : 1)
                    .shadow(color: .black.opacity(isDragging ? 0.4 : 0), radius: 12, y: 4)
                    .zIndex(isDragging ? 1 : 0)
                    .opacity(isDragging ? 0.92 : 1)
                    // The dragged tile must not inherit the container's
                    // layout animation, or it lags behind the cursor by the
                    // spring's duration.
                    .animation(isDragging ? nil : .snappy(duration: 0.2), value: frame)
                    .onTapGesture {
                        guard model.isEditing else { return }
                        selectedID = selectedID == widget.id ? nil : widget.id
                    }
                    .gesture(dragGesture(for: widget, grid: grid, frame: frame))
                    .simultaneousGesture(
                        // Simultaneous, not `.onLongPressGesture`: as a plain
                        // modifier it competes with the drag for the same
                        // press and swallows the first few points of movement.
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in model.isEditing = true }
                    )
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: layout)
            .animation(.easeOut(duration: 0.16), value: model.isEditing)
            .coordinateSpace(name: "notch-grid")
        }
        .frame(height: Self.canvasHeight(rows: model.displayed.rows))
    }

    /// One row is tall enough for a label over a headline figure; each extra
    /// row adds the same again plus the gap between them.
    static let rowHeight: CGFloat = 84
    static let rowSpacing: CGFloat = 10

    static func canvasHeight(rows: Int) -> CGFloat {
        CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * rowSpacing
    }

    /// Turns a handle drag into a target rectangle in grid cells.
    ///
    /// The opposite edge is the anchor and never moves, which is what makes a
    /// resize aimable: dragging the left handle changes the left edge only,
    /// and the right edge stays exactly where the eye expects it.
    private func resize(
        _ widget: NotchWidget, anchor: ResizeAnchor, to point: CGPoint, grid: GridGeometry
    ) {
        if model.resizingID != widget.id { model.beginResize(widget.id) }

        let current = model.displayedWithResize.widgets.first { $0.id == widget.id } ?? widget
        let cell = grid.cellIndex(at: point)

        var left = current.col
        var top = current.row
        var right = current.col + current.size.cols - 1
        var bottom = current.row + current.size.rows - 1

        if anchor.movesLeading { left = min(cell.col, right) }
        if anchor.movesTrailing { right = max(cell.col, left) }
        if anchor.movesTop { top = min(cell.row, bottom) }
        if anchor.movesBottom { bottom = max(cell.row, top) }

        model.resizeMoved(
            to: (col: left, row: top, cols: right - left + 1, rows: bottom - top + 1))
    }

    private func dragGesture(
        for widget: NotchWidget, grid: GridGeometry, frame: CGRect
    ) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("notch-grid"))
            .onChanged { value in
                if model.draggingID != widget.id {
                    model.beginDrag(widget.id)
                    dragOrigin = frame.origin
                    lastCell = GridCell(col: widget.col, row: widget.row)
                }

                dragTranslation = value.translation

                // The target cell comes from the tile's projected top-left,
                // not from the cursor. Using the cursor means grabbing a tile
                // by its right edge teleports it a cell to the left on the
                // first pixel of movement.
                let projected = CGPoint(
                    x: dragOrigin.x + value.translation.width,
                    y: dragOrigin.y + value.translation.height)
                let target = grid.gridPoint(at: projected)
                let cell = GridCell(col: target.col, row: target.row)

                guard cell != lastCell else { return }
                lastCell = cell
                model.dragMoved(to: target)
            }
            .onEnded { _ in
                model.endDrag(commit: true)
                // Cleared inside the same animation that settles the tile into
                // its cell, so it glides home rather than teleporting.
                withAnimation(.snappy(duration: 0.22)) {
                    dragTranslation = .zero
                    dragOrigin = .zero
                }
                lastCell = nil
            }
    }

}


/// What the notch says before anything is in it.
private struct EmptyNotch: View {
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(NotchTheme.tertiaryText)
            Text("No widgets yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.secondaryText)
            Text("Add one from Settings → Widgets")
                .font(.system(size: 10.5))
                .foregroundStyle(NotchTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Which edge or corner a resize handle drags.
enum ResizeAnchor: CaseIterable, Hashable {
    case topLeading, top, topTrailing
    case leading, trailing
    case bottomLeading, bottom, bottomTrailing

    var movesLeading: Bool { self == .topLeading || self == .leading || self == .bottomLeading }
    var movesTrailing: Bool { self == .topTrailing || self == .trailing || self == .bottomTrailing }
    var movesTop: Bool { self == .topLeading || self == .top || self == .topTrailing }
    var movesBottom: Bool { self == .bottomLeading || self == .bottom || self == .bottomTrailing }

    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .trailing: .trailing
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        }
    }

    var cursor: NSCursor {
        switch self {
        case .leading, .trailing: .resizeLeftRight
        case .top, .bottom: .resizeUpDown
        default: .crosshair
        }
    }
}

/// The eight grab points on a selected tile.
struct ResizeHandles: View {
    let onChanged: (ResizeAnchor, CGPoint) -> Void
    let onEnded: () -> Void

    private let size: CGFloat = 9

    var body: some View {
        ForEach(ResizeAnchor.allCases, id: \.self) { anchor in
            Circle()
                .fill(Color.white)
                .overlay(Circle().strokeBorder(NotchTheme.editHighlight, lineWidth: 1.5))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.35), radius: 2)
                // Half outside the tile, so the handle straddles the edge it
                // controls rather than covering the content inside it.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: anchor.alignment)
                .padding(-size / 2)
                .contentShape(Rectangle().inset(by: -4))
                .onHover { inside in
                    if inside { anchor.cursor.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("notch-grid"))
                        .onChanged { onChanged(anchor, $0.location) }
                        .onEnded { _ in onEnded() }
                )
        }
    }
}
