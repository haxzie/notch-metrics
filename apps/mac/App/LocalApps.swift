import MetricsAPI
import MetricsCore
import PluginRuntime

/// Installed custom apps, described the way the widget browser wants them.
///
/// The translation layer between what is on disk and what the gallery draws.
///
/// Only connectors — one app holding one credential and offering several
/// metrics. The older standalone single-metric format is no longer authored
/// or managed: it has no row in Settings, so a widget added for one could
/// never be approved, and offering it here would be offering a dead end. What
/// is already installed and approved keeps running; see `refreshPlugins`.
enum LocalApps {
    /// Only what the user has actually enabled.
    ///
    /// A pending app is listed in Settings, where the toggle is, but not in
    /// the browser: adding a widget for something that will not run until a
    /// separate yes is given produces a tile that says nothing, and the user
    /// has no reason to connect the two surfaces.
    static func browsable(connectors: [LoadedConnector]) -> [LocalCatalogue.LocalApp] {
        fromConnectors(connectors)
    }

    private static func fromConnectors(_ connectors: [LoadedConnector])
        -> [LocalCatalogue.LocalApp]
    {
        connectors.compactMap { app in
            guard app.state == .ready, let manifest = app.manifest else { return nil }
            return LocalCatalogue.LocalApp(
                id: app.id,
                name: manifest.name,
                tagline: manifest.description,
                metrics: manifest.metrics.map { descriptor($0, in: app.id) },
                icon: app.icon,
                // Resolved through `LoadedConnector`, which checks the file is
                // actually there and refuses a name that escapes the app's own
                // directory.
                iconFile: app.iconURL)
        }
    }

    /// Descriptor for one metric of a connector.
    ///
    /// The id is `app/metric`, which is what `CustomMetricRef` unpacks on the
    /// way back. A bare metric id would be ambiguous the moment two custom
    /// apps both offer `downloads`.
    private static func descriptor(
        _ metric: ConnectorMetricDescriptor, in appId: String
    ) -> MetricDescriptor {
        let granularities: [Granularity]
        let series: Bool
        switch metric.shape {
        case .scalar:
            granularities = [.day]
            series = false
        case let .series(declared, _):
            granularities = declared
            series = true
        case let .total(declared, _):
            granularities = declared
            series = false
        case .list:
            granularities = [.day]
            series = false
        case .unknown:
            // A shape this build does not know. Offered as a plain number
            // rather than hidden: the connector may well return something
            // renderable, and hiding it gives the author no way to find out.
            granularities = [.day]
            series = false
        }

        return MetricDescriptor(
            id: CustomMetricRef(appId: appId, metricId: metric.id).packed,
            label: metric.label,
            shortLabel: metric.shortLabel,
            unit: metric.unit,
            granularities: granularities,
            supportsSeries: series,
            supportsCompare: compares(metric.shape),
            help: metric.methodology,
            params: metric.params?.map(Self.field),
            methodology: metric.methodology,
            linkTemplate: metric.linkTemplate,
            isList: {
                if case .list = metric.shape { return true }
                return false
            }())
    }

    private static func compares(_ shape: ConnectorMetricShape) -> Bool {
        switch shape {
        case let .series(_, compare), let .total(_, compare): compare
        case .scalar, .list, .unknown: false
        }
    }

    /// `PluginRuntime`'s auth field as the catalogue's.
    ///
    /// Two near-identical structs in two modules that must not depend on each
    /// other. `type` crosses as its raw string, which is exactly what the
    /// server sends, so the configure pane's existing fallback handles an
    /// unfamiliar one unchanged.
    private static func field(_ field: ConnectorAuthField) -> AuthField {
        AuthField(
            key: field.key,
            label: field.label,
            type: field.type == .unknown ? "secret" : field.type.rawValue,
            required: field.required,
            placeholder: field.placeholder,
            help: field.help,
            pattern: field.pattern,
            options: field.options?.map { AuthFieldOption(value: $0.value, label: $0.label) },
            default: field.default)
    }
}
