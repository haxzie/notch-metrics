import AppKit
import MetricsCore
import SwiftUI

/// Owns one panel per screen and keeps them in step with the hardware.
@MainActor
@Observable
public final class NotchWindowController {
    /// Read once rather than through @Environment: the controller is AppKit,
    /// outside any SwiftUI environment.
    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    public private(set) var geometry: NotchGeometry?

    public var onOpenSettings: () -> Void = {}
    public var onConfigureWidget: (NotchWidget) -> Void = { _ in }
    /// Opens the share editor on a tile. See `ShareRequest`.
    public var onShareWidget: (ShareRequest) -> Void = { _ in }
    public var onAddWidget: () -> Void = {}
    /// Starts the browser sign-in handshake. Owned by the app target, which
    /// is where the PKCE challenge and the website's URL live.
    public var onSignIn: () -> Void = {}

    /// Whether there is an account behind the numbers. The notch shows the
    /// sign-in panel in place of the grid when there is not.
    public var isSignedIn: Bool = true {
        didSet { view?.isSignedIn = isSignedIn }
    }

    /// Whether the browser handshake is out. See `NotchViewModel`.
    public var isSigningIn: Bool = false {
        didSet { view?.isSigningIn = isSigningIn }
    }

    /// The controls shown in the notch's configure pane. See
    /// `NotchViewModel.configuratorPanel`.
    public var configuratorPanel: @MainActor (NotchWidget) -> AnyView = { _ in
        AnyView(EmptyView())
    } {
        didSet { view?.configuratorPanel = configuratorPanel }
    }

    /// Which widget the notch is configuring, if any.
    public var configuringID: String? {
        get { view?.configuringID }
        set { view?.configuringID = newValue }
    }

    /// Whether that widget arrived from the browser a moment ago. The form
    /// reads this to leave out controls that make no sense before the widget
    /// has been added — see `NotchViewModel.configuringIsNew`.
    public var configuringIsNew: Bool { view?.configuringIsNew ?? false }

    /// The widget browser shown in the notch. See
    /// `NotchViewModel.browserPanel`.
    public var browserPanel: @MainActor () -> AnyView = { AnyView(EmptyView()) } {
        didSet { view?.browserPanel = browserPanel }
    }

    /// Opens the configure pane, remembering what the widget looked like so
    /// Cancel has something to put back.
    ///
    /// `isNew` is for a widget the browser has just put on the grid: the pane
    /// commits with Add, and Cancel removes it again.
    public func beginConfiguring(_ id: String, isNew: Bool = false) {
        guard let view else { return }
        // The snapshot is best-effort; the pane opens either way. Refusing to
        // open because the widget could not be resolved *here* made this fail
        // silently whenever it was called before the layout had loaded, and a
        // Cancel with nothing to restore is a far smaller problem than a
        // configure button that does nothing.
        view.configuringSnapshot = model.layout.widgets.first { $0.id == id }
        view.configuringID = id
        view.configuringIsNew = isNew
        // The pane replaces the browser, which is where this was picked.
        view.isBrowsing = false
        // The pointer is over the browser's list, which the pane has just
        // replaced — so without the hold the exit watch collapses the form
        // within a tick of it appearing.
        holdOpenForPane()
    }

    public var onRefresh: () -> Void = {}

    /// What the SwiftUI tree reads. Mutating this updates the notch in place;
    /// the hosting view is built once and never replaced except when the
    /// display configuration changes underneath it.
    private var view: NotchViewModel?

    public var presentation: NotchPresentation { view?.presentation ?? .collapsed }
    /// Clicking pins the notch open. Without it, dragging a widget towards the
    /// edge takes the pointer out of the trigger area and the notch closes
    /// mid-gesture — so rearranging would be impossible.
    public var isPinned: Bool { view?.isPinned ?? false }

    private var panel: NotchPanel?
    private var container: HitTestingContainerView?
    private var hover: NotchHoverMonitor?
    private var screenObserver: (any NSObjectProtocol)?
    private var wakeObserver: (any NSObjectProtocol)?
    private var reconfigureTask: Task<Void, Never>?

    private let model: NotchLayoutModel
    private var settings: AppSettings

    /// True while *this* object holds the pin on behalf of a pane — the
    /// browser or the configure form — as opposed to the user having pinned
    /// the notch themselves. Without the distinction, closing a pane would
    /// quietly unpin a notch that edit mode had pinned.
    private var pinnedForPane = false

    public init(model: NotchLayoutModel, settings: AppSettings = AppSettings()) {
        self.model = model
        self.settings = settings
    }

    public func start() {
        rebuild()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }

