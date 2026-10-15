import AppKit
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
    /// A notification, slid out of the notch and retracted a few seconds later.
    ///
    /// Deliberately *not* `.hinting`, whose stated purpose is an always-on
    /// pill: this has the opposite lifecycle — timer-driven in and out — and
    /// the two would have to coexist if that pill is ever built.
    ///
    /// It is also the app's first presentation change that no pointer asked
    /// for, which is why `isShowingSomething` below exists.
    case banner
    case expanded

    /// Whether the expanded body is on screen.
    ///
    /// Split from "should the hover monitor watch for the pointer leaving".
    /// Those were one boolean serving two opposite purposes, and a banner needs
    /// them to disagree: it is visible, so a hover must not re-expand over it,
    /// but nobody is pointing at it, so the exit watch must stay asleep.
    public var isOpen: Bool { self == .expanded }
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
    @State private var isGrabberHovered = false
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
    private var onShareWidget: (ShareRequest) -> Void { view.onShareWidget }
    private var onAddWidget: () -> Void { view.onAddWidget }
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
            presentation == .expanded || presentation == .banner
                ? NotchMotion.expansion(reduceMotion: reduceMotion)
                : NotchMotion.collapse(reduceMotion: reduceMotion),
            value: presentation)
    }

    private var panel: some View {
        // A banner leaves the notch shape alone entirely: the card that falls
        // out draws its own surface, and the panel behind it stays the size and
        // shape of the hardware notch. A shape stretched to the bounding box
        // would be a large dark rectangle sitting under the menu bar.
        let shape = NotchShape(
            topCornerRadius: presentation == .expanded ? 28 : 0,
            bottomCornerRadius: presentation == .expanded ? 26 : notchBottomRadius
        )

        let body: CGSize
        switch presentation {
        case .expanded: body = expandedSize
        case .banner: body = bannerSize
        case .collapsed, .hinting: body = collapsedSize
        }
        let width = body.width
        let height = body.height

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
                // Collapsed, the shape is drawn at exactly the notch's size and
                // fully transparent, so the hardware notch looks untouched. A
                // banner is the one non-expanded state that is meant to be
                // seen.
                // Collapsed, the shape is drawn at exactly the notch's size and
                // fully transparent, so the hardware notch looks untouched.
                // During a banner it stays out of the way for the same reason.
                .opacity(presentation == .expanded ? 1 : (geometry.hasNotch ? 0 : 0.95))
                .frame(
                    width: presentation == .banner ? collapsedSize.width : nil,
                    height: presentation == .banner ? collapsedSize.height : nil
                )
                .frame(maxWidth: .infinity, alignment: .center)

            // Collapsed, with something waiting: a dot on the trailing inside
            // edge of the notch. The only thing that makes the feature
            // discoverable without hovering, and it is a view reading an
            // observable property — no timer, no poll.
            if presentation == .collapsed, view.unreadAlertCount > 0, view.isSignedIn {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Circle()
                        .fill(NotchTheme.editHighlight)
                        .frame(width: 4, height: 4)
                        .padding(.trailing, geometry.hasNotch ? 6 : 4)
                }
                .frame(width: width, height: height)
                .transition(.opacity)
            }

            if presentation == .banner, let alert = view.bannerAlert {
                VStack(spacing: 0) {
                    // The notch's own band, kept clear so the card falls out
                    // from under it rather than over it.
                    Color.clear.frame(height: collapsedSize.height)

                    NotchDropBanner(
                        alert: alert,
                        isOpen: view.bannerIsOpen,
                        onTap: view.onBannerTapped
                    )
                    .padding(.top, NotchBannerMetrics.gap)
                    // Starts tucked exactly behind the notch — far enough up
                    // that its bottom edge sits on the notch's — and springs
                    // down from there.
                    .transition(
                        .offset(y: -(NotchBannerMetrics.gap + NotchBannerMetrics.circle))
                    )

                    Spacer(minLength: 0)
                }
                // Clipped at the top only. The container is wider and taller
                // than the card on purpose, so the shadow still has room below
                // and to the sides while the circle is hidden on the way out.
                .frame(width: bannerSize.width, height: bannerSize.height, alignment: .top)
                .clipped()
            }

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
            // The handle sets how many rows are on screen, which is not a
            // thing any pane has. Keyed on `bodyKind` like everything else:
            // this was a third copy of the same if-ladder, and it drifted —
            // the grabber drew over the notification centre while
            // `expandedSize` left no room for it.
            if bodyKind == .grid {
                // The chip rides the handle's band rather than taking a row of
                // its own: the band is already full width and its capsule is
                // centred, so the trailing end of it is empty space. The band
                // grows to `bottomBandHeight` to hold it, which is the number
                // `expandedSize` reserves — see the note on that constant.
                ZStack {
                    grabber
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        updateChip
                    }
                }
                .frame(height: bottomBandHeight)
            }
        }
        // One value, so the frame change and the body swap cannot animate on
        // different clocks.
        .animation(.snappy(duration: 0.28), value: bodyKind)
    }

    /// "Update to 0.4.0", in the bottom corner, when there is one.
    ///
    /// Proactive on purpose. The Updates pane is three clicks away and nobody
    /// goes looking in it, so a release that fixes the thing somebody is about
    /// to report sits uninstalled for weeks. Coloured rather than grey because
    /// it is the one thing in the notch that is not a number, and it has to
    /// read as an offer rather than as a label.
    @ViewBuilder
    private var updateChip: some View {
        if let version = view.availableUpdate {
            Button(action: view.onOpenUpdate) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Update to \(version)")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(NotchTheme.brand))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("A newer version of Notch Metrics is ready to install")
            // Clear of the bottom corner radius on both axes. Flush against
            // the edge the chip reads as something that has fallen out of the
            // panel rather than as something in it.
            .padding(.trailing, 16)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    /// The widget being configured, resolved against the live layout.
    private var configuring: NotchWidget? {
        guard let id = view.configuringID else { return nil }
        return model.layout.widgets.first { $0.id == id }
    }

    /// Which body the expanded notch is showing.
    ///
    /// One value, because `content` and `expandedSize` used to be two parallel
    /// if-ladders over the same question — and they already disagreed about
    /// what sits below the body. A fifth case in two ladders is how they drift.
    /// Named `BodyKind`, not `Body`: `Body` is `View`'s own associated type, and
    /// shadowing it makes the whole view silently stop conforming — with the
    /// error reported against `body`, nowhere near the cause.
    private enum BodyKind: Equatable {
        case signedOut
        case browser
        case alerts
        case configure(NotchWidget)
        case grid
    }

    private var bodyKind: BodyKind {
        if !view.isSignedIn { return .signedOut }
        if view.isBrowsing { return .browser }
        if view.isShowingAlerts { return .alerts }
        if let widget = configuring { return .configure(widget) }
        return .grid
    }

    /// Full-width bodies: a sidebar and a list do not fit in the width a row of
    /// tiles needs.
    private var bodyWantsFullWidth: Bool {
        bodyKind == .browser || bodyKind == .alerts
    }

    @ViewBuilder
    private var content: some View {
        if !view.isSignedIn {
            // Before anything else, including the panes. A grid of tiles all
            // reading "Sign in" said the same thing eight times and still
            // left the user to work out where to do it.
            SignedOutNotch(isSigningIn: view.isSigningIn, onSignIn: view.onSignIn)
                .padding(.horizontal, NotchWidgetCanvas.contentHorizontal)
                .padding(.top, NotchWidgetCanvas.contentTop)
                .padding(.bottom, Self.configureBottomInset)
                .frame(height: Self.signedOutBodyHeight + NotchWidgetCanvas.contentTop
                    + Self.configureBottomInset)
                .transition(.opacity)
        } else if view.isBrowsing {
            browser
        } else if view.isShowingAlerts {
            alertCentre
        } else if let widget = configuring {
            WidgetConfigurePane(
                widget: widget,
                app: AppCatalog.resolve(widget.appId, overrides: appOverrides),
                state: states[widget.id] ?? .loading,
                connectionName: widget.integrationId.flatMap { view.connectionNames[$0] },
                showsRange: widget.metricKey.map(view.timeWindowedMetrics.contains) ?? false,
                panel: view.configuratorPanel,
                onResize: { size in
                    var next = widget
                    next.size = size
                    model.update(next)
                })
                .padding(.horizontal, NotchWidgetCanvas.contentHorizontal)
                .padding(.top, NotchWidgetCanvas.contentTop)
                // Its own bottom inset. The grid gets that margin from the
                // grabber sitting under it, and configuring has no grabber —
                // so without this the last row of the form ran flush into the
                // bottom edge of the panel.
                .padding(.bottom, Self.configureBottomInset)
                .onPreferenceChange(ConfigurePanelHeightKey.self) { height in
                    MainActor.assumeIsolated { view.configureContentHeight = height }
                }
                // In from the right, out by fading: the pane arrives as a
                // place you moved to, and leaves without dragging the grid
                // sideways behind it.
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity))
        } else {
            grid.transition(.opacity)
        }
    }

    /// The notification centre.
    ///
    /// The list itself comes from the app target — it needs the connections —
    /// and all this owns is the height, the insets and the way in and out,
    /// which is exactly the split the browser and the configure pane use.
    private var alertCentre: some View {
        view.alertCentrePanel()
            .padding(.horizontal, NotchWidgetCanvas.contentHorizontal)
            .padding(.top, NotchWidgetCanvas.contentTop)
            .padding(.bottom, Self.configureBottomInset)
            // The same height as the browser, deliberately: the same
            // two-column frame at the same size reads as the same room.
            .frame(height: Self.alertsBodyHeight)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity))
    }

    /// Every widget that can be added, in the notch rather than in a window.
    ///
    /// The list itself comes from the app target — it needs the catalogue and
    /// the connections. All this owns is the height, the insets and the way in
    /// and out, which is exactly the split the configure pane uses.
    private var browser: some View {
        view.browserPanel()
            .frame(height: Self.browseBodyHeight)
            .padding(.horizontal, NotchWidgetCanvas.contentHorizontal)
            .padding(.top, NotchWidgetCanvas.contentTop)
            // No grabber under this one either, so it owns its bottom margin.
            .padding(.bottom, Self.configureBottomInset)
            // The same arrival as the configure pane: in from the right, out
            // by fading. Add Widget and a tile's sliders both move you
            // *forward* into a pane, and the two should feel alike.
            .transition(
                .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity))
    }

    private var grid: some View {
        NotchWidgetCanvas(
            model: model, states: states, appOverrides: appOverrides,
            connectionNames: view.connectionNames,
            timeWindowedMetrics: view.timeWindowedMetrics,
            widgetLinks: view.widgetLinks,
            refreshingIDs: view.visibleRefreshingIDs,
            onConfigureWidget: onConfigureWidget,
            onShareWidget: onShareWidget,
            onOpenWidget: view.onOpenWidget)
            // The well, not the tiles, is what has to clear the panel edge —
            // so the tiles are inset by the margin the well wants *plus* the
            // distance the well extends past them.
            .padding(.horizontal, NotchWidgetCanvas.contentHorizontal)
            .padding(.top, NotchWidgetCanvas.contentTop)
            // The well extends below the last row too, and the grabber sits
            // directly under it. Without this the dots ran behind the handle.
            .padding(.bottom, NotchWidgetCanvas.contentBottom)
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
    /// The right half is the crowded one — it carries the edit pill and the
    /// close button — and on a notched display it
    /// starts immediately after the housing, so the two controls reached for
    /// most often were the ones furthest from the pointer and nearest the
    /// hardware. The left half is otherwise only a logo and a label.
    private var header: some View {
        HStack(spacing: 7) {
            NotchLogo(size: 17)
            Text("Notch Metrics")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.secondaryText)

            // Both are about numbers there are none of yet. Settings stays:
            // it is the way to the account pane and to quitting.
            if view.isSignedIn {
                refreshButton
                alertsButton
            }
            headerButton("gearshape", help: "Settings", action: onOpenSettings)

            Spacer(minLength: 0)
            // The width of the camera housing, kept clear.
            Color.clear.frame(width: geometry.hasNotch ? geometry.notchRect.width : 0)
            Spacer(minLength: 0)

            // No edit-mode hint here. The header's right half sits under the
            // camera housing on a notched display, so the text was half
            // hidden on exactly the machines this app is for — and the
            // selection outline and handles say what to do without words.
            if !view.isSignedIn {
                // Nothing to edit, add or finish. The panel's own button is
                // the only thing to press.
                EmptyView()
            } else if view.isBrowsing {
                backFromBrowsingButton
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else if view.isShowingAlerts {
                backFromAlertsButton
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else if configuring != nil {
                cancelConfiguringButton
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                // Add rather than Done for a widget that arrived from the
                // browser a moment ago: the pane is the last step of adding
                // it, not a visit to something already in the notch.
                if view.configuringIsNew {
                    addConfiguredButton
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else {
                    doneConfiguringButton
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            } else {
                // Only in edit mode, beside Done. Adding a widget is a thing
                // you do *while* arranging them, and a permanent button here
                // would sit next to Close competing with the one control that
                // is not destructive.
                if model.isEditing {
                    addWidgetButton
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
                editButton
            }
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
        // than from anything this view knows about. It was 16 while the panel
        // sized the band 10pt shorter than it draws; with that fixed the band
        // is taller and the same correction pushed the row visibly low.
        .padding(.top, 8)
        .frame(height: headerHeight)
    }

    /// How tall the header band is.
    ///
    /// One expression, because `expandedSize` needs the same number. When the
    /// panel's idea of the header was 10pt shorter than the header itself,
    /// the VStack was asked for more height than the panel had and SwiftUI
    /// took the difference out of the first flexible thing it found — this
    /// band's top padding — so the controls slid up against the top edge.
    private var headerHeight: CGFloat {
        max(44, geometry.hasNotch ? geometry.notchRect.height + 12 : 44)
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
                if model.isEditing {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .semibold))
                } else {
                    WidgetsMark(size: 11.5)
                }
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

    /// Puts the widget back as it was and leaves.
    ///
    /// Left of Done, which is where the system puts the action that is not the
    /// default. It reverts the *configuration* only — a widget that was
    /// dragged in stays in, because dropping it was a separate act from
    /// setting it up.
    private var cancelConfiguringButton: some View {
        Button {
            if view.configuringIsNew {
                // Picking a widget in the browser puts it on the grid
                // straight away, because the pane previews the real tile.
                // Cancel therefore has to take it back out — leaving it
                // behind would mean "Cancel" added a widget.
                if let id = view.configuringID { model.remove(id) }
                withAnimation(.snappy(duration: 0.26)) {
                    // Back to the list that was open, not to the grid: this
                    // is "not that one", and the next thing wanted is almost
                    // always another widget.
                    //
                    // Cleared by hand rather than through `endConfiguring`,
                    // which tells the controller the pane is finished with —
                    // and the controller answers that by handing the notch
                    // back to hover. The browser is still up and still needs
                    // holding open, so the hold has to stay where it is.
                    view.configuringID = nil
                    view.configuringSnapshot = nil
                    view.configuringIsNew = false
                    view.isBrowsing = true
                }
                return
            }
            if let snapshot = view.configuringSnapshot { model.update(snapshot) }
            withAnimation(.snappy(duration: 0.26)) { endConfiguring() }
        } label: {
            HStack(spacing: 4) {
                // The chevron says where the button goes; "Cancel" says what
                // it does to the changes. Both, because leaving the pane and
                // discarding the edits are one action here.
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("Cancel")
                    .font(.system(size: 11, weight: .medium))
            }
                .padding(.leading, 8)
                .padding(.trailing, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(NotchTheme.secondaryText)
        .help(view.configuringIsNew ? "Do not add this widget" : "Discard these changes")
    }

    private func endConfiguring() {
        view.configuringID = nil
        view.configuringSnapshot = nil
        view.configuringIsNew = false
        view.onEndConfiguring()
    }

    /// Finishes adding a widget the browser just put on the grid.
    ///
    /// It confirms rather than inserts — the tile is already there. The label
    /// is what the user is doing, not what the code is doing.
    private var addConfiguredButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.26)) { endConfiguring() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("Add")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(NotchTheme.editHighlight.opacity(0.9)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
        .help("Add this widget to the notch")
    }

    /// Leaves the browser for the grid.
    ///
    /// Back rather than Done, and quiet rather than prominent: browsing
    /// changes nothing on its own — adding happens on the pane after it — so
    /// a blue confirm button here promised a commit that was not waiting to
    /// be made. The same shape as the configure pane's Cancel, because both
    /// are the way out of a pane and back to where you were.
    private var backFromBrowsingButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.26)) {
                view.isBrowsing = false
                view.onEndBrowsing()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("Back")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(NotchTheme.secondaryText)
        .help("Back to the notch")
    }

    private var doneConfiguringButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.26)) { endConfiguring() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("Done")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(NotchTheme.editHighlight.opacity(0.9)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
        .help("Finish configuring")
    }

    private var addWidgetButton: some View {
        Button(action: onAddWidget) {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                Text("Add Widget")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(NotchTheme.secondaryText)
        .help("Browse widgets and add one")
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

    /// The way into the notification centre, with the unread count on it.
    ///
    /// The badge is a view reading an `@Observable` property, so it costs no
    /// timer and no poll of its own.
    private var alertsButton: some View {
        headerButton(
            "bell",
            help: view.unreadAlertCount > 0
                ? "\(view.unreadAlertCount) unread" : "Notifications",
            active: view.isShowingAlerts,
            action: { view.onOpenAlerts() }
        )
        .overlay(alignment: .topTrailing) {
            if view.unreadAlertCount > 0 {
                // A dot under ten, a count above it: two digits fit, three do
                // not, and "9+" reads as a number nobody can act on.
                Group {
                    if view.unreadAlertCount < 10 {
                        Circle().fill(NotchTheme.editHighlight).frame(width: 7, height: 7)
                    } else {
                        Text(view.unreadAlertCount > 99 ? "99" : "\(view.unreadAlertCount)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .frame(minWidth: 13, minHeight: 11)
                            .background(Capsule().fill(NotchTheme.editHighlight))
                    }
                }
                .overlay(
                    Circle().stroke(.black.opacity(0.45), lineWidth: 1).opacity(
                        view.unreadAlertCount < 10 ? 1 : 0))
                .offset(x: 2, y: -1)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: view.unreadAlertCount)
    }

    /// The way back out, mirroring the browser's.
    private var backFromAlertsButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.26)) {
                view.isShowingAlerts = false
                view.onEndAlerts()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("Back")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(NotchTheme.secondaryText)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(.white.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        let lit = isResizing || isGrabberHovered
        return Capsule()
            .fill(lit ? NotchTheme.editHighlight : Color.white.opacity(0.22))
            .frame(width: lit ? 56 : 44, height: Self.grabberCapsuleHeight)
            // The hit area is the full width and much taller than the capsule:
            // a 44x4 target is below every sane minimum, and the band is the
            // last thing in the panel, so the pointer arrives at it from
            // outside and should find it before it reaches the capsule itself.
            .padding(.vertical, (Self.grabberHeight - Self.grabberCapsuleHeight) / 2)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            // The cursor comes from `pointerStyle`, which SwiftUI resolves on
            // the hosting view's own cursor-update pass. Setting `NSCursor`
            // from the hover callback below is that pass's loser: on the first
            // hover the callback ran and the pass then put the arrow back, so
            // the handle looked inert until the pointer left and came back.
            // The callback stays for the hover highlight, and for macOS 14,
            // where `pointerStyle` does not exist.
            .rowResizeCursor()
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isGrabberHovered = true
                    if #unavailable(macOS 15.0) { NSCursor.resizeUpDown.set() }
                case .ended:
                    isGrabberHovered = false
                    // Mid-drag the pointer routinely leaves the band; the
                    // gesture's end puts the arrow back.
                    if !isResizing, #unavailable(macOS 15.0) { NSCursor.arrow.set() }
                }
            }
            .gesture(resizeGesture)
            .animation(.easeOut(duration: 0.14), value: lit)
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
                // And explicitly unanimated. The band around the handle
                // carries an `.animation`, and an animation covers where its
                // view *is* as well as how it looks — so anything that eases
                // in there mid-drag leaves the handle gliding towards a
                // position the panel's bottom edge has already snapped to.
                // That is the bottom jumping around under the pointer: one
                // edge on a spring, the other on the mouse.
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) {
                    model.dragRows(
                        to: CGFloat(rowsAtDragStart) + value.translation.height / stride)
                }
            }
            .onEnded { _ in
                isResizing = false
                view.isInteracting = false
                // Animated, unlike the drag itself. The release snaps to a
                // whole row, which moves the bottom edge by up to half a row,
                // and unanimated that reads as the panel jumping away from
                // where it was let go.
                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.1) : .spring(response: 0.22, dampingFraction: 0.9)
                ) {
                    model.endRowDrag()
                }
                if !isGrabberHovered { NSCursor.arrow.set() }
            }
    }


    private var collapsedSize: CGSize {
        geometry.hasNotch
            ? CGSize(width: geometry.notchRect.width, height: geometry.notchRect.height)
            // No notch: a small visible pill, because there is nothing on the
            // bezel to aim at and an invisible trigger would be undiscoverable.
            : CGSize(width: 120, height: 6)
    }

    /// The transient banner's footprint.
    ///
    /// Wide enough for a connector mark, two lines of text and a timestamp, and
    /// no wider: it sits over the menu bar, and one that spanned the screen
    /// would cover the clock and the user's own menu extras.
    ///
    /// On a Mac with no hardware notch there is nothing to slide out of, so the
    /// banner is a little taller to stand on its own rather than appearing to
    /// grow from a 6pt pill.
    private var bannerSize: CGSize {
        // The card's bounding box, plus slack so the drop shadow is not clipped
        // away by the same `.clipped()` that hides the circle on its way out.
        CGSize(
            width: max(collapsedSize.width, NotchBannerMetrics.cardWidth) + Self.bannerShadowSlack * 2,
            height: collapsedSize.height + NotchBannerMetrics.gap + NotchBannerMetrics.cardHeight
                + Self.bannerShadowSlack
        )
    }

    /// Room around the card for its shadow, inside the clipped container.
    static let bannerShadowSlack: CGFloat = 36

    /// Sized to its content, not to the window.
    ///
    /// The *panel* is always NotchPanel.maxSize — that is what keeps expansion
    /// free of a window resize. The visible shape inside it has to stop where
    /// the content does, or the notch hangs a strip of empty black down the
    /// screen below the last row of tiles.
    private var expandedSize: CGSize {
        // Every vertical band the VStack actually contains. Leaving the
        // content's own padding out of this is what squeezed the header.
        // Configuring is a fixed height of its own: it has a form in it, and
        // sizing it to whatever row count the grid happened to be left on
        // would cut the form off on a one-row notch.
        //
        // The two cases count different things below the body. The grid's
        // margin comes from the grabber; configuring has no grabber and uses
        // its own inset. Adding `grabberHeight` to both was counting a
        // control that is not on screen, which is space the form could not
        // use and padding the eye could not see.
        let content: CGFloat
        switch bodyKind {
        case .signedOut:
            content =
                NotchWidgetCanvas.contentTop + Self.signedOutBodyHeight
                + Self.configureBottomInset
        case .browser:
            content =
                NotchWidgetCanvas.contentTop + Self.browseBodyHeight + Self.configureBottomInset
        case .alerts:
            content =
                NotchWidgetCanvas.contentTop + Self.alertsBodyHeight + Self.configureBottomInset
        case .configure:
            content =
                NotchWidgetCanvas.contentTop + configureBodyHeight + Self.configureBottomInset
        case .grid:
            content =
                NotchWidgetCanvas.contentTop
                + NotchWidgetCanvas.viewportHeight(rows: model.visibleRows)
                + NotchWidgetCanvas.contentBottom
                + bottomBandHeight
        }
        // Less the ears, which the panel frame adds back — the window is a
        // fixed 900 and a body at the cap would push them outside it, where
        // they are clipped away again.
        let widest = NotchPanel.maxSize.width - Self.earOverhang
        return CGSize(
            // The browser takes all of it. A sidebar, a search field and a
            // grid of cards in the width a row of tiles needs leaves two
            // columns of widgets to choose from.
            width: bodyWantsFullWidth
                ? widest
                : min(widest, max(560, geometry.notchRect.width + 480)),
            // Rounded up to a whole point. A fractional height — which a drag
            // produces on every frame, since it tracks the pointer in rows —
            // puts the bottom corner radius and the 1pt stroke on a half
            // pixel, and the edge shimmers as it moves. Up rather than to
            // nearest so the rounding never takes a point away from the
            // content.
            height: min(NotchPanel.maxSize.height, (headerHeight + content).rounded(.up))
        )
    }

    /// The notification centre's body, deliberately equal to the browser's.
    static let alertsBodyHeight: CGFloat = 440

    /// The band under the grid: the resize handle, and the update chip when
    /// there is one.
    ///
    /// One value, read by `expandedContent` and by `expandedSize`. Those two
    /// disagreeing about the height of this band is exactly how the handle
    /// came to sit on the panel's bottom edge once already — see
    /// `grabberHeight`.
    private var bottomBandHeight: CGFloat {
        view.availableUpdate == nil ? Self.grabberHeight : Self.updateBandHeight
    }

    /// The same band with a chip in it.
    ///
    /// Tall enough that the chip clears the bottom corner radius rather than
    /// sitting on it: at the handle's own 22 the capsule touched the panel's
    /// edge and overhung the curve.
    static let updateBandHeight: CGFloat = 42

    /// The handle's whole band, capsule plus the slack that makes it hittable.
    ///
    /// The band's padding is derived from this rather than written out beside
    /// it. The two were 20 and 19, which left the handle's last point outside
    /// the height `expandedSize` reserved for it — so the capsule sat on the
    /// panel's bottom edge instead of inside it, and the bottom of the pointer
    /// target hung over nothing.
    static let grabberHeight: CGFloat = 22
    static let grabberCapsuleHeight: CGFloat = 4

    /// How tall the configure pane opens: whatever the form measured, clamped.
    ///
    /// Measured rather than fixed, so the whole form fits instead of the last
    /// group sitting below a fold. The floor keeps the pane from collapsing on
    /// the first layout pass, before the form has reported anything; the
    /// ceiling stops a form that grows without limit from filling the screen,
    /// and the column still scrolls if it ever hits that.
    private var configureBodyHeight: CGFloat {
        let measured = view.configureContentHeight
        guard measured > 0 else { return Self.configureFallbackHeight }
        return min(max(measured, Self.configureFallbackHeight), Self.configureMaxHeight)
    }

    /// How tall the sign-in panel is.
    ///
    /// Taller than the message strictly needs. At the height of the text the
    /// panel read as an error bar dropped out of the bezel rather than as the
    /// app's front door, and the button — the only thing to do here — sat
    /// squeezed against the bottom edge.
    static let signedOutBodyHeight: CGFloat = 210

    /// How tall the browser opens.
    ///
    /// Fixed rather than measured, unlike the configure form: the list is as
    /// long as the catalogue and would ask for the whole screen if allowed
    /// to. It scrolls, so the number only has to be enough to see two rows of
    /// cards and a few connectors at once — and it has to leave the panel
    /// under `NotchPanel.maxSize.height`, which is the window the notch is
    /// drawn in.
    static let browseBodyHeight: CGFloat = 440

    /// Used until the form has laid out once.
    static let configureFallbackHeight: CGFloat = 300
    static let configureMaxHeight: CGFloat = 560

    /// Clear space under the configure pane, standing in for the grabber the
    /// grid has.
    ///
    /// The same number as the inset down each side, not one of its own: the
    /// pane has a visible boundary on three edges and the eye reads the gaps
    /// together, so 16 against 18 looked like a mistake rather than a choice.
    static var configureBottomInset: CGFloat { NotchWidgetCanvas.contentHorizontal }

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
    /// What each connection is called, by integration id.
    public var connectionNames: [String: String] = [:]
    /// Metrics that carry their time window in the title. See `NotchViewModel`.
    public var timeWindowedMetrics: Set<String> = []
    /// Where each tile goes when it is clicked. See `WidgetLink`.
    public var widgetLinks = WidgetLink.Catalogue()
    /// Widgets with a fetch in flight right now.
    ///
    /// Separate from `TileState.loading`, which means "has nothing to show
    /// yet". A refresh deliberately keeps the last number on screen rather
    /// than blanking the tile, so without this there is no signal at all that
    /// a figure is being checked — the notch just silently changes its mind a
    /// second later, or does not.
    public var refreshingIDs: Set<String> = []
    /// Opens the app on a widget's configuration.
    public var onConfigureWidget: (NotchWidget) -> Void = { _ in }
    /// Opens the share editor on a widget, with everything it is currently
    /// drawing. See `ShareRequest`.
    public var onShareWidget: (ShareRequest) -> Void = { _ in }
    /// Opens a tile's destination in the browser.
    public var onOpenWidget: (URL) -> Void = { _ in }

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
    /// The local key monitor that watches for Delete while something is
    /// selected. Installed on selection and torn down with it — see
    /// `watchForDelete`.
    @State private var deleteKeyMonitor: Any?
    /// Where the pointer was when the span last changed, for hysteresis.
    @State private var resizeAnchorCell: CGPoint?
    /// How far the flow is scrolled, in points. Read back from the scroll view
    /// rather than remembered, so the fold button still knows where it is
    /// after a trackpad scroll it had nothing to do with.
    @State private var scrollOffset: CGFloat = 0

    public init(
        model: NotchLayoutModel,
        states: [String: TileState],
        appOverrides: [String: MetricApp] = [:],
        connectionNames: [String: String] = [:],
        timeWindowedMetrics: Set<String> = [],
        widgetLinks: WidgetLink.Catalogue = .init(),
        refreshingIDs: Set<String> = [],
        onConfigureWidget: @escaping (NotchWidget) -> Void = { _ in },
        onShareWidget: @escaping (ShareRequest) -> Void = { _ in },
        onOpenWidget: @escaping (URL) -> Void = { _ in }
    ) {
        self.model = model
        self.states = states
        self.appOverrides = appOverrides
        self.connectionNames = connectionNames
        self.timeWindowedMetrics = timeWindowedMetrics
        self.widgetLinks = widgetLinks
        self.refreshingIDs = refreshingIDs
        self.onConfigureWidget = onConfigureWidget
        self.onShareWidget = onShareWidget
        self.onOpenWidget = onOpenWidget
    }

    public var body: some View {
        GeometryReader { proxy in
            // Laid out over the content, not the viewport: the rows that do
            // not fit are below the fold and scrolled to, which is what makes
            // adding a widget to a full grid work at all.
            let rows = max(Int(model.visibleRows.rounded(.up)), layoutRows)
            // Less the well's band on both sides. The grid now lays out
            // *inside* that padding, so handing it the full width would make
            // the padded content wider than the viewport — which is what got
            // the band clipped away in the first place.
            let grid = GridGeometry(
                available: CGSize(
                    width: proxy.size.width - Self.editInset * 2,
                    height: proxy.size.height),
                rows: rows, spacing: Self.rowSpacing,
                origin: .zero, rowHeight: Self.rowHeight)
            let layout = model.displayedWithResize
            // Is any of the flow still below the viewport? A count of widgets
            // would be wrong once the grid has been scrolled: what matters is
            // where the content ends relative to where the window onto it is.
            let hasMoreBelow =
                scrollOffset + proxy.size.height
                < grid.contentSize.height + Self.editInset * 2 - 1

            // The viewport scrolls over the flow. Before this, a grid that
            // was full simply refused the next widget.
            ScrollViewReader { scroller in
            ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {

                // One anchor per row, so the fold button has something to
                // scroll *to*. The grid is absolutely positioned — there is no
                // stack of rows for `scrollTo` to aim at, and `scrollPosition`
                // needs a scroll-target layout this does not have.
                //
                // Laid out, not offset. `.offset` moves what is drawn and not
                // what the scroll view measures, so eight anchors all sat at
                // the top of the flow and `scrollTo` had nowhere to go — the
                // button clicked and nothing moved. This stack is exactly as
                // tall as the grid beside it.
                VStack(spacing: Self.rowSpacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        Color.clear
                            .frame(height: Self.rowHeight)
                            .id(Self.foldAnchor(row))
                    }
                }
                .frame(width: grid.contentSize.width)
                .allowsHitTesting(false)

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
                        isHovered: hoveredID == widget.id,
                        connectionName: widget.integrationId.flatMap { connectionNames[$0] },
                        showsRange: widget.metricKey.map(timeWindowedMetrics.contains) ?? false
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
                        HStack(spacing: 4) {
                            // Shown whether or not the pointer is here: a tile
                            // only says it is busy while it is busy, and
                            // requiring a hover to find that out defeats it.
                            // It sits inboard of the badges so the share icon
                            // does not move when a refresh starts under it.
                            if refreshingIDs.contains(widget.id) {
                                TileSpinner()
                                    .transition(.opacity)
                            }

                            if hoveredID == widget.id {
                                // Grouped so the whole cluster carries one
                                // transition; a bare `if` inside an HStack
                                // cannot take one.
                                Group {
                                    if model.isEditing {
                                        TileBadge(
                                            symbol: "slider.horizontal.3", help: "Configure"
                                        ) {
                                            onConfigureWidget(widget)
                                        }
                                        TileBadge(symbol: "xmark", help: "Remove this widget") {
                                            if selectedID == widget.id { selectedID = nil }
                                            hoveredID = nil
                                            model.remove(widget.id)
                                        }
                                    } else {
                                    // Share is the one affordance that belongs
                                    // outside edit mode: it does not change
                                    // the widget, and asking somebody to enter
                                    // a rearranging mode to take a picture
                                    // would put the dotted well and the resize
                                    // handles between them and the thing they
                                    // wanted to post.
                                        TileBadge(
                                            symbol: "square.and.arrow.up",
                                            help: "Share this metric"
                                        ) {
                                            onShareWidget(shareRequest(for: widget))
                                        }
                                    }
                                }
                                .transition(.scale(scale: 0.7).combined(with: .opacity))
                            }
                        }
                        .padding(6)
                        .animation(.snappy(duration: 0.18), value: refreshingIDs.contains(widget.id))
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
                    // The pointer says so before the click does. Only
                    // outside edit mode, where a click moves the tile rather
                    // than following it anywhere.
                    .linkCursor(
                        !model.isEditing && WidgetLink.resolve(widget, in: widgetLinks) != nil)
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
                    // Declared before the single tap so SwiftUI gives the
                    // double click a chance to claim the press.
                    .onTapGesture(count: 2) {
                        // The other way into edit mode is a half-second
                        // long press, which nobody discovers, or the button
                        // in the header, which is nowhere near the tile you
                        // want to move. A double click lands on the tile
                        // itself and selects it on the way in.
                        model.isEditing = true
                        selectedID = widget.id
                    }
                    .onTapGesture {
                        // Editing, a click selects; otherwise it opens the
                        // number where it lives. A tile is a glance at
                        // something that exists somewhere else, and "where"
                        // was previously a trip through the provider's app by
                        // hand.
                        guard model.isEditing else {
                            if let url = WidgetLink.resolve(widget, in: widgetLinks) {
                                onOpenWidget(url)
                            }
                            return
                        }
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
            .onChange(of: selectedID) { _, id in watchForDelete(id) }
            .onDisappear { watchForDelete(nil) }
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
                // Tracked in both modes now. Edit mode gets Configure and
                // Remove; a plain hover gets Share. The guard is only about a
                // gesture owning the pointer — a tile following the cursor is
                // not hovering the cell it is passing over.
                guard model.draggingID == nil, model.resizingID == nil else {
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
            // The well is the *background* of a padded grid, not an oversized
            // rectangle drawn behind it. Framed larger and offset outwards,
            // its left and right bands sat outside the ScrollView's bounds
            // and were clipped — so the dots stopped dead at the outermost
            // tile and the band only ever appeared above the first row.
            .padding(Self.editInset)
            .background { if model.isEditing { well } }
            }
            // A tile being dragged must not also scroll the view under it —
            // the drag's own vertical movement would be read as a scroll and
            // the tile would chase a grid that is sliding away from it.
            .scrollDisabled(model.draggingID != nil || model.resizingID != nil)
            // No rubber-banding when everything already fits. A two-row grid
            // that bounces reads as broken rather than as scrollable.
            .scrollBounceBehavior(.basedOnSize)
            // A `GeometryReader` in the content reporting its frame through a
            // preference is the usual trick for this and does not work here:
            // preferences are re-sent when the view tree updates, and a scroll
            // does not update it — the offset stayed 0 for the life of the
            // panel and the button never knew it had reached the bottom.
            .trackScrollOffset($scrollOffset)
            // Over the last row rather than under it, and inside the viewport
            // rather than in the handle's band: the band is one hit target for
            // the resize drag, and a button in it would take the mouse-down
            // that drag needs.
            .overlay(alignment: .bottom) {
                if hasMoreBelow, model.draggingID == nil, model.resizingID == nil {
                    FoldButton {
                        scrollDownOneFold(
                            viewport: proxy.size.height, stride: grid.rowStride, rows: rows,
                            content: grid.contentSize.height + Self.editInset * 2,
                            using: scroller)
                    }
                    .padding(.bottom, 2)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            // Keyed on the boolean, not on the offset: on the offset this
            // would animate the scroll view's own layout on every frame of
            // every scroll.
            .animation(.easeOut(duration: 0.16), value: hasMoreBelow)
            }
        }
        // The viewport. The content inside is as tall as the flow needs.
        .frame(height: Self.viewportHeight(rows: model.visibleRows))
    }

    /// Watches for Delete while `id` is selected, and removes that widget.
    ///
    /// A local `NSEvent` monitor rather than `onKeyPress`, which needs the
    /// view to hold focus — and the notch is a non-activating panel with no
    /// focus ring, no text field and nothing a user would think to click to
    /// give it focus. Re-installed on every selection change so the closure
    /// always holds the current id rather than the one captured when the
    /// grid first appeared.
    ///
    /// Torn down the moment nothing is selected, so a Delete pressed in
    /// somebody's editor is not swallowed by a notch they are not looking at.
    private func watchForDelete(_ id: String?) {
        if let deleteKeyMonitor {
            NSEvent.removeMonitor(deleteKeyMonitor)
            self.deleteKeyMonitor = nil
        }
        guard let id else { return }
        deleteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 51 is Delete, 117 is the forward Delete on a full keyboard.
            // Both read as "remove this"; neither has another meaning in a
            // panel with no text in it.
            guard event.keyCode == 51 || event.keyCode == 117 else { return event }
            selectedID = nil
            hoveredID = nil
            model.remove(id)
            // Swallowed: handing it on would let the key reach whatever is
            // behind the notch, which is somebody else's document.
            return nil
        }
    }

    /// Everything the share editor needs about one tile, resolved here.
    ///
    /// The canvas is the only place that holds the widget, the app it resolved
    /// to, the state it is drawing and the connection's name all at once —
    /// passing an id upwards would make the app target re-derive four things
    /// it would then have to keep in step with how the tile actually rendered.
    private func shareRequest(for widget: NotchWidget) -> ShareRequest {
        ShareRequest(
            widget: widget,
            app: widget.app(overrides: appOverrides),
            state: states[widget.id] ?? .loading,
            connectionName: widget.integrationId.flatMap { connectionNames[$0] },
            showsRange: widget.metricKey.map(timeWindowedMetrics.contains) ?? false)
    }

    /// The recessed surface the tiles sit on in edit mode.
    ///
    /// Sized by whatever it backs, so the band around the tiles is exactly
    /// the padding applied to the grid — there is no second number to keep
    /// in step, and nothing to clip.
    ///
    /// The shade only has to separate the well from the panel; at 0.28 it
    /// went to near-black and the tiles read as floating over a hole. The
    /// dots mark the grid, they do not have to be legible one by one.
    private var well: some View {
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
            .transition(.opacity)
            // Behind the tiles, so a tap only reaches it where no tile covers
            // it. Clicking the empty grid is the obvious way to dismiss a
            // selection and did nothing at all.
            .contentShape(Rectangle())
            .onTapGesture { selectedID = nil }
    }

    /// How many rows of content there are, never fewer than the viewport.
    private var layoutRows: Int {
        max(model.displayedWithResize.contentRows, model.displayed.rows)
    }

    /// How far the edit backdrop extends past the grid, on every side.
    ///
    /// The gutter, exactly — not a number of its own. A well whose padding
    /// matches the gaps between the tiles reads as one grid; anything else
    /// reads as tiles sitting in a box, and the difference is visible at a
    /// glance even when neither value is wrong on its own.
    static var editInset: CGFloat { rowSpacing }

    /// How far the edit well itself sits from the panel's edges.
    ///
    /// Small, because the two gaps add up. Spending the budget out here
    /// rather than inside pushed the tiles a long way off the glass and left
    /// the dotted band looking like a hairline.
    static let wellMargin: CGFloat = 8

    /// The canvas carries the well's band inside itself now, so the content's
    /// own padding is only the gap between the well and the panel.
    static var contentHorizontal: CGFloat { wellMargin }
    static var contentTop: CGFloat { wellMargin }
    /// The grabber supplies the bottom margin on its own.
    static var contentBottom: CGFloat { 0 }

    /// One row is tall enough for a label over a headline figure; each extra
    /// row adds the same again plus the gap between them.
    static let rowHeight: CGFloat = 84
    /// The gap between two tiles, in both axes — and, through `editInset`,
    /// the gap between a tile and the edge of the well.
    static let rowSpacing: CGFloat = 10

    /// Fractional, because the handle drag follows the pointer between
    /// detents rather than snapping to a row on every frame.
    static func canvasHeight(rows: CGFloat) -> CGFloat {
        rows * rowHeight + max(0, rows - 1) * rowSpacing
    }

    /// The grid plus the well's band above and below it — what the viewport
    /// has to be for `rows` rows to be fully visible inside the well.
    /// The id of the invisible marker at the top of `row`.
    static func foldAnchor(_ row: Int) -> String { "fold-anchor-\(row)" }

    /// Brings the next screenful of the flow into view.
    ///
    /// A row boundary rather than exactly one viewport: the grid is a grid, and
    /// landing mid-tile would leave a band of a widget's bottom edge at the top
    /// of the viewport, which reads as the scroll having missed.
    private func scrollDownOneFold(
        viewport: CGFloat, stride: CGFloat, rows: Int, content: CGFloat,
        using scroller: ScrollViewProxy
    ) {
        guard stride > 0 else { return }
        let target = min(max(0, Int(((scrollOffset + viewport) / stride).rounded(.down))), rows - 1)
        withAnimation(.snappy(duration: 0.3)) {
            scroller.scrollTo(Self.foldAnchor(target), anchor: .top)
        }
        // Moved here too, rather than waiting to be told. On macOS 15 the
        // observer above corrects this a moment later — including for a
        // trackpad scroll this button knows nothing about — but on 14 there is
        // no observer, and a button that cannot tell it has reached the bottom
        // would sit there for ever with nowhere left to go. Clamped like the
        // scroll view clamps, for the same reason.
        scrollOffset = min(CGFloat(target) * stride, max(0, content - viewport))
    }

    static func viewportHeight(rows: CGFloat) -> CGFloat {
        // Whole points, for the same reason the panel's height is: `rows` is
        // fractional during a drag, and a viewport on a half point drags the
        // grabber below it onto one too. Everything that moves while the handle
        // is held lands on a point boundary or the whole bottom edge crawls.
        (canvasHeight(rows: rows) + editInset * 2).rounded(.up)
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


/// What the notch says when nobody is signed in.
///
/// The grid is replaced rather than filled with tiles that each say "Sign
/// in": the number of widgets somebody happens to have is not how many times
/// they should be asked, and a tile is not a place anyone looks for a button.
private struct SignedOutNotch: View {
    let isSigningIn: Bool
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            NotchLogo(size: 26)
            Text("Sign in to see your numbers")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NotchTheme.primaryText)
                .padding(.top, 10)
            Text("Your revenue, traffic and support figures, in the notch.")
                .font(.system(size: 11.5))
                .foregroundStyle(NotchTheme.secondaryText)
                .padding(.top, 3)
            signInButton
                .padding(.top, 14)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }

    /// Deliberately the largest thing in the panel. It is the only action
    /// available, and everything else here is explaining it.
    private var signInButton: some View {
        Button(action: onSignIn) {
            HStack(spacing: 7) {
                if isSigningIn {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Waiting for the browser…")
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text("Sign in")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(Capsule().fill(NotchTheme.editHighlight))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSigningIn)
        // The handshake happens in a browser, which is a window away — so the
        // button says where it is going before it goes.
        .help("Opens your browser to sign in")
        .animation(.easeOut(duration: 0.15), value: isSigningIn)
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
            Text("Press Edit Widgets, then Add Widget")
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

/// The chevron that takes you to the next screenful of widgets.
///
/// It replaced a "+3 below" label in the handle's band. The label said the
/// right thing and did nothing about it — and it sat in the one strip of the
/// panel that belongs to the resize drag, so it could not have been clickable
/// there without taking the mouse-down that drag needs. This floats over the
/// last row instead, centred, and only while there is something below.
private struct FoldButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(isHovered ? 1 : 0.85))
                .frame(width: 24, height: 24)
                // The notch's own recipe, the same as `TileBadge`: frosted
                // glass under a dark tint. A flat disc the colour of the panel
                // disappears over a dark tile and glares over a bright one.
                .background(
                    Circle()
                        .fill(NotchTheme.surfaceMaterial)
                        .overlay(Circle().fill(Color.black.opacity(isHovered ? 0.3 : 0.45)))
                )
                .compositingGroup()
                .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                .scaleEffect(isHovered ? 1.1 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .help("Show the widgets below")
        .accessibilityLabel("Show the widgets below")
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
                // Bigger than the 8pt it was. A glyph this small inside a
                // circle this small reads as a dot with something in it,
                // and the share arrow in particular was unrecognisable.
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(isHovered ? 1 : 0.92))
                .frame(width: 25, height: 25)
                // The notch's own recipe: frosted glass with a dark tint over
                // it. The material alone goes milky over a bright tile and
                // the glyph stops reading; the tint is what keeps the white
                // legible. A white disc was the only light thing on a panel
                // made of smoked glass, which is why it sat on the tile
                // rather than belonging to it.
                .background(
                    Circle()
                        .fill(NotchTheme.surfaceMaterial)
                        .overlay(
                            Circle().fill(Color.black.opacity(isHovered ? 0.34 : 0.48)))
                )
                // No stroke. A hairline on a dark disc over a dark tile drew
                // a ring that read as the edge of something else sitting on
                // the tile; the shadow alone is enough to lift it.
                .compositingGroup()
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
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
