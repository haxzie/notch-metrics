import AppKit
import Foundation
import MetricsAPI
import MetricsCore
import NotchUI
import PluginRuntime
import SwiftUI
import Updater

/// Everything long-lived, assembled once.
@MainActor
@Observable
final class AppEnvironment {
    let settingsStore: SettingsStore
    let layoutModel: NotchLayoutModel
    let notch: NotchWindowController
    let plugins: PluginRegistry
    let connectors: ConnectorRegistry
    /// Per-plugin cadence. Separate from the metric poll because a local
    /// metric is a process against somebody's own API, not a row in a batch.
    private let pluginSchedule = PluginScheduler()
    /// Its own clock. A connector's interval is per app, not per
    /// metric, and sharing the plugin scheduler would let a metric id
    /// and an app id collide on one timestamp.
    private let connectorSchedule = ConnectorScheduler()
    let secrets: any SecretStore
    let auth: AuthStore
    let api: APIClient
    let cache: MetricsCache
    let updates: UpdateController

    private(set) var settings = AppSettings()
    private(set) var states: [String: TileState] = [:]

    // MARK: - Notifications

    let alerts: AlertInbox
    let gate = ActivityGate()
    private(set) var alertFeed: (any AlertFeed)?
    private(set) var alertSnapshot = AlertSnapshot()
    private(set) var alertSettings: AlertSettings?
    private(set) var alertsLoading = false
    private(set) var alertsProblem: String?
    private var alertPump: Task<Void, Never>?
    /// Definitions by provider, from the catalogue. Rendered at runtime, so a
    /// new provider's notifications need no app release.
    private(set) var alertDefinitions: [String: [AlertDefinition]] = [:]
    /// The provider of each connection, so a pane holding an integration id can
    /// find that connection's definitions.
    private var providerByIntegration: [String: String] = [:]

    /// Opens the Settings window. Injected by the delegate, which owns the
    /// window — the same convention as `notch.onOpenSettings`.
    var onOpenSettings: @MainActor () -> Void = {}
    func openSettings() { onOpenSettings() }

    /// Opens Settings on a particular pane.
    ///
    /// Set before the window comes forward, so it does not open on whatever
    /// was last selected and then visibly jump.
    func openSettings(pane: SettingsPane) {
        settingsPane = pane
        onOpenSettings()
    }

    /// Bumped whenever the server's idea of the user's connections may have
    /// changed — a sign-in, a connect flow coming back.
    ///
    /// Every catalogue-backed view loads once in a `.task` and then never
    /// again, so signing in left the Apps pane, the connections list and the
    /// widget browser showing the signed-out answer — no accounts — until
    /// they were closed and reopened. They key their `.task` on this instead.
    private(set) var catalogueRevision = 0

    /// Every connected account's id, by provider.
    ///
    /// A by-product of the labels fetch rather than a request of its own.
    /// Two things need it: pointing a widget at its only account, and
    /// telling "nothing connected" apart from "connected, but this widget
    /// has not been pointed at one".
    private(set) var connectionsByProvider: [String: [String]] = [:]

    /// Whether `connectionsByProvider` has been filled yet.
    ///
    /// A tile with no `integrationId` is either "nothing connected" or
    /// "connected, not yet pointed at an account" — and before the
    /// connections have loaded it is neither, it is unknown. Telling those
    /// apart requires the list; guessing before it arrives is what put
    /// "Connect Stripe" on six tiles belonging to four live accounts for the
    /// first second of every launch.
    private enum ConnectionsKnowledge {
        /// Not asked yet, or the answer has not come back.
        case unknown
        case loaded
        /// Asked and could not reach the server. Distinct from `unknown`
        /// because a tile should eventually say something, and "offline" is
        /// true where "Connect Stripe" is not.
        case unreachable
    }

    private var connectionsKnowledge: ConnectionsKnowledge = .unknown

    /// Something changed server-side; reload anything built from the
    /// catalogue.
    func catalogueChanged() { catalogueRevision += 1 }

    /// Which set of demo tiles to show.
    ///
    /// `1` is the mixed layout every other debug flag is written against, so
    /// it stays the meaning of the bare flag. The rest are one connector
    /// category each, named after `ConnectorCategory` in `packages/schemas`
    /// — `marketing` is the SEO one. They exist for the launch gallery: a
    /// revenue screenshot with a CI tile in the corner of it advertises a
    /// different product on every slide.
    enum DemoPreset: String, CaseIterable {
        case starter
        case revenue, analytics, marketing, developer, ai
    }

    /// Plausible numbers, no account, no network. For screenshots.
    static var demoPreset: DemoPreset? {
        let raw = ProcessInfo.processInfo.environment["NOTCH_DEBUG_DEMO"]
        if raw == "1" { return .starter }
        if let raw, let preset = DemoPreset(rawValue: raw) { return preset }
        // Both panels are drawn over the demo layout, so each implies one
        // without having to name it.
        return (isSkeletonDemo || isUpgradeDemo) ? .starter : nil
    }

    static var isDemo: Bool { demoPreset != nil }

    /// The welcome screen, on a Mac that already has a token.
    ///
    /// Not demo mode: the sign-in button has to be the real one, reaching the
    /// real browser handshake. All this does is withhold the account, which is
    /// otherwise arrangeable only by signing out — and signing out of the
    /// build you are working on takes the Keychain item with it.
    static var isWelcomeDemo: Bool {
        ProcessInfo.processInfo.environment["NOTCH_DEBUG_WELCOME"] == "1"
    }

    /// The lapsed-plan panel, without waiting for a trial to end.
    ///
    /// Implies demo mode for the same reason the skeletons do: the state is
    /// otherwise reachable only by owning an account whose trial has run out,
    /// which is not a thing anybody can arrange while looking at the panel
    /// they are changing.
    static var isUpgradeDemo: Bool {
        ProcessInfo.processInfo.environment["NOTCH_DEBUG_UPGRADE"] == "1"
    }

    /// The demo layout with every tile still loading.
    ///
    /// Implies demo mode, so it needs no account and touches no network. The
    /// skeletons are otherwise on screen for the half second a cold fetch
    /// takes, which is not long enough to tell a chart-shaped placeholder
    /// from a bar-shaped one — and they are the whole point of the state.
    static var isSkeletonDemo: Bool {
        ProcessInfo.processInfo.environment["NOTCH_DEBUG_SKELETON"] == "1"
    }
    /// Signed in, but the plan has lapsed.
    ///
    /// Taken from the server's 402 rather than computed from the trial date
    /// the app happens to hold: `entitlement.ts` is explicit that the moment
    /// both sides decide this independently the two answers diverge, and the
    /// one that matters is whichever the Worker applies.
    private(set) var needsUpgrade = false {
        didSet { notch.needsUpgrade = needsUpgrade }
    }

    /// The short recheck started by the Upgrade button. See `watchForUpgrade`.
    private var upgradeWatch: Task<Void, Never>?

    private(set) var isSignedIn = false {
        // The notch shows the sign-in panel in place of the grid, so it has
        // to hear about this the moment it changes rather than on the next
        // refresh — which, signed out, never comes.
        didSet { notch.isSignedIn = isSignedIn }
    }

    /// Where a sign-in attempt has got to.
    ///
    /// The button used to look identical before the click, during the browser
    /// round trip, and after a failure that only reached NSLog — so "nothing
    /// happened" and "it failed" were the same picture.
    /// The signed-in account, once `/v1/me` has answered.
    ///
    /// Optional for the whole of a cold launch: the token is in the Keychain
    /// but nothing has asked the server who it belongs to yet, and the Account
    /// pane is reachable before the answer arrives — and offline, where it
    /// never does.
    private(set) var account: AccountUser?

    enum SignInState: Equatable {
        case idle
        /// The browser is open and we are waiting for the callback.
        case waiting
        case failed(String)
    }

    private(set) var signIn: SignInState = .idle {
        didSet { notch.isSigningIn = signIn == .waiting }
    }

