import AppKit
import MetricsCore
import SwiftUI

/// The window the notch UI lives in.
///
/// Sized **once** to the maximum expanded bounds and never resized: expansion
/// is a content-layout change inside a fixed canvas. Animating
/// `NSWindow.setFrame` at 120 Hz against SwiftUI's own layout pass is where
/// notch apps come apart — the window and the content disagree about their size
/// for a frame at a time, and the result jitters.
public final class NotchPanel: NSPanel {
    /// The window is sized to this once and never resized — expansion is a
    /// content-layout change inside it — so the height only has to be a
    /// ceiling nothing legitimately needs to exceed. 460 was below what the
    /// configure form actually measures, which capped the pane before it
    /// could fit.
    public static let maxSize = CGSize(width: 900, height: 680)

    public override var canBecomeKey: Bool { true }
    /// Never main. Becoming the main window would steal focus from whatever
    /// the user is actually working in every time the pointer brushes the
    /// notch.
    public override var canBecomeMain: Bool { false }

    public init(contentView: NSView) {
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.maxSize),
            // `nonactivatingPanel` is what lets it be clicked without
            // activating the app and pulling focus out of the frontmost window.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
        // SwiftUI owns every transition inside; AppKit's own window fade would
        // double up on it.
        animationBehavior = .none

        // Above the menu bar, below the shielding level. Shielding level sits
        // over alerts, Control Center and screen-sharing overlays, which makes
        // the app feel broken in a way that is hard to attribute.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)

        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            // Renders over a fullscreen app. On a notch Mac that region is
            // black and the menu bar is hidden, so it is free space.
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]

        self.contentView = contentView
    }

    /// Positions the panel so its top edge is flush with the screen top and its
    /// horizontal centre matches the notch.
    public func position(for geometry: NotchGeometry) {
        let frame = CGRect(
            x: geometry.notchRect.midX - Self.maxSize.width / 2,
            y: geometry.screenFrame.maxY - Self.maxSize.height,
            width: Self.maxSize.width,
            height: Self.maxSize.height
        )
        setFrame(frame, display: false)
    }
}

/// Makes everything outside `activeHitRect` click through to whatever is below.
///
/// `ignoresMouseEvents` on the panel cannot do this, because it is all or
/// nothing: with it on, the notch can never be clicked; with it off, a 720×260
/// invisible window swallows the entire menu bar and most of the screen's top
/// edge. Returning nil from `hitTest` is per-point, which is what is needed.
public final class HitTestingContainerView: NSView {
    /// In this view's own coordinate space. Set to the collapsed trigger strip
    /// when collapsed, and to the full bounds when expanded.
    public var activeHitRect: CGRect = .zero

    /// The tracking area's owner has to be this view, because an
    /// `NSTrackingArea` delivers `mouseEntered(with:)` to its owner and
    /// nothing else. Forwarding to closures keeps the controller out of
    /// AppKit's inheritance chain.
    public var onPointerEntered: (() -> Void)?
    public var onPointerExited: (() -> Void)?

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard activeHitRect.contains(point) else { return nil }
        return super.hitTest(point)
    }

    public override func mouseEntered(with event: NSEvent) {
        onPointerEntered?()
    }

    public override func mouseExited(with event: NSEvent) {
        onPointerExited?()
    }

    /// The panel is transparent; AppKit should not treat it as opaque for
    /// hit-testing purposes either.
    public override var isOpaque: Bool { false }

    /// See `FirstMouseHostingView`. Overridden here as well because which view
    /// AppKit asks depends on what `hitTest(_:)` above hands back.
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The hosting view, answering the click that arrives while the panel is not
/// key.
///
/// The notch is never the key window: it is ordered front with
/// `orderFrontRegardless()` and `canBecomeMain` is false, both on purpose, so
/// that brushing it does not pull focus out of whatever is being typed in. The
/// cost is that a click arriving from another app is a *first mouse* event.
/// AppKit asks the hit view whether it wants it, `NSHostingView` says no by
/// default, and that click is spent taking focus instead of doing anything.
/// The tile looks dead; click again, now that the panel has focus, and it
/// works. That second click is the whole tell.
///
/// Answering yes is what a menu bar extra does. Nobody clicks the clock twice.
///
/// Worth knowing if this ever looks unnecessary: a synthetic click at a pinned
/// notch does *not* reproduce the bug, because the panel has usually taken
/// focus by then. It needs the real path — collapsed, hovered open, clicked
/// while another app is in front.
public final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @MainActor @preconcurrency required dynamic init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
