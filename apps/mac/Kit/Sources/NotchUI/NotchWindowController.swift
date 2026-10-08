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
    public var onAddWidget: () -> Void = {}

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

    /// Opens the configure pane, remembering what the widget looked like so
    /// Cancel has something to put back.
    public func beginConfiguring(_ id: String) {
        guard let view else { return }
        // The snapshot is best-effort; the pane opens either way. Refusing to
        // open because the widget could not be resolved *here* made this fail
        // silently whenever it was called before the layout had loaded, and a
        // Cancel with nothing to restore is a far smaller problem than a
        // configure button that does nothing.
        view.configuringSnapshot = model.layout.widgets.first { $0.id == id }
        view.configuringID = id
    }
    public var onDropWidget: (String, Int) -> Bool = { _, _ in false }
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
        viewModel.onAddWidget = { [weak self] in self?.onAddWidget() }
        viewModel.configuratorPanel = configuratorPanel
        viewModel.onDropWidget = { [weak self] payload, index in
            self?.onDropWidget(payload, index) ?? false
        }
        viewModel.onRefresh = { [weak self] in self?.onRefresh() }
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

    /// The × in the header. Leaves edit mode and collapses, whether pinned or
    /// not — a close button that does nothing because the panel is pinned is a
    /// close button that looks broken.
    public func close() {
        view?.isPinned = false
        collapse(animated: true)
    }

    /// Holds the notch open and in edit mode while a tile is being dragged
    /// out of the gallery.
    ///
    /// Only for the drag, not for the whole time the gallery is up: the
    /// gallery collapses the notch when it opens and after each drop, so the
    /// two are not both on screen at once.
    ///
    /// A drag from another window takes the pointer nowhere near the notch,
    /// so the exit watch would collapse the drop target the moment the drag
    /// started. Pinning is the same mechanism edit mode already uses.
    public func holdOpenForGallery(_ open: Bool) {
        guard let view else { return }
        if open {
            expand()
            view.isPinned = true
            model.isEditing = true
            hover?.cancelPendingCollapse()
        } else {
            view.isPinned = false
            collapseIfUnpinned()
        }
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
