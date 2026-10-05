import AppKit
import MetricsCore
import SwiftUI

/// Owns one panel per screen and keeps them in step with the hardware.
@MainActor
@Observable
public final class NotchWindowController {
    public private(set) var presentation: NotchPresentation = .collapsed
    public private(set) var geometry: NotchGeometry?
    /// Clicking pins the notch open. Without it, dragging a widget towards the
    /// edge takes the pointer out of the trigger area and the notch closes
    /// mid-gesture — so rearranging would be impossible.
    public private(set) var isPinned = false

    public var onOpenSettings: () -> Void = {}

    private var panel: NotchPanel?
    private var container: HitTestingContainerView?
    private var hover: NotchHoverMonitor?
    private var screenObserver: (any NSObjectProtocol)?
    private var wakeObserver: (any NSObjectProtocol)?
    private var reconfigureTask: Task<Void, Never>?

    private let model: NotchLayoutModel
    private var states: [String: TileState] = [:]
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
        self.states = states
        refreshContent()
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
        // makes the debounce above safe to run often.
        if next == geometry, panel != nil {
            refreshContent()
            return
        }

        geometry = next
        collapse(animated: false)

        let container = HitTestingContainerView(frame: CGRect(origin: .zero, size: NotchPanel.maxSize))
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: contentView(for: next))
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
        monitor.expandedScreenRect = { [weak self] in self?.expandedScreenRect ?? .zero }
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
                refreshContent()
            }
        }


        updateHitRect()
    }

    private func contentView(for geometry: NotchGeometry) -> some View {
        NotchContentView(
            model: model,
            presentation: presentation,
            geometry: geometry,
            states: states,
            isPinned: isPinned,
            onOpenSettings: { [weak self] in self?.onOpenSettings() },
            onTogglePin: { [weak self] in self?.togglePin() },
            onClose: { [weak self] in self?.close() }
        )
    }

    private func refreshContent() {
        guard let geometry, let container else { return }
        // The root view is replaced wholesale rather than mutated through a
        // retained `NSHostingView<ConcreteType>`. Naming that type means
        // spelling out the opaque result of `contentView(for:)`, which Swift
        // will not let you do — and the tree here is a dozen views that
        // SwiftUI diffs anyway.
        container.subviews.forEach { $0.removeFromSuperview() }
        let hosting = NSHostingView(rootView: contentView(for: geometry))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
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

    private var expandedScreenRect: CGRect {
        guard let panel else { return .zero }
        return panel.frame
    }

    public func expand() {
        guard presentation != .expanded else { return }
        presentation = .expanded
        hover?.beginExpandedWatch()
        updateHitRect()
        refreshContent()
    }

    public func collapseIfUnpinned() {
        guard !isPinned else { return }
        collapse(animated: true)
    }

    public func collapse(animated: Bool) {
        guard presentation != .collapsed else { return }
        presentation = .collapsed
        isPinned = false
        model.isEditing = false
        // Idle cost returns to zero: the global mouse monitor and the poll
        // timer only exist while the notch is open.
        hover?.endExpandedWatch()
        updateHitRect()
        refreshContent()
    }

    /// The × in the header. Leaves edit mode and collapses, whether pinned or
    /// not — a close button that does nothing because the panel is pinned is a
    /// close button that looks broken.
    public func close() {
        isPinned = false
        collapse(animated: true)
    }

    public func togglePin() {
        isPinned.toggle()
        if isPinned { hover?.cancelPendingCollapse() }
        refreshContent()
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
