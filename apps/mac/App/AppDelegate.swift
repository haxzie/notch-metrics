import AppKit
import MetricsAPI
import MetricsCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let env = AppEnvironment()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory, not regular: no Dock icon, no app menu. It flips to
        // .regular only while a window is open — see SettingsWindow.
        NSApp.setActivationPolicy(.accessory)

        env.notch.onOpenSettings = { [weak self] in self?.openSettings() }

        Task { await env.start() }

        installMainMenu()
        updateStatusItem()
    }

    /// Closing the settings window must not quit an app whose whole point is
    /// living in the notch.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        env.notch.stop()
        env.plugins.stop()
        Task { await env.settingsStore.flush() }
    }

    /// Handles `notchmetrics://…`.
    ///
    /// Implemented on the delegate rather than with SwiftUI's `onOpenURL`,
    /// because `onOpenURL` is attached to a scene — and this app normally has
    /// no window open at all, so the callback would simply never fire.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch url.host {
            case "auth":
                Task { await handleAuthCallback(url) }
            case "settings":
                openSettings()
            default:
                break
            }
        }
    }

    private func handleAuthCallback(_ url: URL) async {
        let coordinator = AuthCoordinator()
        do {
            let (code, verifier) = try coordinator.complete(callback: url)
            let label = Host.current().localizedName ?? "Mac"
            let response: DesktopTokenResponse = try await env.api.post(
                "v1/desktop/token",
                body: ["code": code, "verifier": verifier, "label": label],
                as: DesktopTokenResponse.self)
            try await env.auth.store(token: response.token)
            await env.start()
        } catch {
            // Surfaced in Settings rather than as a modal. An alert thrown up
            // by an accessory app appears over whatever the user was doing,
            // with no window to attach itself to.
            NSLog("[auth] sign-in failed: \(error)")
        }
    }

    func openSettings() {
        // A Dock icon appearing while Settings is open is correct, not a bug:
        // without .regular there is no Cmd-Tab entry and no window ordering,
        // and the window cannot be brought back once it is behind something.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue == SettingsWindowID.main }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    /// Flips back to accessory once the last real window closes.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            let remaining = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
            if remaining.isEmpty { NSApp.setActivationPolicy(.accessory) }
        }
    }

    private func updateStatusItem() {
        // Off by default. The product premise is a dashboard that lives in the
        // notch rather than one more menu-bar icon.
        guard env.settings.showMenuBarIcon else {
            statusItem = nil
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "Notch Metrics")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
    }

    @objc private func statusItemClicked() { openSettings() }

    /// An accessory app gets no menu bar of its own, and without an Edit menu
    /// Cmd-V does nothing in the text fields in Settings.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Notch Metrics", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    @objc private func showSettings() { openSettings() }
}

enum SettingsWindowID {
    static let main = "notch-settings"
}
