import AppKit
import Foundation
import MetricsAPI
import MetricsCore
import NotchUI
import PluginRuntime
import SwiftUI

/// Everything long-lived, assembled once.
@MainActor
@Observable
final class AppEnvironment {
    let settingsStore: SettingsStore
    let layoutModel: NotchLayoutModel
    let notch: NotchWindowController
    let plugins: PluginRegistry
    let secrets: any SecretStore
    let auth: AuthStore
    let api: APIClient
    let cache: MetricsCache

    private(set) var settings = AppSettings()
    private(set) var states: [String: TileState] = [:]

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

    /// Plausible numbers, no account, no network. For screenshots.
    static var isDemo: Bool {
        ProcessInfo.processInfo.environment["NOTCH_DEBUG_DEMO"] == "1" || isSkeletonDemo
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
        self.settingsStore = SettingsStore()
        self.plugins = PluginRegistry()

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
        plugins.setApproved(settings.approvedPluginIDs)
        plugins.start()

        notch.apply(settings: settings)
        notch.start()

        isSignedIn = await auth.isSignedIn

        // No starter layout. It used to seed three Stripe tiles, which meant
        // a new user's notch was full of an app they had never connected and
        // every tile said "Connect Stripe". The empty state in NotchPanel
        // says what to do instead.
        if Self.isDemo {
            layoutModel.replace(with: Self.demoLayout())
            // Demo mode never refreshes, so the titles would otherwise miss
            // the time window a live notch shows — and a screenshot of the
            // demo is the place that most needs to look like the real thing.
            Task { await refreshMetricWindows() }
        }

        states =
            Self.isSkeletonDemo
            ? Dictionary(
                uniqueKeysWithValues: layoutModel.layout.widgets.map { ($0.id, TileState.loading) })
            : Self.isDemo
                ? Self.demoStates(for: layoutModel.layout)
                : Self.placeholderStates(for: layoutModel.layout, signedIn: isSignedIn)
        notch.update(states: states)

        // Demo mode has numbers without an account, and the sign-in panel
        // would replace the very screenshot it exists to produce. Only the
        // notch's copy of the flag: everything else that reads `isSignedIn`
        // decides whether to hit the network, which demo mode must not.
        if Self.isDemo { notch.isSignedIn = true }

        // Signing in is the moment every catalogue-backed view is wrong: it
        // was rendered against an anonymous catalogue with no accounts in it.
        guard isSignedIn else {
            startRefreshing()
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
        }
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

    /// A widget's settings changed, so its number is answering the old
    /// question.
    ///
    /// Three things, and the order matters. The tile drops to loading
    /// immediately — `refresh()` then fills it from disk if it has a number
    /// for the *new* range and shows a skeleton if it does not, which is
    /// what makes a range switch look like a fetch rather than like nothing
    /// happening. The previous request is cancelled, because its answer is
    /// for a window nobody is looking at any more. And the new one waits a
    /// moment first: arrowing through a picker is four changes in a second,
    /// and each one is a batch for the whole notch.
    func widgetConfigurationChanged(_ widgetId: String) {
        states[widgetId] = .loading
        notch.update(states: states)

        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.refresh()
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
                await self?.refresh()
                // Five minutes. The notch is a glance, not a dashboard, and
                // every poll costs the user's provider rate limit.
                try? await Task.sleep(for: .seconds(300))
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
        for plugin in plugins.plugins {
            if plugin.manifest?.supportsSeries == true { keys.insert("custom/\(plugin.id)") }
        }
        // Not gated on sign-in: the catalogue is readable either way, and a
        // demo or signed-out notch should label its tiles the same as a live one.
        if let catalogue = try? await api.catalogue() {
            for connector in catalogue.allConnectors {
                for metric in connector.metrics
                where metric.supportsSeries || metric.supportsCompare {
                    keys.insert("\(connector.id)/\(metric.id)")
                }
            }
        }
        notch.update(timeWindowedMetrics: keys)
    }

    /// Fetches once, now. Called on launch, on a timer, and after a widget is
    /// added so a new tile fills in rather than sitting on "Loading".
    /// `rebindAllowed` is the recursion stop. A widget whose account 404s is
    /// unbound and re-adopted, which re-enters here — and if the rebound id
    /// 404s too (a connections list that disagrees with the metrics route)
    /// that is an unbounded loop hammering the Worker. One attempt, then the
    /// tile says "Pick a connection" and waits for the next poll.
    func refresh(rebindAllowed: Bool = true) async {
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
        let fetchable = Set(widgets.map(\.id))
        for widget in layoutModel.layout.widgets where !fetchable.contains(widget.id) {
            states[widget.id] = setupState(for: widget)
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
        var next = states
        for widget in widgets where isPending(next[widget.id]) {
            if let cached = await cache.load(
                widgetID: widget.id, range: widget.range, params: widget.params)
            {
                next[widget.id] = .value(cached)
            } else {
                next[widget.id] = .loading
            }
        }
        states = next
        notch.update(states: states)

        // Set when a widget turned out to point at an account that is gone,
        // so adoption gets a chance to rebind it before the next poll.
        var staleBindings = false

        do {
            let results = try await api.batch(widgets.map(MetricQueryRequest.init(widget:)))
            // Superseded while it was in flight. The answer is for the
            // settings the user has already moved on from, and writing it
            // would flash the old window's number over the new one's
            // skeleton a beat before the current request lands.
            guard !Task.isCancelled else { return }
            guard results.count == widgets.count else { return }

            for (widget, result) in zip(widgets, results) {
                switch result {
                case .success(let series):
                    next[widget.id] = .value(series)
                    await cache.store(
                        series, widgetID: widget.id, range: widget.range, params: widget.params)
                case .failure(let failure):
                    // The one line worth having when a widget misbehaves on
                    // one range and not another: which widget, which window,
                    // and the server's own sentence — which now carries the
                    // provider's, rather than a bare status.
                    Task {
                        await LogFile.shared.write(
                            "metric",
                            "\(widget.appId)/\(widget.metric ?? "?") \(widget.range.rawValue)"
                                + " [\(widget.granularity.rawValue)] → \(failure.code.rawValue):"
                                + " \(failure.message)")
                    }
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
                            layoutModel.update(rebound)
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
            states = next
            notch.update(states: states)

            // Once, and only when something actually came loose: `refresh()`
            // is reentered here, and adoption only reports a change when it
            // bound a widget that had nothing.
            if staleBindings, await adoptConnections() { await refresh(rebindAllowed: false) }
        } catch {
            // A cancelled request is not a failure, it is a request nobody
            // wants the answer to any more. URLSession surfaces cancellation
            // as a transport error, which `tileState` reads as "could not
            // reach Notch Metrics" — so without this, changing a setting
            // twice quickly painted a network error across the whole notch.
            if Task.isCancelled { return }

            Task {
                await LogFile.shared.write(
                    "metric", "batch of \(widgets.count) failed: \(error)")
            }
            let state = Self.tileState(for: error)
            for widget in widgets where !isValue(next[widget.id]) {
                next[widget.id] = state
            }
            states = next
            notch.update(states: states)
        }
    }

    /// What a whole-request failure should say on every tile.
    ///
    /// Every one of these used to read "Could not reach Notch Metrics", which
    /// is only true for one of them. A rejected request, an ended trial and a
    /// signed-out app each send somebody to check their wifi, and the real
    /// cause is on screen nowhere.
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

    func updateSettings(_ mutate: @escaping @Sendable (inout AppSettings) -> Void) {
        Task {
            await settingsStore.update(mutate)
            settings = await settingsStore.current
            plugins.setApproved(settings.approvedPluginIDs)
            notch.apply(settings: settings)
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
    nonisolated private static func demoLayout() -> NotchLayout {
        NotchLayout(
            rows: 2,
            widgets: [
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
                NotchWidget(
                    id: "demo-stars", kind: .customMetric, appId: "github",
                    customMetricId: "github-stars", title: "Stars", size: .small,
                    col: 0, row: 0, position: 5, chart: .none),
            ])
    }

    /// Plausible numbers for screenshots and design work.
    ///
    /// Behind an environment variable and never reachable from the shipped UI:
    /// a dashboard that invents figures when it cannot reach the server is a
    /// dashboard nobody can trust.
    nonisolated private static func demoStates(for layout: NotchLayout) -> [String: TileState] {
        func series(_ metric: String, _ value: Double, unit: MetricUnit, currency: String?, trend: [Double])
            -> MetricSeries
        {
            let now = Date()
            let points = trend.enumerated().map { index, v in
                MetricPoint(
                    t: ISO8601.string(
                        from: now.addingTimeInterval(-Double(trend.count - index) * 86_400)),
                    v: v)
            }
            return MetricSeries(
                integrationId: "int_demo", metric: metric, unit: unit, currency: currency,
                value: value, previousValue: trend.first,
                delta: MetricDelta(
                    absolute: value - (trend.first ?? value),
                    percent: ((value - (trend.first ?? value)) / max(1, trend.first ?? 1)) * 100),
                points: points, granularity: .day, range: .month,
                from: "", to: "", format: nil,
                generatedAt: ISO8601.string(from: now), stale: false)
        }

        let demo: [String: MetricSeries] = [
            "starter-revenue": series(
                "revenue", 5_567_800, unit: .currency, currency: "USD",
                trend: [4_120_000, 4_480_000, 4_310_000, 4_950_000, 5_210_000, 5_567_800]),
            "starter-mrr": series(
                "mrr", 1_284_500, unit: .currency, currency: "USD",
                trend: [1_190_000, 1_236_000, 1_284_500]),
            "starter-subs": series(
                "active_subscribers", 3_456, unit: .count, currency: nil,
                trend: [2_980, 3_110, 3_240, 3_300, 3_398, 3_456]),
            "starter-payments": MetricSeries(
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
                ]),
            "demo-ga-users": series(
                "active_subscribers", 18_402, unit: .count, currency: nil,
                trend: [14_900, 15_800, 16_100, 17_400, 17_900, 18_402]),
            "demo-ga-new": series(
                "new_subscribers", 2_117, unit: .count, currency: nil,
                trend: [2_400, 2_310, 2_290, 2_180, 2_140, 2_117]),
            "demo-stars": series(
                "stars", 6_786, unit: .count, currency: nil,
                trend: [6_310, 6_420, 6_560, 6_700, 6_786]),
        ]

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
