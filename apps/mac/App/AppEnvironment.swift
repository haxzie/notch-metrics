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
    private(set) var isSignedIn = false

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

    private(set) var signIn: SignInState = .idle

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
            .flatMap { SettingsPane(rawValue: $0) ?? SettingsPane.aliases[$0] } ?? .widgets

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

        let secrets = KeychainSecretStore()
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
        if ProcessInfo.processInfo.environment["NOTCH_DEBUG_DEMO"] == "1" {
            layoutModel.replace(with: Self.demoLayout())
        }

        states = ProcessInfo.processInfo.environment["NOTCH_DEBUG_DEMO"] == "1"
            ? Self.demoStates(for: layoutModel.layout)
            : Self.placeholderStates(for: layoutModel.layout, signedIn: isSignedIn)
        notch.update(states: states)

        startRefreshing()
    }

    // MARK: - Real numbers

    private var refreshTask: Task<Void, Never>?

    /// Keeps the notch's tiles filled from the API.
    ///
    /// One batch request for the whole layout rather than one per tile: eight
    /// widgets usually point at two or three integrations, and fanning out
    /// defeats the per-integration spacing that keeps us inside a provider's
    /// rate limit.
    func startRefreshing() {
        guard ProcessInfo.processInfo.environment["NOTCH_DEBUG_DEMO"] != "1" else { return }
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

    /// Fetches once, now. Called on launch, on a timer, and after a widget is
    /// added so a new tile fills in rather than sitting on "Loading".
    func refresh() async {
        guard isSignedIn else {
            states = Self.placeholderStates(for: layoutModel.layout, signedIn: false)
            notch.update(states: states)
            return
        }

        let widgets = layoutModel.layout.widgets.filter {
            $0.integrationId?.isEmpty == false && $0.metric?.isEmpty == false
        }
        guard !widgets.isEmpty else {
            states = Self.placeholderStates(for: layoutModel.layout, signedIn: true)
            notch.update(states: states)
            return
        }

        // Last known values first, so a tile shows yesterday's number while
        // the request is in flight rather than a skeleton.
        var next = states
        for widget in widgets where next[widget.id] == nil {
            if let cached = await cache.load(widgetID: widget.id, range: widget.range) {
                next[widget.id] = .value(cached)
            } else {
                next[widget.id] = .loading
            }
        }
        states = next
        notch.update(states: states)

        do {
            let results = try await api.batch(widgets.map(MetricQueryRequest.init(widget:)))
            guard results.count == widgets.count else { return }

            for (widget, result) in zip(widgets, results) {
                switch result {
                case .success(let series):
                    next[widget.id] = .value(series)
                    await cache.store(series, widgetID: widget.id, range: widget.range)
                case .failure(let failure):
                    // Keep a cached number on screen rather than replacing it
                    // with an error: a stale figure with a mark against it
                    // beats a blank tile while a provider is down.
                    if case .value = next[widget.id] { continue }
                    next[widget.id] = .failed(reason: failure.message)
                }
            }
            states = next
            notch.update(states: states)
        } catch {
            for widget in widgets where !isValue(next[widget.id]) {
                next[widget.id] = .failed(reason: "Could not reach Notch Metrics")
            }
            states = next
            notch.update(states: states)
        }
    }

    private func isValue(_ state: TileState?) -> Bool {
        if case .value = state { return true }
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
                NotchWidget(
                    id: "starter-subs", kind: .providerMetric, appId: "stripe",
                    metric: "active_subscribers", title: "Subscribers", size: .square,
                    col: 4, row: 0, position: 2, chart: .bars),
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
            // Names the app the tile belongs to rather than a hardcoded one.
            let app = AppCatalog.resolve(widget.appId)
            return (widget.id, TileState.needsSetup("Connect \(app.name)"))
        })
    }
}