    func signInStarted() {
        signIn = .waiting
        // The browser may never come back — the tab gets closed, the user
        // changes their mind. Without this the spinner is forever.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(180))
            guard let self, case .waiting = self.signIn, !self.isSignedIn else { return }
            self.signIn = .failed("Timed out waiting for the browser. Try again.")
        }
    }

    func signInFinished(error: String?) {
        signIn = error.map(SignInState.failed) ?? .idle
    }

    /// Opens the browser on the sign-in page, challenge and state included.
    ///
    /// One implementation for the Settings pane and the notch's sign-in
    /// panel. Opening `/desktop/auth` bare is what this used to do from one
    /// of them, and the page can only answer "this link is missing
    /// information" — nothing about the button looked wrong, which is why it
    /// survived. A second call site would have been a second chance to do it.
    ///
    /// Returns the local failure, if the challenge could not be written.
    @discardableResult
    func beginSignIn() -> String? {
        do {
            let url = try AuthCoordinator().signInURL(appBase: Self.appURL)
            signInStarted()
            // Same reason as a connect: the panel is pinned above the browser
            // window it is about to hand over to.
            notch.suspendForExternalFlow()
            NSWorkspace.shared.open(url)
            return nil
        } catch {
            // Writing the pending challenge is what fails here, and silently
            // opening the browser anyway would strand the user on a page that
            // cannot complete.
            return "Could not start sign-in. Check that Notch Metrics can write to "
                + "Application Support."
        }
    }

    /// Which settings pane to show. Driven by `notchmetrics://settings/<pane>`
    /// so a link — from the website, from a notification, from the notch —
    /// can land on the right page rather than on General.
    ///
    /// `NOTCH_DEBUG_PANE=integrations` opens straight to one. The URL scheme
    /// cannot be used for this during development: LaunchServices routes
    /// `notchmetrics://` to whichever copy is *registered*, which is the one
    /// in /Applications rather than the one just built.
    var settingsPane: SettingsPane =
        ProcessInfo.processInfo.environment["NOTCH_DEBUG_PANE"]
            .flatMap { SettingsPane(rawValue: $0) ?? SettingsPane.aliases[$0] } ?? .connections

    /// Read from Info.plist rather than hardcoded, so a build pointed at a
    /// local Worker and a release build run the same code path.
    static var apiURL: URL {
        let string = Bundle.main.object(forInfoDictionaryKey: "NMAPIBaseURL") as? String
        return URL(string: string ?? "") ?? URL(string: "https://api.notchmetrics.com")!
    }

    static var appURL: URL {
        let string = Bundle.main.object(forInfoDictionaryKey: "NMAppBaseURL") as? String
        return URL(string: string ?? "") ?? URL(string: "https://notchmetrics.com")!
    }

    /// Only the updater uses this, and only as the fallback for a Worker that
    /// is not answering. See `UpdateFeed`.
    static var assetsURL: URL {
        let string = Bundle.main.object(forInfoDictionaryKey: "NMAssetsBaseURL") as? String
        return URL(string: string ?? "") ?? URL(string: "https://assets.notchmetrics.com")!
    }

    init() {
        try? AppPaths.ensureDirectories()

        // Demo mode never touches the Keychain. Every read of it — the
        // token on each API call, a plugin's secret — prompts when the item
        // belongs to a differently-signed build of this app, and that dialog
        // lands on top of the screenshot demo mode exists to take, having
        // already blocked launch waiting for an answer.
        let secrets: any SecretStore = Self.isDemo ? InMemorySecretStore() : KeychainSecretStore()
        self.secrets = secrets
        self.auth = AuthStore(secrets: secrets)
        self.api = APIClient(baseURL: Self.apiURL, tokens: auth)
        self.cache = MetricsCache()
        self.alerts = AlertInbox()
        self.settingsStore = SettingsStore()
        self.plugins = PluginRegistry()
        self.connectors = ConnectorRegistry()
        self.updates = UpdateController(api: Self.apiURL, mirror: Self.assetsURL)

        let persistedLayout = Self.loadLayout()
        var model: NotchLayoutModel!
        model = NotchLayoutModel(layout: persistedLayout) { layout in
            Self.saveLayout(layout)
        }
        self.layoutModel = model
        self.notch = NotchWindowController(model: model)
    }

    func start() async {
        // First line of every run. A log that does not say which build wrote
        // it, or which server it was talking to, is a log that answers the
        // wrong question — most reports arrive after an update.
        Task { [api = Self.apiURL] in
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "?"
            let build = info?["CFBundleVersion"] as? String ?? "?"
            await LogFile.shared.write(
                "app", "started \(version) (\(build)) — api \(api.absoluteString)")
        }

        settings = await settingsStore.current
        plugins.setApproved(settings.approvedPlugins)
        plugins.onAdded = { [weak self] arrived in
            MainActor.assumeIsolated { self?.announceNewMetrics(arrived) }
        }
        plugins.start()

        connectors.setApproved(settings.approvedConnectors)
        connectors.onAdded = { [weak self] arrived in
            MainActor.assumeIsolated { self?.announceNewApps(arrived) }
        }
        connectors.start()
        migrateConnectorApprovals()
        publishAppOverrides()

        // Demo mode takes screenshots and must not reach the network; the
        // pane's states are reachable through NOTCH_DEBUG_UPDATE instead.
        if !Self.isDemo {
            updates.automatic = settings.checkForUpdatesAutomatically
            updates.start()
        }

        notch.apply(settings: settings)
        notch.start()

        // The chip in the notch's bottom corner. Pushed from the controller
        // rather than observed, so NotchUI stays ignorant of the updater.
        updates.onOfferChanged = { [weak self] version in
            self?.notch.availableUpdate = version
        }
        notch.availableUpdate = updates.state.offer

        isSignedIn = await auth.isSignedIn && !Self.isWelcomeDemo

        // No starter layout. It used to seed three Stripe tiles, which meant
        // a new user's notch was full of an app they had never connected and
        // every tile said "Connect Stripe". The empty state in NotchPanel
        // says what to do instead.
        if let preset = Self.demoPreset {
            needsUpgrade = Self.isUpgradeDemo
            layoutModel.replace(with: Self.demoLayout(preset))
            // Demo tiles go somewhere too: a click that does nothing in the
            // one mode built for screenshots is how a regression here would
            // be missed.
            notch.update(
                widgetLinks: WidgetLink.Catalogue(
                    byMetric: [
                        "github/ci_runs":
                            "https://github.com/{repository}/actions?query=branch%3A{branch}"
                    ],
                    byApp: [
                        "stripe": "https://dashboard.stripe.com",
                        "google-analytics": "https://analytics.google.com",
                        "github": "https://github.com",
                        "posthog": "https://eu.posthog.com",
                        "plausible": "https://plausible.io",
                        "google-search-console": "https://search.google.com/search-console",
                        "openai": "https://platform.openai.com/usage",
                        "anthropic": "https://console.anthropic.com",
                    ]))
            // Demo mode never refreshes, so the titles would otherwise miss
            // the time window a live notch shows — and a screenshot of the
            // demo is the place that most needs to look like the real thing.
            Task { await refreshMetricWindows() }
        }

        states =
            Self.isSkeletonDemo
            ? Dictionary(
                uniqueKeysWithValues: layoutModel.layout.widgets.map { ($0.id, TileState.loading) })
            : Self.demoPreset.map { Self.demoStates(for: layoutModel.layout, preset: $0) }
                ?? Self.placeholderStates(for: layoutModel.layout, signedIn: isSignedIn)
        notch.update(states: states)

        // Demo mode has numbers without an account, and the sign-in panel
        // would replace the very screenshot it exists to produce. Only the
        // notch's copy of the flag: everything else that reads `isSignedIn`
        // decides whether to hit the network, which demo mode must not.
        if Self.isDemo {
            notch.isSignedIn = true
            startAlerts()
        }

        // Signing in is the moment every catalogue-backed view is wrong: it
        // was rendered against an anonymous catalogue with no accounts in it.
        guard isSignedIn else {
            startRefreshing()
            stopAlerts()
            // The next account's notifications are not this one's, and a badge
            // surviving a sign-out is a privacy bug rather than a stale cache.
            Task {
                await alerts.clear()
                notch.unreadAlertCount = 0
            }
            return
        }
        catalogueChanged()

        // Connections first, then the poll. Adoption used to race the first
        // refresh, so a widget it was about to bind spent that round trip
        // saying "Connect Stripe" — and the fix arrived as a second render a
        // second later, which read as the notch changing its mind. Nothing
        // is painted from a guess now: until the list is in, the tiles are
        // skeletons.
        Task {
            await adoptConnections()
            startRefreshing()
            // After the connections, so the first feed page can name them.
            startAlerts()
        }
        Task { await loadAccount() }
    }

    /// Who the token belongs to. Drives the Account pane's identity line.
    ///
    /// Failures are silent on purpose: this is one line in a pane, and the
    /// pane says "Signed in" without it. An error banner for a name nobody
    /// asked to see would be the loudest thing on the screen.
    private func loadAccount() async {
        guard !Self.isDemo, isSignedIn else { return }
        account = try? await api.me().user
    }

    /// Signs this Mac out: revokes the token, then forgets everything it
    /// unlocked.
    ///
    /// The revoke goes first and is best-effort. A server that cannot be
    /// reached must not strand the user signed in — they asked to leave, and
    /// the token is unusable here the moment the Keychain copy is gone — but
    /// skipping it when it *can* be reached would leave a working credential
    /// in the account's device list.
    ///
    /// Widgets stay. A layout is the user's arrangement of their own notch,
    /// not account data, and deleting it on a sign-out means rebuilding it by
    /// hand after signing back in.
    func signOut() async {
        _ = try? await api.revokeThisDevice()
        await auth.clear()

        isSignedIn = false
        account = nil
        needsUpgrade = false
        signIn = .idle

        // Numbers, notifications and connection names all belong to the
        // account that has just left. A figure surviving a sign-out is the
        // next user of this Mac reading the last one's revenue.
        await cache.clear()
        connectionsKnowledge = .unknown
        connectionsByProvider = [:]
        notch.update(connectionNames: [:])
        stopAlerts()
        await alerts.clear()
        notch.unreadAlertCount = 0

        // Every catalogue-backed view was rendered against an account that no
        // longer exists here, and the tiles go back to their signed-out
        // placeholders.
        catalogueChanged()
        states = Self.placeholderStates(for: layoutModel.layout, signedIn: false)
        notch.update(states: states)
    }

    /// Points a widget with no account at the only one its provider has.
    ///
    /// A widget added while signed out has no `integrationId` — there were
    /// no accounts to choose from at the time — and nothing bound it
    /// afterwards, so the tile sat on "Connect Stripe" with Stripe plainly
    /// connected, and the only way out was opening the configure pane and
    /// picking the one option.
    ///
    /// Only when the choice is unambiguous. With two accounts there is a
    /// right answer and this does not know it, so that tile says "Pick a
    /// connection" and waits. Custom metrics are left alone: they have no
    /// integration by design.
    @discardableResult
    func adoptConnections() async -> Bool {
        guard isSignedIn else { return false }
        // Keyed on whether the list has been fetched, not on whether it came
        // back with anything in it: a user with no connections at all has an
        // empty dictionary legitimately, and testing that re-requested the
        // list on every call.
        if case .loaded = connectionsKnowledge {} else { await refreshConnectionNames() }

        var changed = false
        for widget in layoutModel.layout.widgets
        where widget.kind == .providerMetric && widget.integrationId?.isEmpty != false {
            guard let ids = connectionsByProvider[widget.appId], ids.count == 1 else { continue }
            var next = widget
            next.integrationId = ids[0]
            layoutModel.update(next)
            changed = true
        }
        return changed
    }

    /// Opens the notch's configure pane on a widget.
    ///
    /// Also leaves edit mode: the pane replaces the grid, so the handles and
    /// the dotted well behind it would be arranging something nobody can see.
    /// `isNew` marks a widget the browser has just added, which the pane
    /// commits with Add rather than Done.
    func beginConfiguring(_ id: String, isNew: Bool = false) {
        layoutModel.isEditing = false
        withAnimation(.snappy(duration: 0.28)) {
            notch.beginConfiguring(id, isNew: isNew)
        }
    }

    // MARK: - Real numbers

    private var refreshTask: Task<Void, Never>?

    /// The refresh a user action asked for, so the next action can cancel it.
    ///
    /// Separate from `refreshTask`, which is the five-minute poll: a config
    /// change should supersede the previous change's request, not the timer.
    private var pendingRefresh: Task<Void, Never>?

    /// The whole-layout batch in flight, so the next caller queues behind it
    /// rather than racing it, and the generation of the last caller to ask.
    ///
    /// Nothing used to serialise `refresh()`. It is called from the poll, from
    /// the refresh button, from connection adoption and from the widget
    /// browser the moment a tile is dropped in, and the batch takes four to
    /// ten seconds — so two or three ran concurrently as a matter of course,
    /// each committing a view of the notch it had assembled before the others
    /// existed. See `commit`.
    private var inFlightRefresh: Task<Void, Never>?
    private var refreshGeneration = 0

    /// A widget's settings changed, so its number is answering the old
    /// question.
    ///
    /// Three things, and the order matters. The tile drops to loading
    /// immediately — `refreshOne` then fills it, and shows a skeleton until
    /// it does, which is what makes a range switch look like a fetch rather
    /// than like nothing happening. The previous request is cancelled,
    /// because its answer is for a window nobody is looking at any more. And
    /// the new one waits a moment first: arrowing through a picker is four
    /// changes in a second, and each one is a request.
    func widgetConfigurationChanged(_ widgetId: String) {
        states[widgetId] = .loading
        notch.update(states: states)

        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.refreshOne(widgetId)
        }
    }

    /// Refetches the one widget whose settings changed, not the notch it is in.
    ///
    /// The batch is the right shape for a poll and the wrong shape for a
    /// picker. It is serialised per connection and answers only when its
    /// slowest group has, so a tile waited on every other integration in the
    /// layout before it could show the window somebody had just chosen —
    /// eight to ten seconds with four payment providers, a GitHub account and
    /// two LLM connectors ahead of it, against under one for the metric
    /// itself. A skeleton held that long does not read as a slow fetch; it
    /// reads as a widget that never loads, which is what this was reported as.
    ///
    /// Falls back to the whole batch for the cases it cannot answer alone: an
    /// unbound widget, a transport failure that is everybody's problem, and
    /// `not_found` — where the widget has to be rebound to an account and
    /// `refresh()` owns that.
    private func refreshOne(_ widgetId: String) async {
        guard !Self.isDemo, isSignedIn,
            let widget = layoutModel.layout.widgets.first(where: { $0.id == widgetId }),
            let integrationId = widget.integrationId, !integrationId.isEmpty,
            let metric = widget.metric, !metric.isEmpty
        else {
            await refresh()
            return
        }

        // Same `defer` discipline as the batch: every exit clears it, because
        // a spinner that never stops is worse than no spinner at all.
        notch.update(refreshing: [widgetId])
        defer { notch.update(refreshing: []) }

        do {
            let result = try await api.metric(
                integrationId: integrationId, metric: metric,
                granularity: widget.range.defaultGranularity.rawValue,
                range: widget.range.rawValue,
                series: widget.chart != .none,
                params: widget.params)
            // Superseded while it was in flight: the user has moved the picker
            // on, and this answer is for the setting before last.
            guard !Task.isCancelled else { return }

            switch result {
            case .success(let series):
                states[widgetId] = .value(series)
                notch.update(states: states)
                await cache.store(
                    series, widgetID: widgetId, range: widget.range, params: widget.params)
            case .failure(let failure):
                logMetricFailure(widget, failure)
                // The account is gone. Rebinding lives in `refresh()`, and
                // doing it here would be a second copy of a thing that is
                // already subtle.
                if failure.code == .notFound {
                    await refresh()
                    return
                }
                // `unsupported` is the server saying the widget is not
                // finished — no repository picked yet — rather than broken.
                states[widgetId] =
                    failure.code == .unsupported
                    ? .needsSetup(failure.message)
                    : .failed(reason: failure.message)
                notch.update(states: states)
            }
        } catch {
            if Task.isCancelled { return }
            // Signed out, a lapsed plan, no network: none of those are about
            // this widget, and `refresh()` already says the right thing about
            // each of them across the whole notch.
            await refresh()
        }
    }

    /// Keeps the notch's tiles filled from the API.
    ///
    /// One batch request for the whole layout rather than one per tile: eight
    /// widgets usually point at two or three integrations, and fanning out
    /// defeats the per-integration spacing that keeps us inside a provider's
    /// rate limit.
    func startRefreshing() {
        guard !Self.isDemo else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Five minutes on AC. The notch is a glance, not a dashboard,
                // and every poll costs the user's provider rate limit — which
                // is also why this now *stops* rather than running at a fixed
                // interval with the lid shut. On an eight-hour sleep that used
                // to be ~96 wake-ups and 96 hits on somebody's Stripe limit.
                switch EnergyPolicy.metricCadence(self.gate.conditions) {
                case .suspended:
                    // Idle rather than spin. A conditions change pokes.
                    try? await Task.sleep(for: .seconds(30))
                case .every(let interval):
                    await self.refresh()
                    try? await Task.sleep(for: interval)
                }
            }
        }
    }

    /// Looks for the plan going live, for a few minutes after Upgrade is pressed.
    ///
    /// The ordinary poll is five minutes and deliberately sparse, which is
    /// the right cadence for numbers and the wrong one for the thirty seconds
    /// after somebody has paid: a notch still saying "Your trial has ended"
    /// reads as the payment not having worked. The refresh button is hidden
    /// in this state, so there is nothing to press either.
    ///
    /// Bounded on purpose — twelve checks at fifteen seconds, stopping the
    /// moment the plan is live. It only ever runs just after an explicit
    /// press, which is the one moment polling harder is worth the requests.
    func watchForUpgrade() {
        upgradeWatch?.cancel()
        upgradeWatch = Task { [weak self] in
            for _ in 0..<12 {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled, self.needsUpgrade else { return }
                await self.refresh()
                if !self.needsUpgrade { return }
            }
        }
    }

    func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// The refresh button in the notch.
    ///
    /// Guarded, and it holds the button for one full turn of the glyph: a
    /// batch that answers from cache in 40ms otherwise cuts the rotation
    /// short and the press looks like it missed. Note this does not bypass the *server's*
    /// cache — a daily figure is held for fifteen minutes there, so pressing
    /// this twice in a minute returns the same number by design.
    func refreshNow() async {
        guard !notch.isRefreshing else { return }
        notch.isRefreshing = true
        defer { notch.isRefreshing = false }

        async let fetch: Void = refresh()
        async let floor: Void = Self.spinFloor()
        _ = await (fetch, floor)
    }

    /// Long enough for the glyph's one turn to finish before the button
    /// comes back, so a 40ms cached reply does not cut the rotation short.
    private static func spinFloor() async {
        try? await Task.sleep(for: .milliseconds(700))
    }

    /// Names every tile's account, so a tile can say which one it reads.
    ///
    /// Separate from the metric fetch: the labels change when somebody renames
    /// a connection, not when a number does, and a failure here should leave
    /// the tiles showing numbers rather than take them down with it.
    func refreshConnectionNames() async {
        guard isSignedIn else { return }
        guard let all = try? await api.connections() else {
            // Only downgrade a first attempt. A poll that fails while the
            // list is already known should leave the tiles reading off the
            // list we have rather than fall back to "offline".
            if case .unknown = connectionsKnowledge { connectionsKnowledge = .unreachable }
            return
        }
        connectionsKnowledge = .loaded
        notch.update(
            connectionNames: Dictionary(
                uniqueKeysWithValues: all.map { ($0.id, $0.label) }))
        connectionsByProvider = Dictionary(grouping: all, by: \.provider)
            .mapValues { $0.map(\.id) }
    }

    /// Tells the notch which metrics depend on a time window, so those tiles
    /// write the window into their title.
    ///
    /// The server's descriptor is the one place that knows — the same flags
    /// that decide whether the configure pane shows a Range control at all.
    /// Custom metrics answer from their plugin manifest. Read here rather
    /// than stored on the widget so a widget made before this existed, or a
    /// metric whose descriptor changes, is labelled correctly on the next
    /// refresh without a migration.
    func refreshMetricWindows() async {
        var keys = Set<String>()
        // The demo's own, before the request. This walk reads the catalogue
        // over the network, and a screenshot taken against a Worker that is
        // not running would miss the "· 30d" every windowed tile in a live
        // notch carries — which is the one difference a reader would notice.
        if Self.isDemo { keys.formUnion(Self.demoTimeWindowedMetrics) }
        for plugin in plugins.plugins {
            if plugin.manifest?.supportsSeries == true { keys.insert("custom/\(plugin.id)") }
        }
        // Custom apps. Missing entirely until now, which is why a connector
        // tile lost its "· 30d" while a server tile beside it kept one: this
        // walk knew about legacy plugins and about the catalogue, and the
        // format that replaced the first was never added to it.
        for connector in connectors.connectors {
            guard let manifest = connector.manifest else { continue }
            for metric in manifest.metrics where metric.shape.usesTimeWindow {
                keys.insert("custom/\(CustomMetricRef(appId: connector.id, metricId: metric.id).packed)")
            }
        }
        // Not gated on sign-in: the catalogue is readable either way, and a
        // demo or signed-out notch should label its tiles the same as a live one.
        var links: WidgetLink.Catalogue?
        if let catalogue = try? await api.catalogue() {
            links = WidgetLink.Catalogue()
            for connector in catalogue.allConnectors {
                // Where a tile of this connector's goes when it is clicked,
                // read from the same walk rather than a second request: both
                // are facts about a metric that only the catalogue holds.
                if let dashboard = connector.dashboardUrl {
                    links?.byApp[connector.id] = dashboard
                }
                for metric in connector.metrics {
                    if metric.supportsSeries || metric.supportsCompare {
                        keys.insert("\(connector.id)/\(metric.id)")
                    }
                    if let template = metric.linkTemplate {
                        links?.byMetric["\(connector.id)/\(metric.id)"] = template
                    }
                }
            }
        }
        notch.update(timeWindowedMetrics: keys)
        // Only when the catalogue actually answered. Pushing an empty one
        // after a failed request would make every tile unclickable until the
        // next successful fetch — and would wipe the demo notch's links, which
        // is how this was found.
        if let links { notch.update(widgetLinks: links) }
    }

    /// Fetches once, now. Called on launch, on a timer, and after a widget is
    /// added so a new tile fills in rather than sitting on "Loading".
    ///
    /// One batch at a time, with at most one caller queued behind it.
    ///
    /// Chained rather than joined. A caller that attached itself to the
    /// request already in flight would be answered about a notch that did not
    /// contain its own widget — the browser refreshes the instant a tile is
    /// dropped in, and a batch running at that moment was built before the
    /// tile existed. So each caller waits for the current batch and then
    /// issues its own.
    ///
    /// Queued callers past the first drop out instead of each costing another
    /// ten-second round trip: the batch covers the whole layout, so the last
    /// caller's run answers for everything the ones behind it would have
    /// asked. That is what keeps four pickers touched in a second from
    /// becoming four batches back to back.
    func refresh(rebindAllowed: Bool = true) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let previous = inFlightRefresh
        let task = Task { [weak self] in
            await previous?.value
            guard let self, self.refreshGeneration == generation else { return }
            await self.performRefresh(rebindAllowed: rebindAllowed)
        }
        inFlightRefresh = task
        await task.value
        // Only the last one clears it, so a caller still queued behind this
        // task does not lose the thing it is waiting on.
        if refreshGeneration == generation { inFlightRefresh = nil }
    }

    /// `rebindAllowed` is the recursion stop. A widget whose account 404s is
    /// unbound and re-adopted, which re-enters here — and if the rebound id
    /// 404s too (a connections list that disagrees with the metrics route)
    /// that is an unbounded loop hammering the Worker. One attempt, then the
    /// tile says "Pick a connection" and waits for the next poll.
    ///
    /// Called through `refresh()` from everywhere except that one re-entry,
    /// which goes straight here: it is already inside the queue's single slot,
    /// and queueing behind itself is a deadlock.
    private func performRefresh(rebindAllowed: Bool = true) async {
        // Demo mode draws its own numbers and must not reach the network for
        // real ones. The poll already skips it; this covers every other way
        // in — the refresh button, and the connection adoption that follows
        // a sign-in.
        guard !Self.isDemo else { return }

        // Alongside, not awaited: the tiles should not wait on the labels to
        // show their numbers.
        Task { await refreshConnectionNames() }
        Task { await refreshMetricWindows() }
        guard isSignedIn else {
            states = Self.placeholderStates(for: layoutModel.layout, signedIn: false)
            notch.update(states: states)
            return
        }

        let widgets = layoutModel.layout.widgets.filter {
            $0.integrationId?.isEmpty == false && $0.metric?.isEmpty == false
        }

        // A widget that lost its account keeps its last number otherwise —
        // a figure on screen attributed to nothing. Say what it needs instead,
        // and say the right one: a provider with no account at all needs
        // connecting, while one that has accounts needs a choice. Both used
        // to read "Connect Stripe", which is the wrong instruction for the
        // second and the reason a signed-in notch could look signed out.
        // Custom metrics are answered below, by the runner rather than the
        // Worker, so they are not "unfetchable" — they were, for as long as
        // this sweep was the only thing that saw them, which is why a local
        // metric showed "Connect custom" forever.
        var fetchable = Set(widgets.map(\.id))
        fetchable.formUnion(
            layoutModel.layout.widgets.filter { $0.kind == .customMetric }.map(\.id))
        for widget in layoutModel.layout.widgets where !fetchable.contains(widget.id) {
            states[widget.id] = setupState(for: widget)
        }

        // Alongside the batch, not after it. A slow plugin must not hold up
        // every provider tile in the notch, and the two paths write disjoint
        // widgets so there is nothing to order between them.
        Task {
            await refreshPlugins()
            await refreshConnectors()
        }

        guard !widgets.isEmpty else {
            // Not `placeholderStates`: that answers for every widget at once
            // and would overwrite what the loop above just worked out.
            notch.update(states: states)
            return
        }

        // Last known values first, so a tile shows yesterday's number while
        // the request is in flight rather than a skeleton.
        //
        // Keyed on "has nothing to say yet" rather than on `== nil`:
        // `start()` seeds a state for every widget before the first refresh
        // runs, so nothing was ever nil here and the disk cache was never
        // read — the notch went to a skeleton on every launch with a
        // perfectly good number sitting on disk. Deliberately not "is not a
        // value": that would also overwrite a `.failed` tile with yesterday's
        // number on every poll, and a provider that is still broken an hour
        // later should say so rather than quietly serve stale data forever.
        var before = states
        var next = before
        for widget in widgets where isPending(next[widget.id]) {
            if let cached = await cache.load(
                widgetID: widget.id, range: widget.range, params: widget.params)
            {
                next[widget.id] = .value(cached)
            } else {
                next[widget.id] = .loading
            }
        }
        commit(next, queried: widgets, unchangedFrom: before)
        // What this run has itself put on screen, which is the baseline the
        // batch's own answers are measured against below. Re-read rather than
        // assumed: `commit` declines to write a tile somebody else has
        // answered in the meantime, so `next` is not reliably what is showing.
        before = states

        // Set when a widget turned out to point at an account that is gone,
        // so adoption gets a chance to rebind it before the next poll.
        var staleBindings = false

        // Widgets to unbind once this run's states are written. Applied after
        // `commit` rather than inside the loop: unbinding is a change to the
        // widget, and `commit` declines to write an answer onto a widget that
        // is no longer asking the question that was sent — so rebinding
        // mid-loop would throw away the "Pick a connection" the rebind exists
        // to put there.
        var rebinds: [NotchWidget] = []

        // The tiles say they are being checked for as long as the batch is in
        // flight. Cleared in a `defer` rather than after the call: every exit
        // from here — a throw, a superseded response, a rebind that returns
        // early — has to clear it, and a spinner that never stops is a worse
        // bug than no spinner at all.
        notch.update(refreshing: Set(widgets.map(\.id)))
        defer { notch.update(refreshing: []) }

        do {
            let results = try await api.batch(widgets.map(MetricQueryRequest.init(widget:)))
            // Belt to `commit`'s braces, and no longer the thing that keeps a
            // superseded answer off the tiles. `refresh()` runs this in a task
            // of its own so that one caller walking away does not cancel a
            // batch the others are queued behind — which means a caller's
            // cancellation no longer reaches here. `commit` is what declines
            // the stale write now, per widget and on the evidence rather than
            // on the caller's lifetime.
            guard !Task.isCancelled else { return }
            guard results.count == widgets.count else { return }

            for (widget, result) in zip(widgets, results) {
                switch result {
                case .success(let series):
                    next[widget.id] = .value(series)
                    await cache.store(
                        series, widgetID: widget.id, range: widget.range, params: widget.params)
                case .failure(let failure):
                    logMetricFailure(widget, failure)
                    // `not_found` is the server saying this widget points at
                    // an account that is gone — disconnected, or reconnected
                    // under a new id. Left alone the tile reads "That
                    // integration no longer exists", which is both alarming
                    // and useless: there is no such thing to go and look at.
                    // Clearing the id turns it back into an unbound widget,
                    // which `adoptConnections` rebinds on the next pass when
                    // the provider has exactly one account — so the usual
                    // case fixes itself and the rest say "Pick a connection".
                    if failure.code == .notFound {
                        // The verdict either way — never the server's
                        // sentence, which names a thing there is no way to
                        // go and look at.
                        next[widget.id] = setupState(for: widget)
                        if rebindAllowed {
                            var rebound = widget
                            rebound.integrationId = nil
                            rebinds.append(rebound)
                            staleBindings = true
                        }
                        continue
                    }
                    // Keep a cached number on screen rather than replacing
                    // it with an error: a stale figure beats a blank tile
                    // while a provider is down.
                    //
                    // Only while it still answers the question being asked.
                    // The number carries the window and the metric it was
                    // fetched for, and holding it through a failure on a
                    // *different* range left the old figure under the new
                    // range's title — "Tokens · 7d" showing the 30-day total,
                    // with nothing on screen to say the switch had failed.
                    // A wrong number labelled confidently is worse than the
                    // error it is standing in for.
                    if case .value(let shown) = next[widget.id],
                       shown.range == widget.range,
                       widget.metric == nil || shown.metric == widget.metric {
                        continue
                    }
                    // `unsupported` is the server saying the widget is not
                    // finished — a GitHub tile with no repository picked yet,
                    // say. That is a setup step, not a failure, and a freshly
                    // dropped tile should not greet somebody in red.
                    next[widget.id] =
                        failure.code == .unsupported
                        ? .needsSetup(failure.message)
                        : .failed(reason: failure.message)
                }
            }
            // The batch answered, so the plan is live again — subscribing
            // takes effect on the next poll rather than needing a relaunch.
            needsUpgrade = false
            commit(next, queried: widgets, unchangedFrom: before)
            for rebound in rebinds { layoutModel.update(rebound) }

            // Once, and only when something actually came loose: adoption only
            // reports a change when it bound a widget that had nothing.
            if staleBindings, await adoptConnections() {
                await performRefresh(rebindAllowed: false)
            }
        } catch {
            // A cancelled request is not a failure, it is a request nobody
            // wants the answer to any more. URLSession surfaces cancellation
            // as a transport error, which `tileState` reads as "could not
            // reach Notch Metrics" — so without this, changing a setting
            // twice quickly painted a network error across the whole notch.
            //
            // Rarely reached since `refresh()` began running this in its own
            // task; the same guard now lives per widget in `commit`.
            if Task.isCancelled { return }

            Task {
                await LogFile.shared.write(
                    "metric", "batch of \(widgets.count) failed: \(error)")
            }
            // A lapsed plan is not a per-tile failure. Painting "Subscription
            // needed" across eight widgets says the same thing eight times and
            // leaves nowhere to press; the notch swaps to one panel instead.
            if Self.isSubscriptionRequired(error) { needsUpgrade = true }
            let state = Self.tileState(for: error)
            for widget in widgets where !isValue(next[widget.id]) {
                next[widget.id] = state
            }
            commit(next, queried: widgets, unchangedFrom: before)
        }
    }

    /// What a whole-request failure should say on every tile.
    ///
    /// Every one of these used to read "Could not reach Notch Metrics", which
    /// is only true for one of them. A rejected request, an ended trial and a
    /// signed-out app each send somebody to check their wifi, and the real
    /// cause is on screen nowhere.
    /// Whether this is the server saying the plan has lapsed.
    ///
    /// Takes `any Error` deliberately. Swift narrows a `catch` to the single
    /// concrete type a `do` block can throw, so an inline cast there reads as
    /// "always succeeds" today and silently stops matching the moment anything
    /// in that block throws something else.
    static func isSubscriptionRequired(_ error: any Error) -> Bool {
        guard let api = error as? APIError else { return false }
        if case .subscriptionRequired = api { return true }
        return false
    }

    static func tileState(for error: any Error) -> TileState {
        guard let api = error as? APIError else {
            return .failed(reason: "Could not reach Notch Metrics")
        }
        switch api {
        case .offline, .transport:
            return .failed(reason: "Could not reach Notch Metrics")
        case .unauthorized:
            return .needsSetup("Sign in again")
        case .subscriptionRequired:
            return .needsSetup("Subscription needed")
        case .rateLimited:
            return .failed(reason: "Too many requests — retrying shortly")
        case .server(_, _, let message):
            // The server's own words when it bothered to send any. This is
            // what finally says "Invalid request." out loud rather than
            // blaming the network for it.
            return .failed(reason: message ?? "Notch Metrics refused that request")
        case .decoding:
            return .failed(reason: "Could not read that response")
        }
    }

    private func isValue(_ state: TileState?) -> Bool {
        if case .value = state { return true }
        return false
    }

    /// The one line worth having when a widget misbehaves on one range and not
    /// another: which widget, which window, the bucket that was actually asked
    /// for, and the server's own sentence — which carries the provider's,
    /// rather than a bare status.
    ///
    /// One copy because there were two, and they had drifted. The batch's
    /// printed `widget.granularity` — the field frozen when a widget is
    /// created, which no control has ever changed — while every request is
    /// built from `range.defaultGranularity`. So a 30d tile that asked for
    /// daily buckets was logged as `[hour]`, which is the exact signature of a
    /// bug fixed long ago in `MetricQueryRequest`. A log that names a dead bug
    /// at the moment a widget is failing costs more than no log at all.
    ///
    /// `retryAfterSeconds` is here because it is the only number that says how
    /// long a `rate_limited` will last: the server obeys a provider's own
    /// `Retry-After` literally. Without it a rate limit that clears in a
    /// minute and a hard spend limit that never clears read identically.
    private func logMetricFailure(_ widget: NotchWidget, _ failure: MetricFailure) {
        let granularity = widget.range.defaultGranularity.rawValue
        let retry = failure.retryAfterSeconds.map { ", retry in \($0)s" } ?? ""
        Task {
            await LogFile.shared.write(
                "metric",
                "\(widget.appId)/\(widget.metric ?? "?") \(widget.range.rawValue)"
                    + " [\(granularity)] → \(failure.code.rawValue):"
                    + " \(failure.message)\(retry)")
        }
    }

    /// Writes one refresh's results without taking the rest of the notch with
    /// them.
    ///
    /// `states` is a dictionary and this used to be `states = next`, where
    /// `next` was copied before a request that takes four to ten seconds.
    /// That is a last-writer-wins overwrite of every tile, including the ones
    /// the run never asked about — so a widget added while a batch was in
    /// flight had its key **dropped**, and a key that is absent renders as
    /// `.loading`: a skeleton that never fills, until the next poll up to five
    /// minutes later. That is the "preview shows no numbers" report, and it
    /// was intermittent because it depended on whether a batch happened to be
    /// in flight when the tile was added.
    ///
    /// Three conditions, and each one stands for a way the old assignment lied.
    /// Only the widgets this run queried. Only where nothing else has written
    /// one since, because a newer answer for the same tile is the better one
    /// by definition — `refreshOne` answers in well under a second and lost
    /// that race routinely. And only while the widget is still asking the same
    /// question, since the request carries the range and params it was built
    /// with and an answer that lands after the picker moved belongs to a
    /// window nobody is looking at.
    private func commit(
        _ resolved: [String: TileState],
        queried: [NotchWidget],
        unchangedFrom before: [String: TileState]
    ) {
        let live = Dictionary(
            layoutModel.layout.widgets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for widget in queried {
            guard let state = resolved[widget.id], let current = live[widget.id],
                MetricQueryRequest(widget: current) == MetricQueryRequest(widget: widget),
                states[widget.id] == before[widget.id]
            else { continue }
            states[widget.id] = state
        }
        notch.update(states: states)
    }

    /// Runs the local metrics that are due and paints what they return.
    ///
    /// This is the half that never existed. `PluginRunner` had no callers at
    /// all, so a custom metric could be written, approved and listed, and
    /// still never produce a number — the refresh loop only ever spoke to the
    /// Worker.
    ///
    /// Deliberately not inside the provider batch. These are separate
    /// processes against separate APIs on separate schedules; the only thing
    /// the two paths share is where the answer lands.
    private func refreshPlugins() async {
        // Custom-app widgets are answered by `refreshConnectors`: one process
        // per app for all of its metrics, rather than one per metric. The two
        // are told apart by whether `customMetricId` names an app — see
        // `CustomMetricRef`.
        let widgets = layoutModel.layout.widgets.filter {
            $0.kind == .customMetric
                && !CustomMetricRef(packed: $0.customMetricId ?? "").isConnector
        }
        guard !widgets.isEmpty else { return }

        // Keyed by plugin id, because several widgets may read the same
        // metric at different ranges and each needs its own answer.
        let byID = Dictionary(plugins.plugins.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        await pluginSchedule.retain(ids: Set(byID.keys))

        let runner: PluginRunner
        do {
            runner = try PluginRunner(secrets: secrets)
        } catch {
            // No Node, or no runner script. Every local tile says the same
            // thing, because the remedy is the same for all of them and it is
            // the user's to apply.
            let reason = Self.pluginSetupFailure(error)
            for widget in widgets { states[widget.id] = .failed(reason: reason) }
            notch.update(states: states)
            return
        }

        let runnable = widgets.compactMap { widget -> (NotchWidget, LoadedPlugin)? in
            guard let id = widget.customMetricId, let plugin = byID[id] else { return nil }
            return (widget, plugin)
        }

        // A plugin not yet approved, or rewritten since, is not a failure —
        // it is a question for the user, and the tile says so rather than
        // reporting an error nobody caused.
        for (widget, plugin) in runnable {
            switch plugin.state {
            case .pendingApproval: states[widget.id] = .needsSetup("Enable in Settings")
            case .modified: states[widget.id] = .needsSetup("Changed — review it")
            case .invalid(let reason): states[widget.id] = .failed(reason: reason)
            case .ready: break
            }
        }

        let due = await pluginSchedule.due(runnable.map(\.1))
        let dueIDs = Set(due.map(\.id))
        guard !dueIDs.isEmpty else {
            notch.update(states: states)
            return
        }

        // Serially, on purpose. Each run is a process, and a notch full of
        // local metrics starting six Node processes at once on battery is the
        // opposite of the "lightweight" this is supposed to be.
        for (widget, plugin) in runnable where dueIDs.contains(plugin.id) {
            guard let manifest = plugin.manifest else { continue }
            do {
                let value = try await runner.run(plugin)
                await pluginSchedule.recordRun(plugin)
                states[widget.id] = .value(
                    value.series(manifest: manifest, window: .of(widget.range)))
            } catch {
                // Recorded even on failure: a metric whose API is down must
                // not be retried every tick.
                await pluginSchedule.recordRun(plugin)
                states[widget.id] = .failed(reason: Self.pluginFailure(error))
            }
        }
        notch.update(states: states)
    }

    /// Names and icons for installed custom apps.
    ///
    /// `AppCatalog` ships the marks for connectors we serve, compiled into the
    /// asset catalogue — which an app written on this machine can never be in.
    /// This is the one route by which a custom app's own icon reaches the
    /// notch tile, the gallery and a banner, and it is why a custom widget
    /// carries its app's id rather than a shared "custom".
    private func publishAppOverrides() {
        var overrides: [String: MetricApp] = [:]

        for app in connectors.connectors {
            guard let manifest = app.manifest else { continue }
            overrides[LocalCatalogue.id(for: app.id).lowercased()] = MetricApp.custom(
                id: LocalCatalogue.id(for: app.id),
                name: manifest.name,
                icon: manifest.icon,
                iconFile: app.iconURL)
            // Also under the bare id, which is what a widget added from the
            // gallery stores. Both keys, because the gallery's entry id and
            // the widget's appId are not the same string.
            overrides[app.id.lowercased()] = overrides[
                LocalCatalogue.id(for: app.id).lowercased()]
        }

        notch.update(appOverrides: overrides)
    }

    /// Answers every custom-app tile, one process per app.
    ///
    /// The batching is the whole reason the connector format exists. Six tiles
    /// from one app are six metrics in a single run that reads the credential
    /// once, where the single-metric path would be six Node launches per tick.
    private func refreshConnectors() async {
        let widgets = layoutModel.layout.widgets.filter {
            $0.kind == .customMetric
                && CustomMetricRef(packed: $0.customMetricId ?? "").isConnector
        }
        guard !widgets.isEmpty else { return }

        // Republished here as well as at launch: an app installed or enabled
        // while running changes its tile's name and icon, and nothing else
        // would notice until the next relaunch.
        publishAppOverrides()

        let byID = Dictionary(
            connectors.connectors.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        await connectorSchedule.retain(ids: Set(byID.keys))

        let runner: ConnectorRunner
        do {
            runner = try ConnectorRunner(secrets: secrets)
        } catch {
            let reason = Self.pluginSetupFailure(error)
            for widget in widgets { states[widget.id] = .failed(reason: reason) }
            notch.update(states: states)
            return
        }

        // Grouped by app, and within an app by the range each tile asked for:
        // two widgets on the same metric over different windows are two
        // requests, and one run can carry both.
        var byApp: [String: [(NotchWidget, CustomMetricRef)]] = [:]
        for widget in widgets {
            let ref = CustomMetricRef(packed: widget.customMetricId ?? "")
            guard let appId = ref.appId else { continue }
            byApp[appId, default: []].append((widget, ref))
        }

        for (appId, members) in byApp {
            guard let app = byID[appId] else {
                // Installed once, gone now. Said plainly rather than left
                // spinning: the folder was removed and no amount of waiting
                // brings it back.
                for (widget, _) in members {
                    states[widget.id] = .failed(reason: "App not installed")
                }
                continue
            }

            switch app.state {
            case .pendingApproval:
                for (widget, _) in members {
                    states[widget.id] = .needsSetup("Enable in Settings")
                }
                continue
            case .modified:
                // The only way into this state is an app asking for more than
                // it was enabled for, so the tile can say so. An upgrade never
                // lands here — `migrateConnectorApprovals` adopts what was
                // already agreed to rather than re-asking.
                for (widget, _) in members {
                    states[widget.id] = .needsSetup("Wants more access")
                }
                continue
            case .invalid(let reason):
                for (widget, _) in members { states[widget.id] = .failed(reason: reason) }
                continue
            case .ready:
                break
            }

            // A widget that has never answered, or one the user has just
            // reconfigured — `widgetConfigurationChanged` marks it `.loading`
            // — must not wait out the app's refresh interval. The interval
            // exists to stop polling, not to make a changed setting take
            // fifteen minutes; without this a tile sat on a spinner for ever,
            // because the skip below also leaves its state untouched.
            let awaiting = members.contains { widget, _ in
                switch states[widget.id] {
                case nil, .loading: true
                default: false
                }
            }
            if !awaiting, await !connectorSchedule.isDue(app) { continue }

            // A declared host credential that is missing or expired fails every
            // metric with one actionable reason, rather than letting each
            // request come back as an opaque 401 from inside the connector.
            if let problem = runner.hostCredentialProblem(app) {
                for (widget, _) in members { states[widget.id] = .needsSetup(problem) }
                continue
            }

            let descriptors = Dictionary(
                (app.manifest?.metrics ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let requests = members.map { widget, ref in
                ConnectorMetricRequest(
                    id: widget.id,
                    metric: ref.metricId,
                    window: .of(widget.range),
                    params: widget.params)
            }

            do {
                let outcomes = try await runner.run(app, metrics: requests)
                await connectorSchedule.recordRun(app)

                // Matched by the widget's own id, which the request carried
                // and the outcome echoes.
                //
                // Not by metric id: two widgets can ask for the same metric
                // with different params — one npm package per tile — and
                // keying by `outcome.metric` made the second answer overwrite
                // the first, so both tiles showed one package's number and one
                // package's chart. Not by position either: that works until
                // anything reorders, and then it is a confidently wrong number
                // rather than an error.
                var answers: [String: ConnectorMetricOutcome] = [:]
                for outcome in outcomes { answers[outcome.id] = outcome }

                for (widget, ref) in members {
                    guard let outcome = answers[widget.id] else {
                        // Asked for and not answered. A tile saying nothing is
                        // worse than one saying the connector skipped it.
                        states[widget.id] = .failed(reason: "No answer")
                        continue
                    }
                    switch outcome {
                    case let .success(_, _, result):
                        guard let descriptor = descriptors[ref.metricId] else {
                            states[widget.id] = .failed(reason: "Unknown metric")
                            continue
                        }
                        states[widget.id] = .value(
                            result.series(descriptor: descriptor, window: .of(widget.range)))
                    case let .failure(_, _, code, _):
                        // Per metric, so one broken endpoint does not blank the
                        // other five tiles from the same app.
                        states[widget.id] = .failed(reason: code.shortReason)
                    }
                }
            } catch {
                // Recorded even on failure: an app whose API is down must not
                // be retried every tick.
                await connectorSchedule.recordRun(app)
                let reason = Self.pluginFailure(error)
                for (widget, _) in members { states[widget.id] = .failed(reason: reason) }
            }
        }
        notch.update(states: states)
    }

    /// What a tile says when the runner could not start at all.
    static func pluginSetupFailure(_ error: any Error) -> String {
        guard let error = error as? PluginRunnerError else { return "Could not start" }
        switch error {
        case .nodeMissing: return "Node not found"
        case .nodeTooOld: return "Node too old"
        case .runnerMissing: return "Runner missing"
        default: return "Could not start"
        }
    }

    /// What a tile says when one run failed. Short enough for a notch tile —
    /// the detail is in the plugin's own log.
    static func pluginFailure(_ error: any Error) -> String {
        guard let error = error as? PluginRunnerError else { return "Failed" }
        switch error {
        case .timedOut: return PluginFailureCode.timeout.shortReason
        case .failed(let code, _): return code.shortReason
        case .unreadableOutput: return "Bad output"
        case .spawnFailed: return "Could not start"
        case .nodeMissing, .nodeTooOld, .runnerMissing: return Self.pluginSetupFailure(error)
        }
    }

    /// What a widget with no usable account should say.
    ///
    /// Only ever a verdict once the connections are in. Before that the tile
    /// keeps loading: "Connect Stripe" is a specific, actionable and wrong
    /// instruction when the account is connected and the list simply has not
    /// arrived, and it is the message somebody sees for the whole of a cold
    /// launch. Saying nothing for a moment costs nothing; sending somebody to
    /// reconnect an account that works costs them the trip.
    private func setupState(for widget: NotchWidget) -> TileState {
        switch connectionsKnowledge {
        case .unknown:
            return .loading
        case .unreachable:
            return .failed(reason: "Could not reach Notch Metrics")
        case .loaded:
            return connectionsByProvider[widget.appId]?.isEmpty == false
                ? .needsSetup("Pick a connection")
                : .needsSetup("Connect \(AppCatalog.resolve(widget.appId).name)")
        }
    }

    /// A tile that has not yet been told anything — nothing on screen that
    /// the last-known number would be displacing.
    private func isPending(_ state: TileState?) -> Bool {
        guard let state else { return true }
        if case .loading = state { return true }
        return false
    }

    /// Says so when an agent writes a metric into Application Support.
    ///
    /// The MCP server and the CLI write there while the app is running, so
    /// this is something that happens *to* the notch. Without it the agent
    /// finishes by saying "enable it in Settings" and nothing on screen has
    /// changed — the user has no reason to believe a thing arrived.
    ///
    /// It is deliberately an ordinary banner rather than a system
    /// notification: the metric is not urgent, it is not from a server, and
    /// the notch is where it is going to live.
    private func announceNewMetrics(_ arrived: [LoadedPlugin]) {
        guard !arrived.isEmpty else { return }

        let title =
            arrived.count == 1
            ? "New widget added"
            : "\(arrived.count) new widgets added"
        let body =
            arrived.count == 1
            ? "\(arrived[0].displayName) — enable it in Settings to start it."
            : "\(arrived.map(\.displayName).joined(separator: ", ")) — enable them in Settings."

        present(
            NotchAlert(
                id: "plugin-added-\(arrived.map(\.id).sorted().joined(separator: "-"))",
                seq: 0, integrationId: nil, provider: arrived.count == 1 ? (arrived[0].manifest?.appId ?? AppCatalog.customId) : AppCatalog.customId,
                connectionLabel: "", typeId: "plugin_added", severity: .info,
                title: title, body: body, amount: nil, currency: nil, url: nil,
                occurredAt: ISO8601.string(from: Date()),
                createdAt: ISO8601.string(from: Date()), read: false, alert: true))
    }

    /// Tells the user an app arrived, with the same banner a metric gets.
    ///
    /// Said in widgets rather than in apps, because a widget is the thing the
    /// user is about to see in the notch and an "app" installed by an agent
    /// means nothing to them until a number shows up.
    private func announceNewApps(_ arrived: [LoadedConnector]) {
        guard !arrived.isEmpty else { return }

        let metrics = arrived.reduce(0) { $0 + $1.metricCount }
        let title = metrics == 1 ? "New widget added" : "\(metrics) new widgets added"
        let body =
            arrived.count == 1
            ? "\(arrived[0].displayName) — enable it in Settings to start it."
            : "\(arrived.map(\.displayName).joined(separator: ", ")) — enable them in Settings."

        present(
            NotchAlert(
                id: "connector-added-\(arrived.map(\.id).sorted().joined(separator: "-"))",
                seq: 0, integrationId: nil,
                provider: arrived.count == 1
                    ? (arrived[0].manifest?.appId ?? AppCatalog.customId) : AppCatalog.customId,
                connectionLabel: "", typeId: "plugin_added", severity: .info,
                title: title, body: body, amount: nil, currency: nil, url: nil,
                occurredAt: ISO8601.string(from: Date()),
                createdAt: ISO8601.string(from: Date()), read: false, alert: true))
    }

    /// Re-reads an app from disk and refetches it now.
    ///
    /// Two separate things, both of which "Reload" is expected to do: pick up
    /// a rebuild the user has just made in their project, and ask for the
    /// numbers again without waiting out the refresh interval.
    func reloadConnector(_ app: LoadedConnector) {
        connectors.reload()
        publishAppOverrides()
        // Marked loading so `refreshConnectors` treats them as awaiting and
        // runs the app regardless of when it last ran.
        for widget in widgetsFor(appId: app.id) { states[widget.id] = .loading }
        notch.update(states: states)

        Task {
            await connectorSchedule.invalidate(id: app.id)
            await refreshConnectors()
        }
    }

    /// Removes an app, its credentials, its approval and every widget of its.
    ///
    /// All four, because any one left behind is a loose end the user cannot
    /// see: an orphaned widget shows "App not installed" for ever, a stale
    /// approval would silently re-bless a different app installed under the
    /// same id later, and a credential nobody can reach from the UI is a
    /// secret with no owner.
    /// Returns what went wrong, if anything, so the pane can say it where it
    /// says a failed load — the same place, because they are the same kind of
    /// problem to the person reading it.
    @discardableResult
    func removeConnector(_ app: LoadedConnector) -> String? {
        // Widgets first, while the manifest is still readable — the metric ids
        // it declares are what identifies them.
        for widget in widgetsFor(appId: app.id) { layoutModel.remove(widget.id) }

        if let manifest = app.manifest {
            for field in manifest.auth {
                try? secrets.set(nil, for: .plugin(app.id, field.key))
            }
        }

        var failure: String?
        do {
            try ConnectorImport.remove(id: app.id)
        } catch {
            // Reported, and the rest still runs: an app whose folder could not
            // be deleted must not keep its approval and its widgets as well.
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        updateSettings { settings in
            settings.approvedConnectors.removeValue(forKey: app.id)
        }
        connectors.reload()
        publishAppOverrides()
        Task { await connectorSchedule.invalidate(id: app.id) }
        return failure
    }

    /// How many widgets one custom app answers. Shown before removing it.
    func widgetCount(forConnector id: String) -> Int { widgetsFor(appId: id).count }

    /// Every widget answered by one custom app.
    private func widgetsFor(appId: String) -> [NotchWidget] {
        layoutModel.layout.widgets.filter {
            $0.kind == .customMetric
                && CustomMetricRef(packed: $0.customMetricId ?? "").appId == appId
        }
    }

    /// Enables or disables a custom app.
    ///
    /// Approval pins the app's *grants* — the hosts it may reach, the host
    /// credentials it may be handed, the secrets it may ask for — rather than
    /// a digest of its bytes. `ConnectorGrants` has the reasoning; the short
    /// version is that a digest made every cosmetic edit a consent prompt
    /// nobody could answer.
    /// Rewrites approvals stored as a content digest into grants.
    ///
    /// Silent, and deliberately so. These apps were enabled by the user; the
    /// older build simply recorded the decision in a form that cannot be
    /// compared against anything. Asking again at upgrade would have shown a
    /// consent prompt on first launch for every installed app, which is how a
    /// prompt becomes something you dismiss rather than read.
    ///
    /// One write, not a fallback: until the grants are stored there is no
    /// baseline for the *next* change to be measured against.
    private func migrateConnectorApprovals() {
        let upgrades = connectors.legacyApprovals
        guard !upgrades.isEmpty else { return }
        updateSettings { settings in
            for (id, grants) in upgrades { settings.approvedConnectors[id] = grants }
        }
    }

    /// Shows a custom app's log file in Finder.
    ///
    /// The one thing a connector author needs that the tile cannot give
    /// them: what the connector actually asked for and what came back. The
    /// path is also in the docs, so an agent debugging somebody's app can
    /// read it without being told where it is.
    func revealConnectorLog(_ connector: LoadedConnector) {
        let url = ConnectorLog.url(for: connector.id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func setConnectorApproved(_ connector: LoadedConnector, _ approved: Bool) {
        let grants = connector.grants.canonical
        updateSettings { settings in
            if approved {
                settings.approvedConnectors[connector.id] = grants
            } else {
                settings.approvedConnectors.removeValue(forKey: connector.id)
            }
        }
    }

    /// Reads one of a custom app's credentials back for the form.
    ///
    /// The value, not a mask. The field is a `SecureField`, so it is not shown
    /// in the clear — but a form that cannot load what is already stored makes
    /// changing one field of three mean retyping all of them.
    func connectorCredential(_ connectorId: String, _ key: String) -> String {
        (try? secrets.string(for: .plugin(connectorId, key))) ?? ""
    }

    /// Stores one credential, or clears it when emptied.
    ///
    /// Keyed exactly as the MCP server writes it, which is what lets an agent
    /// set a key and the user correct it in Settings without either of them
    /// knowing about the other.
    func setConnectorCredential(_ connectorId: String, _ key: String, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // nil clears the entry; the protocol takes an optional for exactly
        // this, so emptying a field removes the secret rather than storing "".
        try? secrets.set(trimmed.isEmpty ? nil : trimmed, for: .plugin(connectorId, key))
    }

    /// Runs the app's own `verify`, which is how a credential is checked.
    ///
    /// Locally, against the app's own API — there is no server round trip and
    /// no browser. Returns what to show beside the form: the account label on
    /// success, or the reason it failed.
    func verifyConnector(_ app: LoadedConnector) async -> (ok: Bool, message: String) {
        do {
            let runner = try ConnectorRunner(secrets: secrets)
            let result = try await runner.verify(app)
            if result.ok {
                let label = result.result?.accountLabel
                return (true, label.map { "Connected as \($0)." } ?? "Credentials work.")
            }
            return (false, result.message ?? "The app refused those credentials.")
        } catch {
            return (false, Self.pluginFailure(error))
        }
    }

    /// Installs a custom app from a folder the user picked.
    ///
    /// Returns the failure rather than presenting it, so the pane can put the
    /// message beside the button that caused it. A modal here would be the
    /// wrong shape: most failures are "that folder is a project, not a
    /// build", which the user fixes and retries immediately.
    func loadConnector(from url: URL, replacing: Bool = false) -> String? {
        do {
            let manifest = try ConnectorImport.install(from: url, replacing: replacing)
            connectors.reload()
            Task {
                await LogFile.shared.write(
                    "app", "loaded custom app \(manifest.id) v\(manifest.displayVersion)")
            }
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Enables or disables a local metric.
    ///
    /// Approval pins the digest rather than the id, so this records *what*
    /// was approved — see `PluginDigest`. Re-enabling a metric whose bytes
    /// changed is a new decision and stores the new digest.
    func setPluginApproved(_ plugin: LoadedPlugin, _ approved: Bool) {
        let digest = plugin.contentHash
        updateSettings { settings in
            if approved {
                settings.approvedPlugins[plugin.id] = digest
            } else {
                settings.approvedPlugins.removeValue(forKey: plugin.id)
            }
        }
        guard approved else { return }
        placeWidgetIfMissing(for: plugin)
    }

    /// Puts a tile on the grid the first time a metric is enabled.
    ///
    /// Enabling a metric and then having to go and add a widget for it is two
    /// steps where the user meant one — they have already said they want to
    /// see this number. Only when there is no tile for it already, so
    /// toggling off and on again does not accumulate duplicates.
    private func placeWidgetIfMissing(for plugin: LoadedPlugin) {
        let existing = layoutModel.layout.widgets.contains {
            $0.kind == .customMetric && $0.customMetricId == plugin.id
        }
        guard !existing, let manifest = plugin.manifest else { return }

        let widget = NotchWidget(
            kind: .customMetric,
            appId: manifest.appId ?? AppCatalog.customId,
            customMetricId: plugin.id,
            title: manifest.shortLabel,
            size: manifest.supportsSeries ? .wide : .square,
            range: .month,
            chart: manifest.supportsSeries ? .sparkline : .none)
        layoutModel.add(widget)
        // Straight away, rather than on the next poll: the user just asked
        // for this and a tile that sits empty for five minutes reads as
        // broken.
        Task {
            await refreshPlugins()
            await refreshConnectors()
        }
    }

    func updateSettings(_ mutate: @escaping @Sendable (inout AppSettings) -> Void) {
        Task {
            await settingsStore.update(mutate)
            settings = await settingsStore.current
            plugins.setApproved(settings.approvedPlugins)
            connectors.setApproved(settings.approvedConnectors)
            publishAppOverrides()
            notch.apply(settings: settings)
            updates.automatic = settings.checkForUpdatesAutomatically
        }
    }

    // MARK: - Layout persistence

    /// The three tiles the app used to seed itself with.
    ///
    /// Everyone who ran a build before the starter layout was removed has
    /// these in their `layout.json`, pointing at a Stripe account they never
    /// connected. They can never render anything, so they are dropped on load
    /// rather than left for each person to delete three times.
    nonisolated private static let seededPlaceholderIDs: Set<String> = [
        "starter-revenue", "starter-mrr", "starter-subs",
    ]

    nonisolated private static func loadLayout() -> NotchLayout {
        guard let data = try? Data(contentsOf: AppPaths.layout),
              var layout = try? JSONDecoder().decode(NotchLayout.self, from: data)
        else { return NotchLayout() }

        // Keyed on the exact seeded ids, not on "has no integration": a widget
        // whose connection was disconnected also has none, and that one is
        // meant to survive as a reconnect prompt.
        let kept = layout.widgets.filter { !seededPlaceholderIDs.contains($0.id) }
        if kept.count != layout.widgets.count {
            // Reset the coordinates before repacking. `repack` leaves a widget
            // where it is when it still fits, so removing the tiles that
            // occupied the top rows would otherwise leave the survivors
            // stranded with an empty band above them.
            layout.widgets = kept.map { widget in
                var moved = widget
                moved.col = 0
                moved.row = 0
                return moved
            }
            layout = GridPacker.reflow(layout)
            saveLayout(layout)
        }
        return layout
    }

    /// `nonisolated` because `NotchLayoutModel`'s persist closure is
    /// `@Sendable` and fires from whichever context committed the drag. The
    /// work is a JSON encode and an atomic write — nothing that wants the main
    /// actor, and holding it here would block the drag's final frame.
    nonisolated private static func saveLayout(_ layout: NotchLayout) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        try? FileManager.default.createDirectory(
            at: AppPaths.support, withIntermediateDirectories: true)
        // Atomic: a crash mid-write would otherwise leave a truncated file that
        // fails to decode, and the user's arrangement is gone.
        try? data.write(to: AppPaths.layout, options: .atomic)
    }

    /// What a brand-new install shows.

    /// Widgets from three apps — enough to show what the list view is for.
    ///
    /// All six are present in both modes. `repack` marks the ones that do not
    /// fit the grid as hidden, which is exactly the situation the list solves.
    nonisolated private static func starterLayout() -> [NotchWidget] {
        [
            NotchWidget(
                id: "starter-revenue", kind: .providerMetric, appId: "stripe",
                metric: "revenue", title: "Revenue", size: .square, col: 0, row: 0,
                position: 0, chart: .sparkline),
            NotchWidget(
                id: "starter-mrr", kind: .providerMetric, appId: "stripe", metric: "mrr",
                title: "MRR", size: .square, col: 2, row: 0, position: 1, chart: .none),
            // A list, so the demo shows both kinds of tile.
            NotchWidget(
                id: "starter-payments", kind: .providerMetric, appId: "stripe",
                metric: "recent_payments", title: "Payments", size: .square,
                col: 4, row: 0, position: 2, chart: .none),
            NotchWidget(
                id: "starter-subs", kind: .providerMetric, appId: "stripe",
                metric: "active_subscribers", title: "Subscribers", size: .square,
                col: 0, row: 0, position: 3, chart: .bars),
            NotchWidget(
                id: "demo-ga-users", kind: .providerMetric, appId: "google-analytics",
                metric: "active_subscribers", title: "Active users", size: .wide,
                col: 0, row: 0, position: 3, chart: .sparkline),
            NotchWidget(
                id: "demo-ga-new", kind: .providerMetric, appId: "google-analytics",
                metric: "new_subscribers", title: "New users", size: .wide,
                col: 0, row: 0, position: 4, chart: .none),
            // The other list shape: rows with an outcome rather than an
            // amount, which is the only tile with icons down its left.
            NotchWidget(
                id: "demo-ci", kind: .providerMetric, appId: "github",
                metric: "ci_runs", title: "CI", size: .square,
                col: 0, row: 1, position: 5, chart: .none,
                params: ["repository": "haxzie/notch-metrics", "branch": "main"]),
            NotchWidget(
                id: "demo-stars", kind: .customMetric, appId: "github",
                customMetricId: "github-stars", title: "Stars", size: .small,
                col: 0, row: 0, position: 5, chart: .none),
        ]
    }

    /// One category's worth of tiles, filling the grid exactly.
    ///
    /// Every preset is four tiles on the 6x2 grid — two squares and two
    /// halves, or three squares — because a preset that leaves a hole shows
    /// the empty-grid hint in the corner of a marketing shot. Coordinates are
    /// written out rather than left to `reflow`, so what the screenshot
    /// catches does not depend on the packer's first-fit order.
    nonisolated private static func categoryLayout(_ preset: DemoPreset) -> [NotchWidget] {
        switch preset {
        case .starter:
            return starterLayout()

        case .revenue:
            // Revenue leads rather than MRR, because revenue is the only one
            // of the two Stripe reports as a series — MRR and the subscriber
            // count are snapshots of the book right now, and a chart under
            // either would be a chart the shipped app cannot draw.
            return [
                NotchWidget(
                    id: "cat-revenue", appId: "stripe", metric: "revenue", title: "Revenue",
                    size: .square, col: 0, row: 0, position: 0, chart: .sparkline),
                NotchWidget(
                    id: "cat-payments", appId: "stripe", metric: "recent_payments",
                    title: "Payments", size: .square, col: 2, row: 0, position: 1,
                    chart: .none),
                NotchWidget(
                    id: "cat-mrr", appId: "stripe", metric: "mrr", title: "MRR",
                    size: .wide, col: 4, row: 0, position: 2, chart: .none),
                NotchWidget(
                    id: "cat-subs", appId: "stripe", metric: "active_subscribers",
                    title: "Subscribers", size: .wide, col: 4, row: 1, position: 3,
                    chart: .none),
            ]

        case .analytics:
            // Three apps rather than one: the point of the analytics shot is
            // that the numbers do not have to come from the same place.
            return [
                NotchWidget(
                    id: "cat-users", appId: "google-analytics", metric: "active_users",
                    title: "Active users", size: .square, col: 0, row: 0, position: 0,
                    chart: .sparkline),
                NotchWidget(
                    id: "cat-pageviews", appId: "posthog", metric: "pageviews",
                    title: "Pageviews", size: .square, col: 2, row: 0, position: 1,
                    chart: .bars),
                NotchWidget(
                    id: "cat-bounce", appId: "plausible", metric: "bounce_rate",
                    title: "Bounce rate", size: .square, col: 4, row: 0, position: 2,
                    chart: .gauge),
            ]

        case .marketing:
            return [
                NotchWidget(
                    id: "cat-clicks", appId: "google-search-console", metric: "clicks",
                    title: "Clicks", size: .square, col: 0, row: 0, position: 0,
                    chart: .sparkline),
                NotchWidget(
                    id: "cat-impressions", appId: "google-search-console",
                    metric: "impressions", title: "Impressions", size: .square,
                    col: 2, row: 0, position: 1, chart: .bars),
                NotchWidget(
                    id: "cat-ctr", appId: "google-search-console", metric: "ctr",
                    title: "CTR", size: .wide, col: 4, row: 0, position: 2, chart: .none),
                NotchWidget(
                    id: "cat-position", appId: "google-search-console",
                    metric: "average_position", title: "Position", size: .wide,
                    col: 4, row: 1, position: 3, chart: .none),
            ]

        case .developer:
            // Every GitHub scalar is a snapshot — the API reports what is
            // true now and offers no history — so four of these are a figure
            // and nothing else, and the run feed carries the tile.
            return [
                NotchWidget(
                    id: "cat-ci", appId: "github", metric: "ci_runs", title: "CI",
                    size: .square, col: 0, row: 0, position: 0, chart: .none,
                    params: ["repository": "haxzie/notch-metrics", "branch": "main"]),
                NotchWidget(
                    id: "cat-stars", appId: "github", metric: "stars", title: "Stars",
                    size: .wide, col: 2, row: 0, position: 1, chart: .none,
                    params: ["repository": "haxzie/notch-metrics"]),
                NotchWidget(
                    id: "cat-issues", appId: "github", metric: "open_issues",
                    title: "Open issues", size: .wide, col: 4, row: 0, position: 2,
                    chart: .none, params: ["repository": "haxzie/notch-metrics"]),
                NotchWidget(
                    id: "cat-forks", appId: "github", metric: "forks", title: "Forks",
                    size: .wide, col: 2, row: 1, position: 3, chart: .none,
                    params: ["repository": "haxzie/notch-metrics"]),
                NotchWidget(
                    id: "cat-prs", appId: "github", metric: "open_pull_requests",
                    title: "Open PRs", size: .wide, col: 4, row: 1, position: 4,
                    chart: .none, params: ["repository": "haxzie/notch-metrics"]),
            ]

        case .ai:
            return [
                NotchWidget(
                    id: "cat-spend", appId: "openai", metric: "api_spend",
                    title: "API spend", size: .square, col: 0, row: 0, position: 0,
                    chart: .sparkline),
                NotchWidget(
                    id: "cat-tokens", appId: "anthropic", metric: "tokens",
                    title: "Tokens", size: .square, col: 2, row: 0, position: 1,
                    chart: .bars),
                NotchWidget(
                    id: "cat-requests", appId: "openai", metric: "api_requests",
                    title: "Requests", size: .wide, col: 4, row: 0, position: 2,
                    chart: .none),
                NotchWidget(
                    id: "cat-claude-spend", appId: "anthropic", metric: "api_spend",
                    title: "API spend", size: .wide, col: 4, row: 1, position: 3,
                    chart: .none),
            ]
        }
    }

    nonisolated private static func demoLayout(_ preset: DemoPreset) -> NotchLayout {
        NotchLayout(rows: 2, widgets: categoryLayout(preset))
    }

    /// Plausible numbers for screenshots and design work.
    ///
    /// Behind an environment variable and never reachable from the shipped UI:
    /// a dashboard that invents figures when it cannot reach the server is a
    /// dashboard nobody can trust.
    ///
    /// One company across every preset — roughly $12.8k a month from 1,842
    /// subscribers — so a launch gallery does not show five unrelated
    /// businesses one slide apart.
    /// Which demo metrics carry a time window, and so a "· 30d" in the tile's
    /// title.
    ///
    /// Hand-written here rather than derived, because the real answer lives
    /// in the server's catalogue and demo mode is the one mode that must not
    /// ask it. Each is a `series` metric in `packages/integrations`; the
    /// snapshots beside them — MRR, subscribers, stargazers, open issues —
    /// are deliberately absent, and a list metric has no window either.
    nonisolated static let demoTimeWindowedMetrics: Set<String> = [
        "stripe/revenue",
        "google-analytics/active_users",
        "google-analytics/active_subscribers",
        "google-analytics/new_subscribers",
        "posthog/pageviews",
        "plausible/bounce_rate",
        "google-search-console/clicks",
        "google-search-console/impressions",
        "google-search-console/ctr",
        "google-search-console/average_position",
        "openai/api_spend",
        "openai/api_requests",
        "anthropic/tokens",
        "anthropic/api_spend",
    ]

    /// `previous` is the window before this one, not the first bucket of this
    /// one — the two are different numbers and only the first produces an
    /// honest delta. Defaulted to the first bucket, which is close enough for
    /// a flat trend and is what the starter layout has always done.
    nonisolated private static func demoSeries(
        _ metric: String, _ value: Double, unit: MetricUnit, currency: String? = nil,
        trend: [Double] = [], previous: Double? = nil, format: MetricFormat? = nil
    ) -> MetricSeries {
        let now = Date()
        let points = trend.enumerated().map { index, v in
            MetricPoint(
                t: ISO8601.string(
                    from: now.addingTimeInterval(-Double(trend.count - index) * 86_400)),
                v: v)
        }
        let before = previous ?? trend.first
        return MetricSeries(
            integrationId: "int_demo", metric: metric, unit: unit, currency: currency,
            value: value, previousValue: before,
            // Nil, not zero, where there is nothing to compare against. A
            // metric with no previous window has no delta, and a constructed
            // one reads as "+0.0%" — which claims the number has not moved.
            delta: before.map {
                MetricDelta(absolute: value - $0, percent: ((value - $0) / max(1, $0)) * 100)
            },
            points: points, granularity: .day, range: .month,
            from: "", to: "", format: format,
            generatedAt: ISO8601.string(from: now), stale: false)
    }

    /// The payment rows, shared by the starter and revenue presets.
    nonisolated private static func demoPayments() -> MetricSeries {
        MetricSeries(
            integrationId: "int_demo", metric: "recent_payments", unit: .currency,
            currency: "USD", value: 41_700, points: [], granularity: .day, range: .month,
            generatedAt: ISO8601.string(from: Date()),
            items: [
                MetricListItem(
                    id: "1", t: ISO8601.string(from: Date().addingTimeInterval(-420)),
                    label: "Ada Lovelace", detail: "Pro · yearly", amount: 9_900,
                    currency: "USD", status: "succeeded"),
                MetricListItem(
                    id: "2", t: ISO8601.string(from: Date().addingTimeInterval(-5_400)),
                    label: "grace@example.com", detail: "Starter", amount: 1_900,
                    currency: "USD", status: "succeeded"),
                MetricListItem(
                    id: "3", t: ISO8601.string(from: Date().addingTimeInterval(-19_800)),
                    label: "Linus T.", detail: "Team", amount: 29_900, currency: "USD",
                    status: "succeeded"),
                MetricListItem(
                    id: "4", t: ISO8601.string(from: Date().addingTimeInterval(-93_600)),
                    label: "Margaret H.", detail: "Pro", amount: 4_900, currency: "USD",
                    status: "refunded"),
                MetricListItem(
                    id: "5", t: ISO8601.string(from: Date().addingTimeInterval(-180_000)),
                    label: "ken@example.com", detail: "Starter", amount: 1_900,
                    currency: "USD", status: "succeeded"),
            ])
    }

    /// The CI rows, shared by the starter and developer presets.
    nonisolated private static func demoRuns() -> MetricSeries {
        MetricSeries(
            integrationId: "int_demo", metric: "ci_runs", unit: .count, currency: nil,
            value: 5, points: [], granularity: .day, range: .month,
            generatedAt: ISO8601.string(from: Date()),
            items: [
                MetricListItem(
                    id: "101", t: ISO8601.string(from: Date().addingTimeInterval(-240)),
                    label: "CI", detail: "Tell people when something happened",
                    status: "success", state: .succeeded),
                MetricListItem(
                    id: "102", t: ISO8601.string(from: Date().addingTimeInterval(-260)),
                    label: "Deploy the API", detail: "Tell people when something happened",
                    status: "failure", state: .failed),
                MetricListItem(
                    id: "103", t: ISO8601.string(from: Date().addingTimeInterval(-280)),
                    label: "Deploy the website", detail: "Tell people when something happened",
                    status: "in_progress", state: .running),
                MetricListItem(
                    id: "104", t: ISO8601.string(from: Date().addingTimeInterval(-9_000)),
                    label: "Version and publish", detail: "Cut 0.2.1",
                    status: "cancelled", state: .neutral),
                MetricListItem(
                    id: "105", t: ISO8601.string(from: Date().addingTimeInterval(-20_000)),
                    label: "CI", detail: "Step the notch aside",
                    status: "success", state: .succeeded),
            ])
    }

    nonisolated private static func demoStates(
        for layout: NotchLayout, preset: DemoPreset
    ) -> [String: TileState] {
        // Bound to a local so the tables below read as data rather than as
        // six lines of labelled arguments each. Spelled out as a closure
        // rather than a reference to `demoSeries`, because a function
        // reference drops both the labels and the defaults.
        let series = {
            (
                metric: String, value: Double, unit: MetricUnit, currency: String?,
                trend: [Double], previous: Double?
            ) in
            demoSeries(
                metric, value, unit: unit, currency: currency, trend: trend, previous: previous)
        }
        var demo: [String: MetricSeries] = [:]

        switch preset {
        case .starter:
            demo = [
                "starter-revenue": series(
                    "revenue", 5_567_800, .currency, "USD",
                    [4_120_000, 4_480_000, 4_310_000, 4_950_000, 5_210_000, 5_567_800], nil),
                "starter-mrr": series(
                    "mrr", 1_284_500, .currency, "USD",
                    [1_190_000, 1_236_000, 1_284_500], nil),
                "starter-subs": series(
                    "active_subscribers", 3_456, .count, nil,
                    [2_980, 3_110, 3_240, 3_300, 3_398, 3_456], nil),
                "starter-payments": demoPayments(),
                "demo-ga-users": series(
                    "active_subscribers", 18_402, .count, nil,
                    [14_900, 15_800, 16_100, 17_400, 17_900, 18_402], nil),
                "demo-ga-new": series(
                    "new_subscribers", 2_117, .count, nil,
                    [2_400, 2_310, 2_290, 2_180, 2_140, 2_117], nil),
                "demo-ci": demoRuns(),
                "demo-stars": series(
                    "stars", 6_786, .count, nil, [6_310, 6_420, 6_560, 6_700, 6_786], nil),
            ]

        case .revenue:
            demo = [
                // Daily takings, which swing — so the delta is against the
                // previous window's total rather than against the first of
                // eight days, which is a different number entirely.
                "cat-revenue": series(
                    "revenue", 4_821_000, .currency, "USD",
                    [
                        412_000, 586_000, 497_000, 638_000, 521_000, 702_000, 594_000,
                        871_000,
                    ], 4_063_000),
                "cat-payments": demoPayments(),
                // Snapshots. No window, no previous, no delta.
                "cat-mrr": demoSeries("mrr", 1_284_500, unit: .currency, currency: "USD"),
                "cat-subs": demoSeries("active_subscribers", 1_842, unit: .count),
            ]

        case .analytics:
            demo = [
                "cat-users": series(
                    "active_users", 18_402, .count, nil,
                    [14_900, 15_600, 15_200, 16_400, 16_100, 17_300, 17_800, 18_402], nil),
                "cat-pageviews": series(
                    "pageviews", 96_480, .count, nil,
                    [11_200, 16_400, 12_900, 18_100, 13_600, 19_480], 82_300),
                // A ratio, so the arc has a ceiling to fill against. Down is
                // the good direction here, which the falling trend says.
                "cat-bounce": series(
                    "bounce_rate", 0.382, .ratio, nil, [0.441, 0.428, 0.409, 0.382], nil),
            ]

        case .marketing:
            demo = [
                "cat-clicks": series(
                    "clicks", 24_918, .count, nil,
                    [17_400, 18_200, 17_900, 19_600, 21_300, 20_800, 23_100, 24_918], 20_600),
                "cat-impressions": series(
                    "impressions", 612_400, .count, nil,
                    [68_000, 112_000, 76_000, 131_000, 94_000, 131_400], 524_800),
                "cat-ctr": series("ctr", 0.0407, .ratio, nil, [0.0388, 0.0394, 0.0407], nil),
                // A rank, so the tenths matter. Search Console's adapter
                // sends this format with the series rather than leaving the
                // tile to round 8.4 down to page-one-or-not.
                // No trend, so no delta. A rank improving is a number
                // falling, and nothing on the wire says which direction is
                // the good one — so a shot with a trend on this tile sells
                // the product with a red minus against its best news.
                "cat-position": demoSeries(
                    "average_position", 8.4, unit: .count,
                    format: MetricFormat(decimals: 1, compact: false)),
            ]

        case .developer:
            demo = [
                "cat-ci": demoRuns(),
                "cat-stars": demoSeries("stars", 6_786, unit: .count),
                "cat-issues": demoSeries("open_issues", 23, unit: .count),
                "cat-forks": demoSeries("forks", 412, unit: .count),
                "cat-prs": demoSeries("open_pull_requests", 7, unit: .count),
            ]

        case .ai:
            demo = [
                "cat-spend": series(
                    "api_spend", 42_860, .currency, "USD",
                    [28_400, 32_100, 30_600, 35_900, 34_200, 38_700, 40_100, 42_860], nil),
                "cat-tokens": series(
                    "tokens", 18_400_000, .count, nil,
                    [1_820_000, 3_640_000, 2_410_000, 4_180_000, 2_960_000, 3_390_000],
                    14_900_000),
                "cat-requests": series(
                    "api_requests", 142_800, .count, nil, [104_000, 121_000, 142_800], nil),
                "cat-claude-spend": series(
                    "api_spend", 21_240, .currency, "USD", [16_800, 19_300, 21_240], nil),
            ]
        }

        return Dictionary(
            uniqueKeysWithValues: layout.widgets.map { widget in
                (widget.id, demo[widget.id].map(TileState.value) ?? .loading)
            })
    }

    nonisolated private static func placeholderStates(
        for layout: NotchLayout, signedIn: Bool
    ) -> [String: TileState] {
        Dictionary(uniqueKeysWithValues: layout.widgets.map { widget in
            guard signedIn else { return (widget.id, TileState.needsSetup("Sign in")) }
            // Signed in, so this tile is about to be fetched and the honest
            // answer is "not yet". It used to say "Connect <app>" for the
            // whole of the first fetch, which told somebody with four
            // working connections to go and make them again — and was the
            // reason a slow first load read as a broken one. `refresh()`
            // corrects the tiles that genuinely have no account, by name,
            // before the request leaves.
            return (widget.id, TileState.loading)
        })
    }
}

// MARK: - Notifications

extension AppEnvironment {
    /// Starts the notification feed and the energy gate that paces it.
    ///
    /// The gate also paces the metrics refresh, which is why it is started here
    /// rather than inside the feed: the notification work is what forced the
    /// abstraction to exist, and the existing loop gets it for free.
    func startAlerts() {
        // Demo mode shows the sample feed and starts no network work, so a
        // screenshot of the pane is the same every run.
        if Self.isDemo {
            alertSnapshot = AlertSnapshot(
                alerts: AlertSample.feed, connections: AlertSample.connections,
                unread: AlertSample.feed.filter { !$0.read }.count,
                cursor: 412, hasMore: true)
            notch.unreadAlertCount = alertSnapshot.unread
            alertDefinitions = AlertSample.definitions
            providerByIntegration = [
                "int_stripe": "stripe", "int_github": "github", "int_polar": "polar",
            ]
            alertSettings = AlertSample.settings
            return
        }
        guard isSignedIn else { return }

        gate.onChange = { [weak self] conditions in
            guard let self else { return }
            let cadence = EnergyPolicy.alertCadence(conditions)
            Task { await self.alertFeed?.setCadence(cadence) }
        }
        gate.start()

        let feed = PollingAlertFeed(api: api)
        alertFeed = feed

        alertPump?.cancel()
        alertPump = Task { [weak self] in
            guard let self else { return }
            await feed.setCadence(EnergyPolicy.alertCadence(self.gate.conditions))
            await feed.start(from: await self.alerts.cursor)
            for await event in feed.events {
                await self.handle(event)
            }
        }

        Task { await self.loadAlertSettings() }
    }

    func stopAlerts() {
        alertPump?.cancel()
        alertPump = nil
        gate.stop()
        let feed = alertFeed
        alertFeed = nil
        Task { await feed?.stop() }
    }

    private func handle(_ event: AlertFeedEvent) async {
        switch event {
        case .page(let page):
            let outcome = await alerts.merge(page)
            apply(outcome.snapshot)

            // One banner per arrival, or one summary for a burst. The decision
            // is the inbox's, because it is a pure function worth testing.
            if outcome.collapsed {
                presentSummaryBanner(count: page.unread)
            } else {
                for alert in outcome.arrived { present(alert) }
            }

        case .cadence(let floor):
            // The server's floor, re-applied through the policy so the power
            // state still gets to ask for something slower.
            let wanted = EnergyPolicy.alertCadence(gate.conditions, serverFloor: floor)
            await alertFeed?.setCadence(wanted)

        case .degraded(let message):
            alertsProblem = message

        case .unauthorized:
            // `AuthStore` owns the escalation; this just stops asking.
            stopAlerts()
        }
    }

    private func apply(_ snapshot: AlertSnapshot) {
        alertSnapshot = snapshot
        alertsProblem = nil
        // Straight through to the notch, so the bell's badge and the collapsed
        // dot are current now rather than on the next refresh.
        notch.unreadAlertCount = snapshot.unread
    }

    /// Drops one notification out of the notch.
    private func present(_ alert: NotchAlert) {
        guard settings.alertBannersEnabled, settings.alertBannerSeconds > 0 else { return }
        // Sound first, so it lands with the start of the drop rather than a
        // frame after it.
        AlertSoundPlayer.play(settings.alertSound)
        notch.showBanner(alert, seconds: Double(settings.alertBannerSeconds))
    }

    private func presentSummaryBanner(count: Int) {
        guard settings.alertBannersEnabled, settings.alertBannerSeconds > 0, count > 0 else {
            return
        }
        // Once for the whole batch, which is the entire point of collapsing it.
        AlertSoundPlayer.play(settings.alertSound)
        // A synthetic row, so the burst path reuses the same banner view rather
        // than needing a second one.
        let summary = NotchAlert(
            id: "summary", seq: 0, integrationId: nil, provider: "unknown",
            connectionLabel: "", typeId: "summary", severity: .info,
            title: "\(count) notifications while you were away",
            body: "Open the notch to catch up.", amount: nil, currency: nil, url: nil,
            occurredAt: ISO8601.string(from: Date()),
            createdAt: ISO8601.string(from: Date()), read: false, alert: true)
        notch.showBanner(summary, seconds: Double(settings.alertBannerSeconds))
    }

    /// The pane's pull-to-refresh and its first load.
    func refreshAlerts() async {
        guard !alertsLoading else { return }
        alertsLoading = true
        defer { alertsLoading = false }
        await alertFeed?.pokeNow()
    }

    /// "Load earlier" — a history page, which never banners.
    func loadEarlierAlerts() async {
        guard let oldest = alertSnapshot.alerts.map(\.seq).min(), alertSnapshot.hasMore else {
            return
        }
        do {
            let page = try await api.alerts(before: oldest)
            apply(await alerts.append(page))
        } catch {
            alertsProblem = describeAlertError(error)
        }
    }

    func markAlertsRead(ids: [String]) async {
        await alerts.markRead(ids)
        apply(await alerts.snapshot())
        // Server-side read state, so a second Mac agrees. Failing is not worth
        // surfacing: the local state is already right and the next feed page
        // reconciles it.
        _ = try? await api.markAlertsRead(ids: ids)
    }

    func markAlertsRead(in scope: AlertScope) async {
        // Collected before the local mark, which is what sets `read` on the
        // rows: after it there is nothing left for the server to be told about.
        // Scoped to the connection too — unscoping it here marks a user's whole
        // inbox read on every other device because they cleared one connection.
        var pending: [String] = []
        if case .connection(let integrationId) = scope {
            pending = alertSnapshot.alerts
                .filter { $0.integrationId == integrationId && !$0.read }
                .map(\.id)
        }

        await alerts.markAllRead(in: scope)
        let snapshot = await alerts.snapshot()
        apply(snapshot)

        if case .all = scope {
            _ = try? await api.markAlertsRead(upToSeq: snapshot.cursor)
        } else if !pending.isEmpty {
            _ = try? await api.markAlertsRead(ids: pending)
        }
    }

    // MARK: Settings

    func loadAlertSettings() async {
        do {
            alertSettings = try await api.alertSettings()
        } catch {
            alertsProblem = describeAlertError(error)
        }
    }

    func alertSubscription(for integrationId: String, typeId: String) -> AlertSubscription? {
        alertSettings?.subscriptions.first {
            $0.integrationId == integrationId && $0.typeId == typeId
        }
    }

    func alertDefinitions(forIntegration integrationId: String) -> [AlertDefinition] {
        guard let provider = providerByIntegration[integrationId] else { return [] }
        return alertDefinitions[provider] ?? []
    }

    /// Flips one toggle, optimistically.
    ///
    /// The local copy moves first so the switch is instant, and a failed write
    /// rolls it back — the server is authoritative here, unlike the layout.
    func setAlertEnabled(_ enabled: Bool, for integrationId: String, typeId: String) async {
        guard var settings = alertSettings else { return }
        guard
            let index = settings.subscriptions.firstIndex(where: {
                $0.integrationId == integrationId && $0.typeId == typeId
            })
        else { return }

        let previous = settings.subscriptions[index].enabled
        settings.subscriptions[index].enabled = enabled
        alertSettings = settings

        do {
            alertSettings = try await api.updateAlertSettings(settings)
        } catch {
            settings.subscriptions[index].enabled = previous
            alertSettings = settings
            alertsProblem = "Couldn't save that. Try again."
        }
    }

    /// "Stop telling me this" from a row or a banner.
    func muteAlertType(_ alert: NotchAlert) async {
        guard let integrationId = alert.integrationId else { return }
        await setAlertEnabled(false, for: integrationId, typeId: alert.typeId)
    }

    func updateAlertSettings(_ next: AlertSettings) async {
        let previous = alertSettings
        alertSettings = next
        do {
            alertSettings = try await api.updateAlertSettings(next)
        } catch {
            alertSettings = previous
            alertsProblem = "Couldn't save that. Try again."
        }
    }

    /// Records which provider each connection belongs to, and what each
    /// provider can notify about.
    ///
    /// Called from the catalogue load, so the toggles render from the server
    /// rather than from anything compiled into the app.
    func adoptAlertCatalogue(_ entries: [ConnectorEntry]) {
        var definitions: [String: [AlertDefinition]] = [:]
        var byIntegration: [String: String] = [:]
        for entry in entries {
            if let notifications = entry.notifications, !notifications.isEmpty {
                definitions[entry.id] = notifications
            }
            for connection in entry.connections {
                byIntegration[connection.id] = entry.id
            }
        }
        alertDefinitions = definitions
        providerByIntegration = byIntegration
    }

    private func describeAlertError(_ error: any Error) -> String {
        guard let api = error as? APIError else { return "Couldn't load notifications." }
        switch api {
        case .offline: return "You're offline."
        case .unauthorized: return "Sign in to see notifications."
        case .subscriptionRequired: return "Notifications need an active plan."
        case .rateLimited: return "Too many requests. Try again shortly."
        default: return "Couldn't load notifications."
        }
    }
}
