import AppKit
import NotchUI
import SwiftUI

/// Owns the share editor window.
///
/// Plain AppKit for the same reason the gallery is: this app is an accessory
/// with no scene phase to hang a SwiftUI `Window` off, and the editor wants a
/// transparent title bar over a visual effect view that covers the whole
/// content — which a `Window` scene does not expose.
///
/// A titled window rather than the gallery's borderless panel. The gallery is
/// a palette you drag out of and dismiss; this is a thing you sit in front of
/// and resize, so it gets traffic lights and a real window to drag by.
@MainActor
final class ShareWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    func show(_ request: ShareRequest) {
        // Rebuilt rather than reused. The editor is seeded from the tile that
        // was clicked — its size, its number — and SwiftUI would keep the
        // `@State` of the previous one, so sharing a second metric would open
        // on the first one's frame and background with no way to tell why.
        window?.close()

        // An `NSHostingController`, not a hosting view inside a
        // `NSVisualEffectView` the way the gallery does it. The gallery is
        // frosted so it can sit over the desktop; this window is filled edge
        // to edge by a preview whose whole job is to show one gradient
        // honestly, and a translucent chrome around it makes every dark
        // background in the picker look lighter than it exports.
        let window = NSWindow(
            contentRect: Self.frame(),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.contentView = NSHostingView(
            rootView: ShareEditorView(request: request).environment(env))
        window.title = "Share \(request.widget.baseTitle)"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.delegate = self
        window.isReleasedWhenClosed = false
        // Dark regardless of the system setting, for the same reason.
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = CGSize(width: 760, height: 660)

        self.window = window

        // .regular while a real window is up, so the editor gets a Dock entry
        // and can be brought back once something else covers it. Dropped again
        // in `windowWillClose`.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        // Belt and braces for the accessory case. `activate` can be refused
        // when the app has no foreground standing yet, and a plain window
        // from an LSUIElement process that is refused comes up *behind*
        // everything — present in the window list, invisible on screen.
        window.orderFrontRegardless()

        // The notch is at the top of the screen and the editor is centred
        // under it; leaving the panel pinned open would put a second copy of
        // the same tile directly above the preview of it.
        env.notch.close()
    }

    func close() {
        window?.close()
    }

    private static func frame() -> CGRect {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(max(visible.width * 0.56, 760), 1100)
        let height = min(max(visible.height * 0.82, 660), 1000)
        return CGRect(
            x: visible.midX - width / 2, y: visible.midY - height / 2,
            width: width, height: height)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        DispatchQueue.main.async {
            let remaining = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
            if remaining.isEmpty { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
