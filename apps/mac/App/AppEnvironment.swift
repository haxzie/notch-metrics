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

    /// Why the last sign-in attempt failed, for the Account pane.
    ///
    /// This used to go to NSLog only, which meant a failed exchange left the
    /// button saying "Sign in" with no explanation anywhere the user could
    /// reach — indistinguishable from the click not registering.
    private(set) var authError: String?

    func noteAuthError(_ message: String?) { authError = message }

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
            .flatMap(SettingsPane.init(rawValue:)) ?? .general

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

        // Something is always on screen, even before the first fetch lands and
        // even signed out. An empty notch with no explanation reads as broken.
        if layoutModel.layout.widgets.isEmpty {
            layoutModel.replace(with: Self.starterLayout())
        }
        // After the starter layout, which would otherwise reset the mode.
        let wantsList = ProcessInfo.processInfo.environment["NOTCH_DEBUG_LIST"] == "1"
        if ProcessInfo.processInfo.environment["NOTCH_DEBUG_DEMO"] == "1" {
            layoutModel.replace(with: Self.demoLayout(display: wantsList ? .list : .grid))
        } else if wantsList {
            layoutModel.setDisplay(.list)
        }

        states = ProcessInfo.processInfo.environment["NOTCH_DEBUG_DEMO"] == "1"
            ? Self.demoStates(for: layoutModel.layout)
            : Self.placeholderStates(for: layoutModel.layout, signedIn: isSignedIn)
        notch.update(states: states)
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

    nonisolated private static func loadLayout() -> NotchLayout {
        guard let data = try? Data(contentsOf: AppPaths.layout),
              let layout = try? JSONDecoder().decode(NotchLayout.self, from: data)
        else { return NotchLayout() }
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
    nonisolated private static func starterLayout() -> NotchLayout {
        // Three 2x2 tiles fill the 6x2 grid exactly.
        NotchLayout(widgets: [
            NotchWidget(
                id: "starter-revenue", kind: .providerMetric, appId: "stripe", metric: "revenue",
                title: "Revenue", size: .square, col: 0, row: 0, position: 0, chart: .sparkline),
            NotchWidget(
                id: "starter-mrr", kind: .providerMetric, appId: "stripe", metric: "mrr",
                title: "MRR", size: .square, col: 2, row: 0, position: 1, chart: .none),
            NotchWidget(
                id: "starter-subs", kind: .providerMetric, appId: "stripe",
                metric: "active_subscribers",
                title: "Subscribers", size: .square, col: 4, row: 0, position: 2, chart: .bars),
        ])
    }

    /// Widgets from three apps — enough to show what the list view is for.
    ///
    /// All six are present in both modes. `repack` marks the ones that do not
    /// fit the grid as hidden, which is exactly the situation the list solves.
    nonisolated private static func demoLayout(display: DisplayMode) -> NotchLayout {
        NotchLayout(
            rows: display == .list ? 4 : 2,
            display: display,
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
            (widget.id, signedIn
                ? TileState.needsSetup("Connect Stripe")
                : TileState.needsSetup("Sign in"))
        })
    }
}
