import AppKit
import Foundation

/// Decides when the notch opens and closes.
///
/// The two decisions are asymmetric and that is the whole design:
///
/// **Opening** is governed by the notch itself — a small strip at the top of
/// the screen. A tracking area wakes us up, but the decision is made by
/// testing the pointer against that strip in *screen* coordinates. The
/// tracking area alone is not trustworthy enough to be the authority: it fires
/// for reasons that have nothing to do with where the pointer actually is, and
/// an unreliable open means the notch appears when nobody asked for it.
///
/// **Closing** is governed by the *expanded panel*, not by the strip. Moving
/// from the notch down into the panel necessarily leaves the strip, so an exit
/// from the trigger area means nothing once we are open — treating it as a
/// close makes the notch shut the instant you try to use it.
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

    /// Zero by default: the notch opens the instant the pointer reaches it.
    public var dwell: Duration = .zero
    /// Zero as well, so it closes the moment the pointer leaves the panel.
    public var collapseDelay: Duration = .zero

    /// The strip that opens the notch, in screen coordinates.
    public var triggerScreenRect: () -> CGRect = { .zero }
    /// The *visible* expanded panel, in screen coordinates. Not the window,
    /// which is much larger than what is drawn and would keep the notch open
    /// across half the screen.
    public var expandedScreenRect: () -> CGRect = { .zero }
    /// Whether the notch is currently open, which decides who owns the close.
    public var isExpanded: () -> Bool = { false }

    public init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
    }

    /// Installs the trigger area. `rect` is the hot zone in `view`'s own
    /// coordinates — the notch, inflated a little so a pointer heading for the
    /// menu bar still catches it.
    public func attach(to view: NSView, rect: CGRect) {
        detachTrackingArea()
        self.view = view

        let area = NSTrackingArea(
            rect: rect,
            // `.activeAlways`, because this app is an accessory and is almost
            // never frontmost — `.activeInKeyWindow` would mean the notch only
            // worked while it had focus, which it never has.
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: view,
            userInfo: nil
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
        guard !isExpanded() else { return }

        // The authority is the pointer's actual position, not the fact that a
        // tracking area fired. Without this the notch opens for pointer
        // movement nowhere near it.
        guard triggerScreenRect().contains(NSEvent.mouseLocation) else { return }

        collapseTask?.cancel()
        collapseTask = nil

        dwellTask?.cancel()
        guard dwell > .zero else {
            onEvent(.shouldExpand)
            return
        }
        dwellTask = Task { [dwell, onEvent] in
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled else { return }
            onEvent(.shouldExpand)
        }
    }

    public func pointerExited() {
        // Deliberately does *not* close an open notch. Moving from the strip
        // into the panel leaves the trigger area every time, so acting on this
        // would shut the notch the moment somebody tried to use it. Once open,
        // `evaluatePointer` is the only thing that closes it.
        dwellTask?.cancel()
        dwellTask = nil
    }

    /// Call on expand. Watches for the pointer leaving the panel.
    public func beginExpandedWatch() {
        guard globalMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.evaluatePointer() }
        }

        // Insurance for the case the monitor misses: a pointer that moves
        // during a modal drag generates no `.mouseMoved` at all, so a poll
        // catches somebody who has walked away with the notch open.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluatePointer() }
        }
    }

    /// Call on collapse. Idle cost goes back to zero.
    public func endExpandedWatch() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        globalMonitor = nil
        pollTimer?.invalidate()
        pollTimer = nil
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func evaluatePointer() {
        guard isExpanded() else { return }

        if expandedScreenRect().contains(NSEvent.mouseLocation) {
            collapseTask?.cancel()
            collapseTask = nil
            return
        }

        guard collapseDelay > .zero else {
            onEvent(.shouldCollapse)
            return
        }
        guard collapseTask == nil else { return }
        collapseTask = Task { [collapseDelay, onEvent] in
            try? await Task.sleep(for: collapseDelay)
            guard !Task.isCancelled else { return }
            onEvent(.shouldCollapse)
        }
    }

    public func cancelPendingCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    // No deinit. A nonisolated deinit cannot touch this actor's state, and
    // both resources are owned by endExpandedWatch(), which the controller
    // calls on every collapse.
}
