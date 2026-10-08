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
    private var window: NSWindow?
    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    var isOpen: Bool { window?.isVisible ?? false }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            env.notch.holdOpenForGallery(true)
            return
        }

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 980, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "Add Widgets"
        // The traffic lights float over the sidebar, as in a Finder window.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // Off, deliberately. The whole content area is draggable *cards*, and
        // background dragging is resolved by AppKit before SwiftUI ever sees
        // the press — so every attempt to drag a widget moved the window
        // instead. The transparent title bar is still a drag handle.
        window.isMovableByWindowBackground = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.minSize = CGSize(width: 820, height: 520)
        window.delegate = self
        window.isReleasedWhenClosed = false

        window.contentView = glassContentView {
            WidgetGalleryView()
                .environment(env)
                .ignoresSafeArea()
        }
        window.center()
        self.window = window

        // Regular, so the window can be cycled to and ordered properly — the
        // same reason Settings does it.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        env.notch.holdOpenForGallery(true)
    }

    func windowWillClose(_ notification: Notification) {
        // The notch goes back to following the pointer the moment there is
        // nothing left to drag into it.
        env.notch.holdOpenForGallery(false)
        DispatchQueue.main.async {
            let remaining = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
            if remaining.isEmpty { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