        // Window level is occasionally lost across display sleep, which leaves
        // the notch rendering *behind* the menu bar — visible as the panel
        // simply not appearing any more until relaunch.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reassertLevel() }
        }
    }

    public func stop() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        hover?.endExpandedWatch()
        panel?.orderOut(nil)
        panel = nil
    }

    public func apply(settings: AppSettings) {
        self.settings = settings
        hover?.dwell = .milliseconds(settings.hoverDwellMilliseconds)
        hover?.collapseDelay = .milliseconds(settings.collapseDelayMilliseconds)
        scheduleRebuild()
    }

    public func update(states: [String: TileState]) {
        // A property change, not a view rebuild. This used to replace the
        // hosting view, which killed any gesture in progress — a metric
        // landing mid-drag would drop the widget being moved.
        view?.states = states
    }

    /// Whether the refresh glyph is turning.
    public var isRefreshing: Bool {
        get { view?.isRefreshing ?? false }
        set { view?.isRefreshing = newValue }
    }

    /// App names and colours from the server's provider manifests.
    public func update(connectionNames: [String: String]) {
        view?.connectionNames = connectionNames
    }

    public func update(appOverrides: [String: MetricApp]) {
        view?.appOverrides = appOverrides
    }

    /// Which metrics carry their time window in the tile's title.
    public func update(timeWindowedMetrics: Set<String>) {
        view?.timeWindowedMetrics = timeWindowedMetrics
    }

    private func scheduleRebuild() {
        // Debounced. Waking a display, attaching a dock, or changing
        // resolution fires didChangeScreenParameters five to ten times in a
        // burst, and rebuilding a window per notification visibly flickers.
        reconfigureTask?.cancel()
        reconfigureTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.rebuild()
        }
    }

    private func rebuild() {
        guard let screen = NotchGeometryResolver.targetScreen(policy: settings.displayPolicy) else {
            return
        }
        let next = NotchGeometryResolver.geometry(for: screen)

        // Equatable, so an unchanged geometry costs nothing. This is what
        // makes the debounce above safe to run often — and why a redundant
        // notification cannot tear down a view mid-gesture.
        if next == geometry, panel != nil { return }

        // `.public`, because os_log redacts interpolated values by default
        // and a screen rectangle logged as `<private>` is the one thing this
        // line exists to show.
        Log.notch.debug(
            """
            geometry screen=\(next.screenNumber, privacy: .public) \
            hasNotch=\(next.hasNotch, privacy: .public) \
            notch=\(next.notchRect.debugDescription, privacy: .public)
            """)
        geometry = next

        // Carried across a display change so the notch does not forget it was
        // open because somebody plugged in a monitor.
        let carried = view
        let viewModel = carried ?? NotchViewModel(geometry: next)
        viewModel.geometry = next
        viewModel.presentation = .collapsed
        viewModel.isPinned = false
        viewModel.onOpenSettings = { [weak self] in self?.onOpenSettings() }
        viewModel.onConfigureWidget = { [weak self] widget in
            self?.onConfigureWidget(widget)
        }
        viewModel.onShareWidget = { [weak self] request in
            self?.onShareWidget(request)
        }
        viewModel.onAddWidget = { [weak self] in self?.onAddWidget() }
        viewModel.onSignIn = { [weak self] in self?.onSignIn() }
        viewModel.isSignedIn = isSignedIn
        viewModel.isSigningIn = isSigningIn
        viewModel.configuratorPanel = configuratorPanel
        viewModel.browserPanel = browserPanel
        viewModel.onRefresh = { [weak self] in self?.onRefresh() }
        viewModel.onEndConfiguring = { [weak self] in self?.paneEnded() }
        viewModel.onEndBrowsing = { [weak self] in self?.paneEnded() }
        viewModel.onTogglePin = { [weak self] in self?.togglePin() }
        viewModel.onClose = { [weak self] in self?.close() }
        self.view = viewModel

        let container = HitTestingContainerView(frame: CGRect(origin: .zero, size: NotchPanel.maxSize))
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: NotchContentView(model: model, view: viewModel))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        self.container = container

        let panel = self.panel ?? NotchPanel(contentView: container)
        panel.contentView = container
        panel.position(for: next)
        panel.orderFrontRegardless()
        self.panel = panel

        let monitor = hover ?? NotchHoverMonitor { [weak self] event in
            MainActor.assumeIsolated {
                switch event {
                case .shouldExpand: self?.expand()
                case .shouldCollapse: self?.collapseIfUnpinned()
                }
            }
        }
        monitor.dwell = .milliseconds(settings.hoverDwellMilliseconds)
        monitor.collapseDelay = .milliseconds(settings.collapseDelayMilliseconds)
        monitor.triggerScreenRect = { [weak self] in self?.triggerScreenRect ?? .zero }
        monitor.expandedScreenRect = { [weak self] in self?.expandedScreenRect ?? .zero }
        monitor.isExpanded = { [weak self] in self?.presentation == .expanded }
        container.onPointerEntered = { [weak monitor] in monitor?.pointerEntered() }
        container.onPointerExited = { [weak monitor] in monitor?.pointerExited() }
        monitor.attach(to: container, rect: triggerRect(for: next))
        hover = monitor

        // A deterministic way to see the expanded state without a pointer.
        // It must *pin*, not merely expand: the exit watch installed by
        // expand() finds the pointer elsewhere and collapses again within half
        // a second, which is correct behaviour and makes an unpinned debug
        // expand useless for screenshots.
        if ProcessInfo.processInfo.environment["NOTCH_DEBUG_EXPAND"] == "1" {
            expand()
            if !isPinned { togglePin() }
            if ProcessInfo.processInfo.environment["NOTCH_DEBUG_EDIT"] == "1" {
                model.isEditing = true
            }
        }


        updateHitRect()
    }



    /// The collapsed hot zone, in the container's coordinates.
    ///
    /// Inflated downward and sideways so a pointer travelling towards the menu
    /// bar still catches it — aiming at a strip exactly the width of the notch
    /// and a few points tall is a precision task nobody should be set.
    private func triggerRect(for geometry: NotchGeometry) -> CGRect {
        let width = geometry.hasNotch ? geometry.notchRect.width : 120
        let height = geometry.hasNotch ? geometry.notchRect.height : 10
        return CGRect(
            x: (NotchPanel.maxSize.width - width) / 2 - 8,
            y: NotchPanel.maxSize.height - height - 4,
            width: width + 16,
            height: height + 6
        )
    }

    private func updateHitRect() {
        guard let container, let geometry else { return }
        // Collapsed, only the trigger strip is clickable and everything else
        // falls through to the menu bar below. Without this a 720x260
        // invisible window eats the top of the screen.
        container.activeHitRect = presentation == .expanded
            ? container.bounds
            : triggerRect(for: geometry)
    }

    /// The strip that opens the notch, in screen coordinates.
    private var triggerScreenRect: CGRect {
        guard let geometry else { return .zero }
        let rect = geometry.hasNotch
            ? geometry.notchRect
            : CGRect(
                x: geometry.screenFrame.midX - 60,
                y: geometry.screenFrame.maxY - geometry.menuBarHeight,
                width: 120, height: geometry.menuBarHeight)

        // Inflated sideways and downward so a pointer travelling toward the
        // menu bar still catches it — aiming at a 185x32 strip exactly is a
        // precision task nobody should be set.
        return rect.insetBy(dx: -8, dy: -3)
    }

    /// The panel as drawn, in screen coordinates — not the window, which is
    /// sized to the maximum and would keep the notch open across a third of
    /// the screen.
    private var expandedScreenRect: CGRect {
        guard let panel, let view, view.visiblePanelSize != .zero else {
            return panel?.frame ?? .zero
        }
        let size = view.visiblePanelSize
        let rect = CGRect(
            x: panel.frame.midX - size.width / 2,
            y: panel.frame.maxY - size.height,
            width: size.width,
            height: size.height)

        // A few points of slack, so a pointer resting exactly on the border
        // does not flicker the notch open and shut.
        return rect.insetBy(dx: -4, dy: -4)
    }

    public func expand() {
        guard let view, view.presentation != .expanded else { return }
        // Animated here rather than inside the view, so the frame change and
        // the content transition are driven by one spring. Without an explicit
        // transaction the change arrives from AppKit outside any animation and
        // the panel simply snaps.
        Log.notch.debug("expand")
        withAnimation(NotchMotion.expansion(reduceMotion: reduceMotion)) {
            view.presentation = .expanded
        }
        hover?.beginExpandedWatch()
        updateHitRect()
    }

    public func collapseIfUnpinned() {
        guard !isPinned, !(view?.isInteracting ?? false) else { return }
        collapse(animated: true)
    }

    public func collapse(animated: Bool) {
        guard let view, view.presentation != .collapsed else { return }
        Log.notch.debug("collapse")
        let apply = {
            view.presentation = .collapsed
            view.isPinned = false
            self.model.isEditing = false
            // A collapsed notch has no pane. The pane used to survive the
            // collapse, so the next hover reopened on a half-finished form
            // for a widget the user had stopped thinking about rather than on
            // the grid — and the only way back was Done. Changes are written
            // straight through to the layout, so dropping it keeps them,
            // exactly as Done does.
            view.configuringID = nil
            view.configuringSnapshot = nil
            view.configuringIsNew = false
            // Same reasoning for the browser: reopening on somebody's
            // half-scrolled widget list rather than on their numbers is not
            // what the next hover was asking for.
            view.isBrowsing = false
            self.pinnedForPane = false
        }
        if animated {
            withAnimation(NotchMotion.collapse(reduceMotion: reduceMotion)) { apply() }
        } else {
            apply()
        }
        // Idle cost returns to zero: the global mouse monitor and the poll
        // timer only exist while the notch is open.
        hover?.endExpandedWatch()
        updateHitRect()
    }

    /// What the notch was showing before something opened a window elsewhere.
    ///
    /// `nil` means nothing was suspended, which is what makes `resume` safe
    /// to call from more than one place: a connect flow finishes through the
    /// poll *and* through the `notchmetrics://connected` deep link, and
    /// whichever arrives second must not reopen a notch the user has since
    /// closed themselves.
    private var suspendedPane: (configuring: String?, isNew: Bool, browsing: Bool)?

    /// Collapse because this action opens a window somewhere else.
    ///
    /// The notch is a hover panel pinned over everything, so leaving it up
    /// in front of the browser tab it just opened is both in the way and
    /// confusing about which window is being asked for input. What it was
    /// showing is remembered so the user comes back to the pane they left,
    /// rather than to a closed notch and the job of finding it again.
    public func suspendForExternalFlow() {
        guard let view else { return }
        suspendedPane = (view.configuringID, view.configuringIsNew, view.isBrowsing)
        close()
    }

    /// Put back whatever `suspendForExternalFlow` took down.
    ///
    /// Only ever reopens a notch this object closed, and only once — a flow
    /// that was started from Settings never suspended anything, so finishing
    /// it must not make a notch appear over the window the user is actually
    /// looking at.
    public func resumeAfterExternalFlow() {
        guard let pane = suspendedPane else { return }
        suspendedPane = nil

        if let id = pane.configuring {
            beginConfiguring(id, isNew: pane.isNew)
        } else if pane.browsing {
            beginBrowsing()
        } else {
            expand()
            holdOpenForPane()
        }
    }

    /// Whether a flow currently running elsewhere was started from the notch.
    ///
    /// The deep link that ends a connect flow cannot otherwise tell: the same
    /// `notchmetrics://connected` arrives whether the user pressed Connect in
    /// the notch or on the Integrations pane, and the right place to put them
    /// back is not the same for both.
    public var hasSuspendedPane: Bool { suspendedPane != nil }

    /// Forgets a suspended pane without reopening it.
    ///
    /// For the case where the flow ends somewhere the notch should not
    /// follow — the user closed the browser tab, or carried on in Settings.
    public func discardSuspendedPane() { suspendedPane = nil }

    /// The × in the header. Leaves edit mode and collapses, whether pinned or
    /// not — a close button that does nothing because the panel is pinned is a
    /// close button that looks broken.
    public func close() {
        view?.isPinned = false
        collapse(animated: true)
    }

    /// Opens the widget browser in the notch.
    ///
    /// Leaves edit mode: the browser replaces the grid, so the handles and the
    /// dotted well behind it would be arranging something nobody can see.
    public func beginBrowsing() {
        guard let view else { return }
        view.configuringID = nil
        view.configuringSnapshot = nil
        view.configuringIsNew = false
        expand()
        model.isEditing = false
        // The pane swap animates from the view, which watches `isBrowsing` —
        // see `expandedContent`.
        view.isBrowsing = true
        holdOpenForPane()
    }

    /// Keeps the notch open while a pane — the browser, the configure form —
    /// is up.
    ///
    /// A pane is read and typed into, not hovered over: the pointer sits
    /// still inside a scroll view or leaves for the keyboard, and either way
    /// the exit watch would collapse the panel out from under it. The pin is
    /// given back in `paneEnded`, and only if it was taken here — edit mode
    /// pins on its own, and stealing credit for that pin would unpin a notch
    /// this object never pinned.
    private func holdOpenForPane() {
        guard let view else { return }
        if !view.isPinned {
            view.isPinned = true
            pinnedForPane = true
        }
        hover?.cancelPendingCollapse()
    }

    /// A pane closed — Done, Add or Cancel. Gives back a pin taken on its
    /// behalf so hover owns the notch again; the exit watch's poll collapses
    /// it a tick later if the pointer has gone elsewhere.
    private func paneEnded() {
        guard pinnedForPane else { return }
        pinnedForPane = false
        view?.isPinned = false
    }

    public func togglePin() {
        guard let view else { return }
        view.isPinned.toggle()
        if view.isPinned { hover?.cancelPendingCollapse() }
    }

    private func reassertLevel() {
        panel?.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel?.orderFrontRegardless()
    }
}

/// Lets the SwiftUI tree report hover without reaching back into AppKit.
public struct NotchHoverDelegate: Sendable {
    public let entered: @MainActor () -> Void
    public let exited: @MainActor () -> Void

    public init(entered: @escaping @MainActor () -> Void, exited: @escaping @MainActor () -> Void) {
        self.entered = entered
        self.exited = exited
    }
}

extension EnvironmentValues {
    @Entry public var notchHoverDelegate: NotchHoverDelegate? = nil
}
