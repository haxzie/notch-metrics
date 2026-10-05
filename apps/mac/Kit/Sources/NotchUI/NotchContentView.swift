import MetricsCore
import SwiftUI

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
    public let presentation: NotchPresentation
    public let geometry: NotchGeometry
    public let states: [String: TileState]
    public var onOpenSettings: () -> Void
    public var onTogglePin: () -> Void
    public var onClose: () -> Void
    public var isPinned: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isResizing = false
    @State private var rowsAtDragStart = NotchLayout.defaultRows

    public init(
        model: NotchLayoutModel, presentation: NotchPresentation, geometry: NotchGeometry,
        states: [String: TileState], isPinned: Bool,
        onOpenSettings: @escaping () -> Void, onTogglePin: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.model = model
        self.presentation = presentation
        self.geometry = geometry
        self.states = states
        self.isPinned = isPinned
        self.onOpenSettings = onOpenSettings
        self.onTogglePin = onTogglePin
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            panel
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchMotion.expansion(reduceMotion: reduceMotion), value: presentation)
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
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            header
            NotchWidgetCanvas(model: model, states: states)
                .padding(.horizontal, 16)
            grabber
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

            if model.isEditing {
                Text("Drag to move · click the corner to resize")
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTheme.tertiaryText)
                    .transition(.opacity)
            }

            headerButton(
                model.isEditing ? "checkmark" : "square.grid.2x2",
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
        let content = NotchWidgetCanvas.canvasHeight(rows: model.displayed.rows)
            + Self.grabberHeight
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: NotchLayoutModel, states: [String: TileState]) {
        self.model = model
        self.states = states
    }

    public var body: some View {
        GeometryReader { proxy in
            let grid = GridGeometry(available: proxy.size, rows: model.displayed.rows)
            let layout = model.displayed

            ZStack(alignment: .topLeading) {
                if model.isEditing {
                    DottedGrid(cellSize: grid.cellSize, spacing: grid.spacing)
                        .frame(width: grid.contentSize.width, height: grid.contentSize.height)
                }

                ForEach(Array(layout.widgets.enumerated()), id: \.element.id) { index, widget in
                    let frame = grid.rect(for: widget)

                    WidgetTile(
                        widget: widget,
                        state: states[widget.id] ?? .loading,
                        accent: NotchTheme.accent(for: index),
                        isEditing: model.isEditing
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .zIndex(model.draggingID == widget.id ? 1 : 0)
                    .opacity(model.draggingID == widget.id ? 0.85 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        if model.isEditing { resizeHandle(for: widget) }
                    }
                    .gesture(dragGesture(for: widget, grid: grid))
                    .onLongPressGesture(minimumDuration: 0.5) { model.isEditing = true }
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

    private func dragGesture(for widget: NotchWidget, grid: GridGeometry) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("notch-grid"))
            .onChanged { value in
                if model.draggingID != widget.id { model.beginDrag(widget.id) }
                model.dragMoved(to: grid.gridPoint(at: value.location))
            }
            .onEnded { _ in model.endDrag(commit: true) }
    }

    private func resizeHandle(for widget: NotchWidget) -> some View {
        Button {
            if let next = model.nextSize(for: widget.id, growing: true) {
                model.resize(widget.id, to: next)
            } else if let smaller = model.nextSize(for: widget.id, growing: false) {
                // Wraps back to the smallest that fits, so the handle always
                // does something — a control that is sometimes inert reads as
                // broken rather than as "no room".
                model.resize(widget.id, to: smaller)
            }
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 7, weight: .bold))
                .padding(3)
                .background(Circle().fill(Color.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(NotchTheme.secondaryText)
        .padding(3)
    }
}
