import Foundation
import MetricsCore

/// The **Custom** category in the widget browser.
///
/// Everything built on this machine appears here, under one heading, so
/// browsing for a widget does not ask the user to know whether a number comes
/// from our Worker or from code they wrote last night. The shape is the
/// server's own `ConnectorEntry`, which is what lets the gallery, the search
/// field and the preview card work on local apps with no second code path.
///
/// Built here, in `MetricsAPI`, rather than where the manifests are read: this
/// module owns the catalogue types, and the alternative was making the browser
/// assemble a dozen fields correctly in a view file.
public enum LocalCatalogue {
    /// Namespacing for local ids, so a custom app called `stripe` cannot be
    /// mistaken for the connector we ship.
    ///
    /// The prefix is the whole mechanism behind `ConnectorEntry.isLocal`, and
    /// so decides whether a widget is refreshed by the Node runner or by the
    /// Worker. A collision here would send someone's Stripe widget to a local
    /// script, or their local widget to an API that has never heard of it.
    public static let idPrefix = "local."

    /// The category id and label every local app is filed under.
    public static let categoryId = "custom"
    public static let categoryLabel = "Custom"

    /// What a local entry puts in `status`.
    ///
    /// Not `"coming_soon"`, which would make `isConnectable` false and show a
    /// "not ready to connect yet" message. A custom app has nothing to
    /// connect *to* — its credentials live in the Keychain already — so it is
    /// available in the sense the browser cares about.
    public static let status = "available"

    public static func id(for localId: String) -> String { idPrefix + localId }

    /// One browsable app per custom app.
    ///
    /// - Parameters:
    ///   - apps: `(id, name, tagline, metrics)` for each installed app. Taken
    ///     as plain values rather than as `LoadedConnector` so this module
    ///     does not have to depend on `PluginRuntime` — the dependency runs
    ///     the other way round everywhere else, and inverting it here would be
    ///     a cycle.
    public static func entries(_ apps: [LocalApp]) -> [ConnectorEntry] {
        apps.map { app in
            ConnectorEntry(
                id: id(for: app.id),
                name: app.name,
                category: categoryId,
                tagline: app.tagline,
                // No `dashboardUrl`: a custom app has no web app to open, and
                // a tile that looks clickable and does nothing is worse than
                // one that does not.
                accentColor: AppCatalog.resolve(AppCatalog.customId).accentHex,
                // Searchable by "custom" and "local" as well as by its own
                // name, because that is what someone types when they cannot
                // remember what they called it.
                keywords: ["custom", "local"] + app.keywords,
                authMode: "api_key",
                metrics: app.metrics,
                status: status,
                customIcon: app.icon,
                customIconFile: app.iconFile)
        }
    }

    public static func group(_ apps: [LocalApp]) -> ConnectorCategoryGroup? {
        let entries = entries(apps).filter { !$0.metrics.isEmpty }
        guard !entries.isEmpty else { return nil }
        return ConnectorCategoryGroup(id: categoryId, label: categoryLabel, connectors: entries)
    }

    /// The minimum a custom app has to say to be browsable.
    public struct LocalApp: Sendable {
        public let id: String
        public let name: String
        public let tagline: String
        public let keywords: [String]
        public let metrics: [MetricDescriptor]
        /// What the app's manifest says it looks like.
        public let icon: CustomAppIcon?
        /// Artwork, already resolved against the app's own directory.
        public let iconFile: URL?

        public init(
            id: String, name: String, tagline: String, keywords: [String] = [],
            metrics: [MetricDescriptor], icon: CustomAppIcon? = nil, iconFile: URL? = nil
        ) {
            self.id = id
            self.name = name
            self.tagline = tagline
            self.keywords = keywords
            self.metrics = metrics
            self.icon = icon
            self.iconFile = iconFile
        }
    }
}

extension ConnectorEntry {
    /// The app this entry stands for, as the icon and theme views want it.
    ///
    /// Resolving through `AppCatalog` alone was not enough: that returns the
    /// *generic* Custom app, whose `customIcon` is nil, so a manifest
    /// declaring `shippingbox.fill` still drew `{}`. The declared icon has to
    /// be carried across, which is what this does — in one place, rather than
    /// at each of the gallery's three call sites.
    public var metricApp: MetricApp {
        guard isLocal, customIcon != nil || customIconFile != nil else {
            return AppCatalog.resolve(isLocal ? AppCatalog.customId : id)
        }
        // The same builder the notch's overrides use, so the gallery and the
        // tile cannot disagree about what a custom app looks like.
        return MetricApp.custom(
            id: id, name: name, icon: customIcon, iconFile: customIconFile)
    }
}
