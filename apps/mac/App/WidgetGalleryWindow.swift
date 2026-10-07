import AppKit
import SwiftUI

/// A `NSVisualEffectView` behind SwiftUI content.
///
/// `.ultraThinMaterial` inside SwiftUI blurs what is *behind it in the window*,
/// which over an opaque window background is nothing at all. Only a visual
/// effect view with `.behindWindow` samples the desktop, and sampling the
/// desktop is the entire look.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        // `.active`, not `.followsWindowActiveState`: the gallery is dragged
        // *from*, so it spends the whole interaction inactive — and a panel
        // that goes flat grey the moment you start using it looks broken.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
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

        let root = ZStack {
            VisualEffectBackground()
            WidgetGalleryView()
        }
        .environment(env)
        .ignoresSafeArea()

        window.contentView = NSHostingView(rootView: root)
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
