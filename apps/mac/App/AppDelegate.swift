import AppKit
import OSLog
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
        // Lands on Widgets rather than on the exact widget: the builder makes
        // new widgets and there is no screen yet for editing one that exists.
        env.notch.onConfigureWidget = { [weak self] _ in
            self?.env.settingsPane = .widgets
            self?.openSettings()
        }

        env.notch.onRefresh = { [weak self] in
            guard let self else { return }
            Task { await self.env.refreshNow() }
        }

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
            case "connected":
                // The browser finished a connect flow. Land on Integrations
                // so the newly connected account is visible rather than
                // leaving the user to go looking for it.
                env.settingsPane = .connections
                openSettings()
            case "settings":
                // `notchmetrics://settings/integrations` lands on that pane.
                // The path is matched leniently — an unknown one opens
                // General rather than doing nothing, because a link that
                // silently no-ops is worse than one that lands nearby.
                let wanted = url.pathComponents.first { $0 != "/" }
                if let wanted,
                   let pane = SettingsPane(rawValue: wanted) ?? SettingsPane.aliases[wanted] {
                    env.settingsPane = pane
                }
                openSettings()
            default:
                break
            }
        }
    }

    /// `os.Logger` rather than NSLog: this is readable afterwards with
    /// `log show --predicate 'subsystem == "com.notchmetrics.app"'`, which
    /// matters for a flow whose failures all happen while no window is open.
    private static let log = Logger(subsystem: AppPaths.bundleIdentifier, category: "auth")

    private func handleAuthCallback(_ url: URL) async {
        let coordinator = AuthCoordinator()
        Self.log.info("callback received")
        do {
            let (code, verifier) = try coordinator.complete(callback: url)
            Self.log.info("pending matched, exchanging code")
            let label = Host.current().localizedName ?? "Mac"
            let response: DesktopTokenResponse = try await env.api.post(
                "v1/desktop/token",
                body: ["code": code, "verifier": verifier, "label": label],
                as: DesktopTokenResponse.self)
            Self.log.info("token received, storing")
            try await env.auth.store(token: response.token)
            await env.start()
            Self.log.info("signed in: \(self.env.isSignedIn, privacy: .public)")
            env.signInFinished(error: nil)
        } catch AuthError.noPendingSignIn where env.isSignedIn {
            // The web page's effect runs twice under React strict mode, so a
            // second callback arrives with a code we no longer have a
            // verifier for. The first one already signed us in; saying
            // anything here would report a failure that did not happen.
        } catch {
            // Surfaced in Settings rather than as a modal. An alert thrown up
            // by an accessory app appears over whatever the user was doing,
            // with no window to attach itself to.
            Self.log.error("sign-in failed: \(String(describing: error), privacy: .public)")
            env.signInFinished(error: Self.describe(error))
        }
    }

    /// Plain language, and specific where being specific helps.
    private static func describe(_ error: Error) -> String {
        switch error {
        case SecretStoreError.identityChanged:
            return "macOS would not let the app save your sign-in to the Keychain. "
                + "This happens after the app is re-signed; try signing in once more."
        case SecretStoreError.notPersisted:
            return "The Keychain accepted your sign-in but did not keep it. "
                + "Open Keychain Access, delete any \"Notch Metrics\" item, and try again."
        case let SecretStoreError.unexpected(status):
            return "The Keychain refused to save your sign-in (OSStatus \(status))."
        case AuthError.stateMismatch:
            return "That sign-in link did not match the one this Mac started. Try again."
        case AuthError.expired, AuthError.noPendingSignIn:
            return "That sign-in took too long. Start again from this window."
        default:
            return "Sign-in could not be completed: \(error.localizedDescription)"
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
