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
    /// Whole turns of the refresh glyph, one per press.
    @State private var turns = 0.0
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
    private var onConfigureWidget: (NotchWidget) -> Void { view.onConfigureWidget }
    private var onRefresh: () -> Void { view.onRefresh }
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
            topCornerRadius: presentation == .expanded ? 28 : 0,
            bottomCornerRadius: presentation == .expanded ? 26 : notchBottomRadius
        )

        let width = presentation == .expanded ? expandedSize.width : collapsedSize.width
        let height = presentation == .expanded ? expandedSize.height : collapsedSize.height

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
                    // Inside the ears, so the content keeps the body's width
                    // and its padding is unchanged by them.
                    .padding(.horizontal, shape.horizontalOverhang / 2)
                    .transition(NotchMotion.content(reduceMotion: reduceMotion))
            }
        }
        // The ears are drawn inside the shape's rect, so the frame carries
        // them: a path that overflowed its own bounds was silently clipped,
        // which is why the top corners had gone square. `width` is still the
        // body, and the content is inset back onto it above.
        .frame(width: width + shape.horizontalOverhang, height: height)
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

    private var content: some View {
        NotchWidgetCanvas(
            model: model, states: states, appOverrides: appOverrides,
            onConfigureWidget: onConfigureWidget)
            // Wider than the backdrop's inset, so the well has room to sit
            // between the tiles and the panel edge instead of being squeezed
            // flush against one or the other.
            .padding(.horizontal, 20)
            // Clear of the header, with room for the edit backdrop's own
            // inset on top of it — that is what this has to cover, not just
            // the grid.
            .padding(.top, NotchWidgetCanvas.editInset + 6)
            // The well extends below the last row too, and the grabber sits
            // directly under it. Without this the dots ran behind the handle.
            .padding(.bottom, NotchWidgetCanvas.editInset)
            // A tile drag or resize holds the notch open for the same reason
            // the handle does. Edit mode pins already, but a drag begun by
            // long-press turns edit mode on *without* pinning, and that one
            // collapses mid-gesture.
            .onChange(of: model.draggingID) { _, id in
                view.isInteracting = id != nil || model.resizingID != nil
            }
            .onChange(of: model.resizingID) { _, id in
                view.isInteracting = id != nil || model.draggingID != nil
            }
    }

    /// Brand and the everyday controls on the left, edit and close on the
    /// right, the camera housing between.
    ///
    /// The header is exactly as tall as the physical notch and the middle of
    /// it is deliberately empty — that span is occupied by hardware, and
    /// anything placed there is invisible.
    ///
    /// Refresh and settings sit beside the name rather than on the right.
    /// The right half is the crowded one — it carries the edit pill, the
    /// below-fold count and the close button — and on a notched display it
    /// starts immediately after the housing, so the two controls reached for
    /// most often were the ones furthest from the pointer and nearest the
    /// hardware. The left half is otherwise only a logo and a label.
    private var header: some View {
        HStack(spacing: 7) {
            NotchLogo(size: 17)
            Text("Notch Metrics")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.secondaryText)

            refreshButton
            headerButton("gearshape", help: "Settings", action: onOpenSettings)

            Spacer(minLength: 0)
            // The width of the camera housing, kept clear.
            Color.clear.frame(width: geometry.hasNotch ? geometry.notchRect.width : 0)
            Spacer(minLength: 0)

            // No edit-mode hint here. The header's right half sits under the
            // camera housing on a notched display, so the text was half
            // hidden on exactly the machines this app is for — and the
            // selection outline and handles say what to do without words.
            if belowFoldCount > 0 {
                // Below the fold, not lost. Saying so beats silently showing
                // fewer numbers than the user added.
                Text("+\(belowFoldCount) below")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .help("Scroll the grid, or drag the handle at the bottom to make the notch taller.")
                    .transition(.opacity)
            }

            editButton
            headerButton("xmark", help: "Close", action: onClose)
        }
        // Filling the band before it is given a height, so the row's contents
        // centre on the header rather than on their own 24pt selves. Without
        // this the HStack is only as tall as a button and sits at the top of
        // the bar, which reads as the icons being pushed up.
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 16)
        // The panel's top edge sits above the screen's, so the band is
        // centred on a top that cannot be seen and the row reads as pushed
        // up. This nudges it into the middle of the part that can be seen.
        //
        // Padding inside a centred frame moves the content by half of it, so
        // this is twice the correction — measured, not derived, because the
        // overhang comes from how the window is placed over the notch rather
        // than from anything this view knows about.
        .padding(.top, 16)
        .frame(height: max(44, geometry.hasNotch ? geometry.notchRect.height + 12 : 44))
    }

    /// A labelled pill rather than a pencil.
    ///
    /// Edit mode rearranges and resizes every widget in the notch, which is
    /// more than a glyph can promise — and a pencil beside a gear and a cross
    /// reads as one more icon rather than the one control most people came
    /// for.
    private var editButton: some View {
        Button(action: toggleEditing) {
            HStack(spacing: 5) {
                Image(systemName: model.isEditing ? "checkmark" : "square.grid.2x2")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(model.isEditing ? "Done" : "Edit Widgets")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    model.isEditing
                        ? NotchTheme.editHighlight.opacity(0.9)
                        : Color.white.opacity(0.1)))
            .overlay(
                Capsule().strokeBorder(
                    model.isEditing ? Color.clear : Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.isEditing ? Color.white : NotchTheme.secondaryText)
        .help(model.isEditing ? "Finish editing" : "Rearrange and resize widgets")
        .animation(.easeOut(duration: 0.14), value: model.isEditing)
    }

    /// Fetch every tile again, now.
    ///
    /// The poll is five minutes and the server caches a daily figure for
    /// fifteen, so a number that has just moved is otherwise invisible for a
    /// while. The glyph turns once per press — a button that does its work
    /// silently reads as a button that did nothing.
    private var refreshButton: some View {
        headerButton(
            "arrow.clockwise",
            help: view.isRefreshing ? "Refreshing…" : "Refresh now",
            action: {
                // A counter rather than a bool. Toggling 0↔360 unwinds on the
                // way back, so the glyph spun forwards and then visibly
                // backwards; this only ever increases.
                turns += 1
                onRefresh()
            }
        )
        .rotationEffect(.degrees(turns * 360))
        .animation(.easeInOut(duration: 0.7), value: turns)
        .disabled(view.isRefreshing)
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

    /// Widgets that start below the visible rows.
    ///
    /// Not "hidden" any more — the area scrolls, so they are reachable. The
    /// count is still worth showing, because a notch two rows tall gives no
    /// other hint that there is a third row under it.
    private var belowFoldCount: Int {
        let visible = Int(model.visibleRows.rounded())
        return model.displayed.widgets.count { $0.visible && $0.row >= visible }
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
                    // The pointer is about to travel towards the edge of the
                    // panel, and an exit mid-drag would collapse the notch
                    // out from under the gesture.
                    view.isInteracting = true
                }
                // Fractional, and followed exactly. Rounding to a whole row
                // on every frame meant the panel jumped a row at a time
                // under a pointer that was moving smoothly; the detent
                // belongs at the end of the gesture.
                let stride = NotchWidgetCanvas.rowHeight + NotchWidgetCanvas.rowSpacing
                model.dragRows(to: CGFloat(rowsAtDragStart) + value.translation.height / stride)
            }
            .onEnded { _ in
                isResizing = false
                view.isInteracting = false
                model.endRowDrag()
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
        let content = NotchWidgetCanvas.canvasHeight(rows: model.visibleRows)
            + Self.grabberHeight
        return CGSize(
            // Less the ears, which the panel frame adds back — the window is
            // a fixed 900 and a body at the cap would push them outside it,
            // where they are clipped away again.
            width: min(
                NotchPanel.maxSize.width - Self.earOverhang,
                max(560, geometry.notchRect.width + 480)),
            height: min(NotchPanel.maxSize.height, header + content)
        )
    }

    static let grabberHeight: CGFloat = 19

    /// Both ears together, at the expanded top corner radius.
    static let earOverhang: CGFloat = 56

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
    /// Opens the app on a widget's configuration.
    public var onConfigureWidget: (NotchWidget) -> Void = { _ in }

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
    @State private var hoveredID: String?
    /// Where the pointer was when the span last changed, for hysteresis.
    @State private var resizeAnchorCell: CGPoint?

    public init(
        model: NotchLayoutModel,
        states: [String: TileState],
        appOverrides: [String: MetricApp] = [:],
        onConfigureWidget: @escaping (NotchWidget) -> Void = { _ in }
    ) {
        self.model = model
        self.states = states
        self.appOverrides = appOverrides
        self.onConfigureWidget = onConfigureWidget
    }

    public var body: some View {
        GeometryReader { proxy in
            // Laid out over the content, not the viewport: the rows that do
            // not fit are below the fold and scrolled to, which is what makes
            // adding a widget to a full grid work at all.
            let rows = max(Int(model.visibleRows.rounded(.up)), layoutRows)
            let grid = GridGeometry(
                available: proxy.size, rows: rows,
                origin: .zero, rowHeight: Self.rowHeight)
            let layout = model.displayedWithResize

            // The viewport scrolls over the flow. Before this, a grid that
            // was full simply refused the next widget.
            ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                if model.isEditing {
                    // A recessed surface behind the tiles, so edit mode reads
                    // as a different place rather than the same panel with
                    // specks on it. Inset outwards so the dots run past the
                    // tiles rather than stopping flush against the outermost
                    // one.
                    //
                    // The shade only has to separate the well from the panel;
                    // at 0.28 it went to near-black and the tiles read as
                    // floating over a hole. The dots mark the grid, they do
                    // not have to be legible one by one.
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(0.12))
                        .overlay(
                            DottedGrid(pitch: 11, opacity: 0.07)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        // The same inset on all four sides. Trimming the top
                        // to keep it clear of the header made the gap above
                        // the first row visibly tighter than the one beside
                        // it; the clearance belongs in the content's own top
                        // padding, where it does not distort this.
                        .frame(
                            width: grid.contentSize.width + Self.editInset * 2,
                            height: grid.contentSize.height + Self.editInset * 2)
                        .offset(x: -Self.editInset, y: -Self.editInset)
                        .transition(.opacity)
                        // Behind the tiles in the ZStack, so a tap only
                        // reaches it where no tile covers it. Clicking the
                        // empty grid is the obvious way to dismiss a
                        // selection and did nothing at all.
                        .contentShape(Rectangle())
                        .onTapGesture { selectedID = nil }
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
                        isEditing: model.isEditing,
                        isHovered: hoveredID == widget.id
                    )
                    .frame(width: frame.width, height: frame.height)
                    // Inside the animation below, deliberately. Applied after
                    // `.animation` the outline is outside its scope, so it
                    // jumps to the destination frame while the tile is still
                    // gliding there — selection and tile visibly out of step
                    // for the length of every move.
                    // Inset from the corner rather than centred on it, so the
                    // badges do not sit under the top-trailing resize handle
                    // when a widget is both hovered and selected.
                    .overlay(alignment: .topTrailing) {
                        if model.isEditing, hoveredID == widget.id {
                            HStack(spacing: 4) {
                                TileBadge(symbol: "slider.horizontal.3", help: "Configure") {
                                    onConfigureWidget(widget)
                                }
                                TileBadge(symbol: "xmark", help: "Remove this widget") {
                                    if selectedID == widget.id { selectedID = nil }
                                    hoveredID = nil
                                    model.remove(widget.id)
                                }
                            }
                            .padding(6)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                        }
                    }
                    .overlay {
                        if model.isEditing, selectedID == widget.id {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(NotchTheme.editHighlight, lineWidth: 1.5)
                                ResizeHandles(
                                    onChanged: { anchor, point in
                                        resize(widget, anchor: anchor, to: point, grid: grid)
                                    },
                                    onEnded: {
                                        model.endResize(commit: true)
                                        resizeAnchorCell = nil
                                    })
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
                    .animation(.easeOut(duration: 0.12), value: hoveredID)
                    .onTapGesture {
                        guard model.isEditing else { return }
                        // Exactly one selection at a time: tapping a
                        // different tile moves it rather than adding to it,
                        // and tapping the selected one clears it.
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
            .onChange(of: model.isEditing) { _, editing in
                if !editing { selectedID = nil }
            }
            .frame(
                width: grid.contentSize.width, height: grid.contentSize.height,
                alignment: .topLeading)
            .coordinateSpace(name: "notch-grid")
            // Hover is resolved from the pointer against the same rects the
            // tiles are drawn at, not by a per-tile `.onHover`.
            //
            // Per-tile hover asked each tile's *presentation* layer, which is
            // mid-flight during every reflow and sits under a `.scaleEffect`
            // and an animated `.offset`. The result was badges appearing on a
            // neighbour of the tile the pointer was actually over, and exits
            // that never arrived. One point tested against `grid.rect` cannot
            // disagree with itself.
            .onContinuousHover(coordinateSpace: .named("notch-grid")) { phase in
                guard model.isEditing, model.draggingID == nil else {
                    hoveredID = nil
                    return
                }
                switch phase {
                case .active(let point):
                    hoveredID =
                        layout.widgets
                        .first { $0.visible && grid.rect(for: $0).contains(point) }?.id
                case .ended:
                    hoveredID = nil
                }
            }
            }
            // A tile being dragged must not also scroll the view under it —
            // the drag's own vertical movement would be read as a scroll and
            // the tile would chase a grid that is sliding away from it.
            .scrollDisabled(model.draggingID != nil || model.resizingID != nil)
            // No rubber-banding when everything already fits. A two-row grid
            // that bounces reads as broken rather than as scrollable.
            .scrollBounceBehavior(.basedOnSize)
        }
        // The viewport. The content inside is as tall as the flow needs.
        .frame(height: Self.canvasHeight(rows: model.visibleRows))
    }

    /// How many rows of content there are, never fewer than the viewport.
    private var layoutRows: Int {
        max(model.displayedWithResize.contentRows, model.displayed.rows)
    }

    /// How far the edit backdrop extends past the grid, on every side.
    ///
    /// At 8 the well was the same distance from the tiles as the tiles were
    /// from the panel, so the two gaps read as one and the dots looked like
    /// they were touching the outermost tile. The content's own horizontal
    /// padding grew with it, which keeps the well the same distance from the
    /// panel edge rather than pushing it out against the glass.
    static let editInset: CGFloat = 12

    /// One row is tall enough for a label over a headline figure; each extra
    /// row adds the same again plus the gap between them.
    static let rowHeight: CGFloat = 84
    static let rowSpacing: CGFloat = 10

    /// Fractional, because the handle drag follows the pointer between
    /// detents rather than snapping to a row on every frame.
    static func canvasHeight(rows: CGFloat) -> CGFloat {
        rows * rowHeight + max(0, rows - 1) * rowSpacing
    }

    /// Turns a handle drag into a target rectangle in grid cells.
    ///
    /// The opposite edge is the anchor and never moves, which is what makes a
    /// resize aimable: dragging the left handle changes the left edge only,
    /// and the right edge stays exactly where the eye expects it.
    private func resize(
        _ widget: NotchWidget, anchor: ResizeAnchor, to point: CGPoint, grid: GridGeometry
    ) {
        if model.resizingID != widget.id {
            model.beginResize(widget.id)
            resizeAnchorCell = point
        }

        // Hysteresis. Without it the span flips the instant the pointer
        // crosses a cell boundary, so a hand drifting a couple of points
        // sideways while pulling down would retarget the column — which is
        // what made this feel like it was fighting back.
        //
        // Measured from where the span last changed, not from the gesture's
        // start, so a long drag stays responsive.
        guard ResizeGate.shouldReevaluate(
            anchor: anchor, from: resizeAnchorCell ?? point, to: point)
        else { return }

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

        let changed = model.resizeMoved(
            to: (col: left, row: top, cols: right - left + 1, rows: bottom - top + 1))
        if changed { resizeAnchorCell = point }
    }

    private func dragGesture(
        for widget: NotchWidget, grid: GridGeometry, frame: CGRect
    ) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("notch-grid"))
            .onChanged { value in
                // A handle drag must never also move the tile. The handles sit
                // in an overlay above the tile, but SwiftUI will still deliver
                // the drag to both, and the move was winning — which is why a
                // resize looked like the widget scattering its neighbours.
                guard model.resizingID == nil else { return }
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

    /// Sets or clears the cursor for this handle.
    ///
    /// `set()` rather than `push()`/`pop()`: hover enter and exit are not
    /// guaranteed to pair up when a drag ends outside the view, and an
    /// unbalanced push leaves the resize cursor stuck over the whole notch.
    ///
    /// macOS 15 has real diagonal frame cursors; on 14 the nearest honest
    /// thing is the crosshair, because the diagonals are not public API.
    func applyCursor(_ active: Bool) {
        guard active else {
            NSCursor.arrow.set()
            return
        }
        if #available(macOS 15.0, *) {
            switch self {
            case .leading: NSCursor.frameResize(position: .left, directions: .all).set()
            case .trailing: NSCursor.frameResize(position: .right, directions: .all).set()
            case .top: NSCursor.frameResize(position: .top, directions: .all).set()
            case .bottom: NSCursor.frameResize(position: .bottom, directions: .all).set()
            case .topLeading: NSCursor.frameResize(position: .topLeft, directions: .all).set()
            case .topTrailing: NSCursor.frameResize(position: .topRight, directions: .all).set()
            case .bottomLeading:
                NSCursor.frameResize(position: .bottomLeft, directions: .all).set()
            case .bottomTrailing:
                NSCursor.frameResize(position: .bottomRight, directions: .all).set()
            }
        } else {
            switch self {
            case .leading, .trailing: NSCursor.resizeLeftRight.set()
            case .top, .bottom: NSCursor.resizeUpDown.set()
            default: NSCursor.crosshair.set()
            }
        }
    }
}

/// The eight grab points on a selected tile.
///
/// The ordering of modifiers here is the whole thing, and getting it wrong is
/// invisible: `.contentShape`, `.onHover` and `.gesture` must be attached to
/// the dot itself, *before* the frame that positions it. Applied after, each
/// handle's interactive area becomes the entire tile — all eight stacked on
/// top of each other, with the last one in `allCases` quietly winning every
/// hover and every drag. The symptom is the same diagonal cursor on all eight
/// handles and a resize that answers to the wrong edge.
struct ResizeHandles: View {
    let onChanged: (ResizeAnchor, CGPoint) -> Void
    let onEnded: () -> Void

    @State private var hovered: ResizeAnchor?

    private let size: CGFloat = 9
    /// Grown outwards for hit testing only. A 9pt target is too small to grab
    /// reliably; the padding is undone again so it changes nothing visually.
    private let grab: CGFloat = 6

    var body: some View {
        ForEach(ResizeAnchor.allCases, id: \.self) { anchor in
            let isHovered = hovered == anchor
            Circle()
                // Filled with the selection blue under the pointer, so it is
                // obvious which handle a drag will grab before committing to
                // it. White otherwise, to read against any tile colour.
                .fill(isHovered ? NotchTheme.editHighlight : Color.white)
                .overlay(
                    Circle().strokeBorder(
                        isHovered ? Color.white : NotchTheme.editHighlight,
                        lineWidth: 1.5))
                .frame(width: isHovered ? size + 3 : size, height: isHovered ? size + 3 : size)
                .shadow(color: .black.opacity(0.35), radius: 2)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .padding(grab)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        hovered = anchor
                    } else if hovered == anchor {
                        hovered = nil
                    }
                    anchor.applyCursor(inside)
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("notch-grid"))
                        .onChanged { onChanged(anchor, $0.location) }
                        .onEnded { _ in onEnded() }
                )
                .padding(-grab)
                // Positioned last, and half outside the tile, so the handle
                // straddles the edge it controls rather than covering the
                // content inside it.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: anchor.alignment)
                .padding(-size / 2)
        }
    }
}

