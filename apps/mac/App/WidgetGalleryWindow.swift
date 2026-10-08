import AppKit
import SwiftUI

/// Wraps SwiftUI content in a window-wide `NSVisualEffectView`.
///
/// The material has to be the window's *content view*, not a layer inside the
/// SwiftUI tree. Inside the tree it is subject to the title bar's safe area,
/// so with a transparent title bar that strip stayed unfrosted — a black band
/// with a seam under it, sitting above a frosted body. As the content view it
/// fills the whole window, title bar included.
///
/// `.ultraThinMaterial` is no use here either way: it blurs what is behind it
/// *in the window*, which over a clear background is nothing. Only
/// `.behindWindow` samples the desktop, and that is the entire look.
@MainActor
func glassContentView(
    material: NSVisualEffectView.Material = .hudWindow,
    @ViewBuilder _ root: () -> some View
) -> NSView {
    let effect = NSVisualEffectView()
    effect.material = material
    effect.blendingMode = .behindWindow
    // `.active`, not `.followsWindowActiveState`: the gallery is dragged
    // *from*, so it spends the whole interaction inactive — and a panel that
    // goes flat grey the moment you start using it looks broken.
    effect.state = .active

    let hosting = NSHostingView(rootView: root())
    hosting.translatesAutoresizingMaskIntoConstraints = false
    effect.addSubview(hosting)
    NSLayoutConstraint.activate([
        hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
        hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        hosting.topAnchor.constraint(equalTo: effect.topAnchor),
        hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
    ])
    return effect
}

/// Owns the gallery window.
///
/// Plain AppKit rather than a SwiftUI `Window` scene: this app is an accessory
/// with no scene phase to hang one off, and the window needs a transparent
/// title bar and a visual effect view under the whole content — neither of
/// which a `Window` scene exposes.
@MainActor
final class WidgetGalleryWindowController: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private let env: AppEnvironment
    private var isDragging = false
    private var dragEndMonitor: Any?
    private var dragTimeout: Task<Void, Never>?

    init(env: AppEnvironment) {
        self.env = env
    }

    var isOpen: Bool { window?.isVisible ?? false }

    func show() {
        if let window {
            window.setFrame(Self.frame(), display: true)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            env.notch.close()
            return
        }

        let window = GalleryPanel(
            contentRect: Self.frame(),
            // Borderless: the system's widget gallery has no title bar and no
            // traffic lights, and neither does this. Done, in the footer, is
            // the way out.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isMovable = false
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = .modalPanel

        let content = glassContentView {
            WidgetGalleryView(
                onDragStart: { [weak self] in self?.beginDrag() },
                onDone: { [weak self] in self?.close() })
                .environment(env)
                .ignoresSafeArea()
        }
        // Top corners only. The panel sits flush with the bottom of the
        // screen, so rounding the bottom pair would cut two notches out of the
        // screen edge — the system's gallery rounds only what you can see.
        content.wantsLayer = true
        content.layer?.cornerRadius = 14
        content.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        content.layer?.masksToBounds = true
        window.contentView = content

        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // Out of the way, not held open. The gallery is the thing being
        // looked at now, and a notch pinned open above it — in edit mode,
        // dotted well and all — was two panels competing for one screen.
        // `beginDrag` brings it back the moment there is a tile to drop.
        env.notch.close()
    }

    func close() {
        window?.close()
    }

    /// Flush with the bottom of the screen, like the system widget gallery.
    private static func frame() -> CGRect {
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = NSScreen.main?.visibleFrame ?? screen
        let width = min(max(visible.width * 0.82, 820), 1600)
        let height = min(max(visible.height * 0.72, 480), 900)
        return CGRect(
            x: visible.midX - width / 2,
            // The screen's own bottom, not the visible frame's: the panel runs
            // under the Dock the way the system gallery does, rather than
            // floating above it with a strip of desktop showing through.
            y: screen.minY,
            width: width,
            height: height)
    }

    // MARK: - Getting out of the way

    /// Hides the bar for the duration of a drag.
    ///
    /// The bar covers the bottom of the screen and the notch is at the top, so
    /// it is not strictly in the way — but a palette that stays put while the
    /// thing it produced is being carried somewhere else reads as two
    /// unrelated windows. Hiding it also makes the notch unmistakably the
    /// target.
    private func beginDrag() {
        guard !isDragging else { return }
        // SwiftUI calls an `onDrag` closure to *prepare* an item provider, not
        // only when a drag actually begins. Without this the bar could hide
        // itself with no drag in flight and nothing to bring it back until
        // the timeout. A real drag always has the button down.
        guard NSEvent.pressedMouseButtons & 0x1 != 0 else { return }
        isDragging = true

        // Edit mode first: the drop destination only draws its well — the one
        // thing on screen that says "this takes tiles" — while editing.
        env.notch.holdOpenForGallery(true)

        window?.animator().alphaValue = 0
        window?.ignoresMouseEvents = true

        // AppKit gives no drag-ended callback to the *source*, so the mouse
        // coming back up is the signal. Global, because the drag is happening
        // over another window by then.
        dragEndMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.endDrag() }
        }
        // Belt and braces: a drag that ends somewhere that swallows the mouse
        // up would otherwise leave the bar invisible and unclickable.
        dragTimeout?.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.endDrag()
        }
        dragTimeout = task
    }

    private func endDrag() {
        guard isDragging else { return }
        isDragging = false

        if let dragEndMonitor { NSEvent.removeMonitor(dragEndMonitor) }
        dragEndMonitor = nil
        dragTimeout?.cancel()
        dragTimeout = nil

        window?.ignoresMouseEvents = false
        window?.animator().alphaValue = 1

        // Back out of the way once the gallery is back. Deferred, because the
        // drop is delivered on the same mouse-up this monitor saw, and
        // collapsing the notch first would take the drop target away before
        // the tile landed on it.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, self.isOpen, !self.isDragging else { return }
            self.env.notch.close()
        }
    }

    func windowWillClose(_ notification: Notification) {
        endDrag()
        // The notch goes back to following the pointer the moment there is
        // nothing left to drag into it.
        env.notch.holdOpenForGallery(false)
        DispatchQueue.main.async {
            let remaining = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
            if remaining.isEmpty { NSApp.setActivationPolicy(.accessory) }
        }
    }
}


/// A borderless panel that can still take key.
///
/// Borderless windows refuse key by default, which would leave the search
/// field unable to accept a single keystroke.
final class GalleryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    /// Never main: this is a palette, and taking main would pull focus out of
    /// whatever the user is actually working in.
    override var canBecomeMain: Bool { false }
}
