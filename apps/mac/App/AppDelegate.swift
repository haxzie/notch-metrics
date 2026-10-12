import AppKit
import OSLog
import MetricsAPI
import MetricsCore
import NotchUI
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let env = AppEnvironment()
    private var statusItem: NSStatusItem?
    private lazy var share = ShareWindowController(env: env)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory, not regular: no Dock icon, no app menu. It flips to
        // .regular only while a window is open — see SettingsWindow.
        NSApp.setActivationPolicy(.accessory)

        env.notch.onOpenSettings = { [weak self] in self?.openSettings() }
        // The notification centre, supplied from here for the same reason the
        // widget browser is: it needs the user's connections.
        env.notch.alertCentrePanel = { AnyView(AlertCentrePane().environment(self.env)) }
        env.notch.onBannerTapped = { [weak self] alert in
            guard let self else { return }
            // A link opens the browser; a banner with none opens the centre on
            // the connection it came from. Either way it is read.
            Task { await self.env.markAlertsRead(ids: [alert.id]) }
            if let link = alert.link {
                NSWorkspace.shared.open(link)
            } else {
                // In-process rather than through `notchmetrics://`: the URL
                // scheme exists for *other* processes, and round-tripping
                // through Launch Services would re-activate us for no reason.
                self.env.notch.beginAlerts(
                    focus: AlertFocus(integrationId: alert.integrationId, alertID: alert.id))
            }
        }
        env.onOpenSettings = { [weak self] in self?.openSettings() }
        // Lands on Widgets rather than on the exact widget: the builder makes
        // new widgets and there is no screen yet for editing one that exists.
        // In the notch, not a window. A second window thrown on screen over
        // whatever the user was working in — with its own focus and
        // activation to manage — for what is a change to the thing already on
        // screen was the wrong shape for this.
        env.notch.configuratorPanel = { [weak self] widget in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(WidgetConfigPanel(widgetId: widget.id).environment(self.env))
        }
        // Browsing is a pane in the notch for the same reason configuring is.
        // Both need the catalogue, which is why both come from here.
        env.notch.browserPanel = { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(WidgetBrowserPane().environment(self.env))
        }
        env.notch.onConfigureWidget = { [weak self] widget in
            self?.env.beginConfiguring(widget.id)
        }

        // The request arrives fully resolved — widget, app, state, connection
        // name — because only the notch has all four. See `ShareRequest`.
        env.notch.onShareWidget = { [weak self] request in
            self?.share.show(request)
        }

        env.notch.onAddWidget = { [weak self] in
            self?.env.notch.beginBrowsing()
        }

        env.notch.onSignIn = { [weak self] in
            self?.env.beginSignIn()
        }

        env.notch.onRefresh = { [weak self] in
            guard let self else { return }
            Task { await self.env.refreshNow() }
        }

        Task { await env.start() }

        installMainMenu()
        updateStatusItem()

        // The browser is otherwise only reachable by hovering the notch,
        // entering edit mode and clicking — none of which a screenshot or a
        // first look at the layout can do. Deferred, because `beginBrowsing`
        // needs the panel, and the panel is built in `env.start()`.
        if ProcessInfo.processInfo.environment["NOTCH_DEBUG_BROWSE"] == "1" {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                env.notch.beginBrowsing()
            }
        }

        // Same deferral, same reason: the notification centre is otherwise
        // reachable only by pressing the bell, which a screenshot cannot do.
        // `1` opens it on All; anything else is treated as an integration id.
        // `NOTCH_DEBUG_PANE` already picks which pane opens; this is what makes
        // the window appear without a click, for screenshots.
        if ProcessInfo.processInfo.environment["NOTCH_DEBUG_SETTINGS"] == "1" {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                openSettings()
            }
        }

        if let value = ProcessInfo.processInfo.environment["NOTCH_DEBUG_ALERTS"] {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                env.notch.beginAlerts(
                    focus: value == "1" ? nil : AlertFocus(integrationId: value))
            }
        }

        // Drives one banner, held rather than retracted so it can be looked at
        // — the retract is what makes this impossible to screenshot otherwise.
        if let value = ProcessInfo.processInfo.environment["NOTCH_DEBUG_BANNER"] {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                // `circle` stops at the dropped dot; anything else opens the
                // card. Held rather than retracted, so both halves can be
                // looked at — the retract is what makes this impossible to
                // screenshot otherwise.
                // Through the sound too, so the demo is what a real arrival
                // looks and sounds like rather than a silent rehearsal of it.
                AlertSoundPlayer.play(env.settings.alertSound)
                env.notch.showBanner(
                    AlertSample.banner, seconds: 600, holdClosed: value == "circle")
            }
        }

        // The share editor is otherwise only reachable by hovering a tile and
        // clicking a badge that appears on hover — which a screenshot cannot
        // do, because taking one moves the pointer.
        if let wanted = ProcessInfo.processInfo.environment["NOTCH_DEBUG_SHARE"], !wanted.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                let widgets = env.layoutModel.layout.widgets
                // `1` picks the first widget; any other value is a metric id,
                // for framing a particular tile.
                let target =
                    wanted == "1" ? widgets.first : widgets.first { $0.metric == wanted }
                if let target { openShare(for: target) }
            }
        }

        // The configure pane is otherwise only reachable by picking a widget
        // in the browser or clicking a tile's sliders, neither of which a
        // screenshot can do.
        if let wanted = ProcessInfo.processInfo.environment["NOTCH_DEBUG_CONFIG"], !wanted.isEmpty {
            Task { @MainActor in
                // Long enough for the layout to have loaded: beginConfiguring
                // resolves the widget up front, so firing before the layout
                // arrives silently does nothing.
                try? await Task.sleep(for: .seconds(3))
                // `1` picks whichever widget has no account — the state a
                // freshly dropped one is in. Any other value is a metric id,
                // for looking at a particular widget's controls.
                let widgets = env.layoutModel.layout.widgets
                let target =
                    wanted == "1"
                    ? widgets.first { $0.integrationId == nil } ?? widgets.first
                    : widgets.first { $0.metric == wanted }
                if let target { env.beginConfiguring(target.id) }
            }
        }
    }

    /// Opens the share editor on a widget, resolving what the notch would
    /// have passed in. Only for `NOTCH_DEBUG_SHARE` — in normal use the
    /// request comes from the canvas, which already holds all of this.
    private func openShare(for widget: NotchWidget) {
        share.show(
            ShareRequest(
                widget: widget,
                app: widget.app(),
                state: env.states[widget.id] ?? .loading))
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
                // A new account exists. Reload everything built from the
                // catalogue, and point any widget that was waiting for its
                // provider's only account at it.
                env.catalogueChanged()
                Task { if await env.adoptConnections() { await env.refresh() } }

                // Back where it started. The same link arrives whether
                // Connect was pressed in the notch or on the Integrations
                // pane, and only the notch leaves a suspended pane behind —
                // so that is the one signal that says which. Opening
                // Settings on a flow begun in the notch threw away the
                // widget the user was half-way through configuring.
                if env.notch.hasSuspendedPane {
                    env.notch.resumeAfterExternalFlow()
                } else {
                    // Land on Integrations so the new account is visible
                    // rather than leaving the user to go looking for it.
                    env.settingsPane = .connections
                    openSettings()
                }
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
        // The notch is pinned above every window, including the one about to
        // be brought forward, so it would sit on top of Settings. Discarded
        // rather than suspended: Settings is somewhere to stay, and a notch
        // springing back over it the moment a connection lands is the
        // behaviour this is here to prevent.
        env.notch.close()
        env.notch.discardSuspendedPane()

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