/// When a handle drag is allowed to change the span.
///
/// Pulled out of the view so it can be tested: the complaint it answers — a
/// drag downwards retargeting the column because the hand wandered two points
/// sideways — is not something a screenshot shows.
enum ResizeGate {
    /// Points the pointer must travel, on an axis the handle controls, before
    /// the span is recomputed.
    static let threshold: CGFloat = 10

    static func shouldReevaluate(
        anchor: ResizeAnchor, from: CGPoint, to: CGPoint, threshold: CGFloat = threshold
    ) -> Bool {
        let dx = abs(to.x - from.x)
        let dy = abs(to.y - from.y)
        let horizontal = anchor.movesLeading || anchor.movesTrailing
        let vertical = anchor.movesTop || anchor.movesBottom

        // An edge handle ignores the axis it does not control outright, so a
        // vertical drag cannot change a column however far sideways it wanders.
        switch (horizontal, vertical) {
        case (true, false): return dx >= threshold
        case (false, true): return dy >= threshold
        default: return dx >= threshold || dy >= threshold
        }
    }
}

/// A small round control on a hovered tile while editing.
///
/// Only on hover: always-visible would put a pair of buttons on every widget
/// the moment edit mode opens, and the grid is small enough that they would
/// be most of what is on screen.
private struct TileBadge: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.black.opacity(0.78))
                .frame(width: 17, height: 17)
                .background(Circle().fill(isHovered ? Color.white : Color.white.opacity(0.88)))
                .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                .scaleEffect(isHovered ? 1.12 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .help(help)
    }
}
