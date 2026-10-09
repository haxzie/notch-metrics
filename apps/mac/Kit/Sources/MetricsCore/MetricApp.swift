import Foundation

/// The app a number came from.
///
/// Every metric in the notch belongs to one — Stripe, Google Analytics, or
/// whatever a custom metric declared. That is what the list view groups by and
/// what the tile's mark identifies, so it needs an answer for *any* id,
/// including ones this build predates.
public struct MetricApp: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    /// An SF Symbol, used only where no vendored brand mark exists.
    public let symbol: String
    /// `RRGGBB`. Converted to a colour in NotchUI, so MetricsCore stays free
    /// of SwiftUI and can be tested without a UI.
    public let accentHex: String

    /// The colour for a chart line, when it differs from the accent.
    ///
    /// Several brands are a dark primary plus a bright secondary: Dodo
    /// Payments is black with lime. The black is right behind their mark and
    /// useless as a 1.5pt line on a dark tile, so the two are separate rather
    /// than one being derived from the other.
    public let chartHex: String?

    public init(
        id: String, name: String, symbol: String, accentHex: String, chartHex: String? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.accentHex = accentHex
        self.chartHex = chartHex
    }
}

public enum AppCatalog {
    public static let customId = "custom"
    public static let unknownId = "unknown"

    /// What ships in the binary.
    ///
    /// The server's provider manifests carry a name and an accent colour too,
    /// and `resolve(_:overrides:)` prefers those — but the app has to render a
    /// cold launch with no network, and custom metrics name apps the server
    /// has never heard of.
    /// What ships in the binary.
    ///
    /// The server's connector manifests carry a name and an accent colour too,
    /// and `resolve(_:overrides:)` prefers those — but the app has to render a
    /// cold launch with no network, and custom metrics name apps the server has
    /// never heard of.
    ///
    /// Symbols rather than vendor logos: shipping third-party marks means an
    /// asset pipeline, a licence question for each one, and a release every time
    /// somebody rebrands. `ProviderManifest.iconPath` exists for when that trade
    /// is worth making.
    public static let builtIn: [MetricApp] = [
        MetricApp(
            id: "stripe", name: "Stripe", symbol: "creditcard.fill", accentHex: "635BFF"),
        MetricApp(
            id: "dodopayments", name: "Dodo Payments", symbol: "bird.fill", accentHex: "111111",
            chartHex: "C6FE1E"),
        MetricApp(
            id: "lemonsqueezy", name: "Lemon Squeezy", symbol: "cart.fill", accentHex: "FFC233"),
        MetricApp(
            id: "polar", name: "Polar", symbol: "snowflake", accentHex: "0062FF"),
        MetricApp(
            id: "paddle", name: "Paddle", symbol: "banknote.fill", accentHex: "FDDD35"),
        MetricApp(
            id: "revenuecat", name: "RevenueCat", symbol: "cat.fill", accentHex: "F2545B"),
        MetricApp(
            id: "posthog", name: "PostHog", symbol: "chart.dots.scatter", accentHex: "F54E00"),
        MetricApp(
            id: "plausible", name: "Plausible", symbol: "chart.xyaxis.line", accentHex: "5850EC"),
        MetricApp(
            id: "mixpanel", name: "Mixpanel", symbol: "chart.bar.xaxis", accentHex: "7856FF"),
        MetricApp(
            id: "amplitude", name: "Amplitude", symbol: "waveform.path.ecg", accentHex: "1E61F0"),
        MetricApp(
            id: "google-analytics", name: "Google Analytics", symbol: "chart.bar.fill", accentHex: "E8710A"),
        MetricApp(
            id: "google-search-console", name: "Google Search Console", symbol: "magnifyingglass", accentHex: "4285F4"),
        MetricApp(
            id: "google-ads", name: "Google Ads", symbol: "megaphone.fill", accentHex: "4285F4"),
        MetricApp(
            id: "meta-ads", name: "Meta Ads", symbol: "bubble.left.and.bubble.right.fill", accentHex: "0866FF"),
        MetricApp(
            id: "hubspot", name: "HubSpot", symbol: "person.crop.circle.badge.checkmark", accentHex: "FF7A59"),
        MetricApp(
            id: "intercom", name: "Intercom", symbol: "message.fill", accentHex: "1F8DED"),
        MetricApp(
            id: "github", name: "GitHub", symbol: "chevron.left.forwardslash.chevron.right",
            accentHex: "F0F6FC"),
        MetricApp(
            id: "linear", name: "Linear", symbol: "square.stack.3d.up.fill", accentHex: "5E6AD2"),
        MetricApp(
            id: "plausible-selfhost", name: "Plausible (self-hosted)", symbol: "chart.xyaxis.line", accentHex: "5850EC"),
        MetricApp(id: customId, name: "Custom", symbol: "curlybraces", accentHex: "D819C2"),
    ]

    private static let byId: [String: MetricApp] = Dictionary(
        uniqueKeysWithValues: builtIn.map { ($0.id, $0) })

    /// Never fails.
    ///
    /// An unrecognised id is titlecased and given a neutral mark rather than
    /// dropped. The alternative — hiding the row, or refusing the layout — is
    /// how one unfamiliar value from a newer server blanks a whole notch.
    public static func resolve(_ id: String?, overrides: [String: MetricApp] = [:]) -> MetricApp {
        let key = (id?.isEmpty == false ? id! : unknownId).lowercased()
        if let override = overrides[key] { return override }
        if let known = byId[key] { return known }
        return MetricApp(
            id: key, name: titlecase(key), symbol: "app.dashed", accentHex: "8E8E93")
    }

    /// "google-analytics" → "Google Analytics".
    static func titlecase(_ id: String) -> String {
        id.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

extension NotchWidget {
    /// The app this widget belongs to, with the server's manifests preferred
    /// when they are loaded.
    public func app(overrides: [String: MetricApp] = [:]) -> MetricApp {
        AppCatalog.resolve(appId, overrides: overrides)
    }
}
