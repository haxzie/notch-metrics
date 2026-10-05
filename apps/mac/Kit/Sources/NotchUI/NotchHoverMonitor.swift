import AppKit
import Foundation

/// Decides when the notch opens and closes.
///
/// Two mechanisms, each covering the other's gap.
///
/// An `NSTrackingArea` is free when nothing is happening, which matters for
/// something that sits in the menu bar all day. But on a borderless,
/// click-through panel it can miss `mouseExited` entirely — if the pointer
/// teleports (a trackpad flick, `CGWarpMouseCursorPosition`, a hot corner), or
/// if another always-on-top window overlaps us, the exit event is simply never
/// delivered and the notch stays open forever.
///
/// A global `.mouseMoved` monitor never misses, but it fires on essentially
/// every frame of every pointer movement system-wide, for an event we care
/// about perhaps a dozen times an hour.
///
/// So: the tracking area is the primary signal, and the global monitor is
/// installed **only while expanded** as exit insurance and torn down on
/// collapse. Idle cost returns to zero the moment the notch closes.
@MainActor
public final class NotchHoverMonitor {
    public enum Event { case shouldExpand, shouldCollapse }

    private let onEvent: (Event) -> Void
    private var trackingArea: NSTrackingArea?
    private weak var view: NSView?

    private var globalMonitor: Any?
    private var pollTimer: Timer?
    private var dwellTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    public var dwell: Duration = .milliseconds(120)
    public var collapseDelay: Duration = .milliseconds(400)
    /// Supplied by the controller: the expanded region in screen coordinates.
    public var expandedScreenRect: () -> CGRect = { .zero }

    public init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
    }

    /// Installs the trigger area. `rect` is the collapsed hot zone in `view`'s
    /// coordinates, usually the notch inflated a little downward and sideways
    /// so a pointer heading for the menu bar still catches it.
    public func attach(to view: NSView, rect: CGRect) {
        detachTrackingArea()
        self.view = view

        let area = NSTrackingArea(
            rect: rect,
            // `.activeAlways`, because the app is an accessory and is almost
            // never the active application — `.activeInKeyWindow` would mean
            // the notch only worked while the app had focus, which it never has.
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: view,
            userInfo: ["notchHover": true]
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    private func detachTrackingArea() {
        if let trackingArea, let view { view.removeTrackingArea(trackingArea) }
        trackingArea = nil
    }

    /// Called from the hosting view's `mouseEntered`.
    public func pointerEntered() {
        collapseTask?.cancel()
        collapseTask = nil

        // The dwell is what stops the notch flashing open every time somebody
        // travels to the menu bar. 120 ms is below the threshold at which the
        // delay is perceptible, and above the time a passing pointer spends
        // over a 200-point strip.
        dwellTask?.cancel()
        dwellTask = Task { [dwell, onEvent] in
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled else { return }
            onEvent(.shouldExpand)
        }
    }

    public func pointerExited() {
        dwellTask?.cancel()
        dwellTask = nil
        scheduleCollapse()
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { [collapseDelay, onEvent] in
            try? await Task.sleep(for: collapseDelay)
            guard !Task.isCancelled else { return }
            onEvent(.shouldCollapse)
        }
    }

    /// Call on expand. Installs the insurance.
    public func beginExpandedWatch() {
        guard globalMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.evaluatePointer() }
        }

        // Belt and braces for the case the monitor itself misses: a pointer
        // that moves while a modal drag is in progress generates no
        // `.mouseMoved` at all, so a slow poll catches the user who has walked
        // away with the notch open.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluatePointer() }
        }
    }

    /// Call on collapse. Idle cost goes back to zero.
    public func endExpandedWatch() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func evaluatePointer() {
        let location = NSEvent.mouseLocation
        if expandedScreenRect().contains(location) {
            collapseTask?.cancel()
            collapseTask = nil
        } else if collapseTask == nil {
            scheduleCollapse()
        }
    }

    public func cancelPendingCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    // No deinit. A nonisolated deinit cannot touch this actor's state, and
    // both resources are owned by endExpandedWatch() — which the controller
    // calls on every collapse, including the one before teardown.
}
