import Foundation
import MetricsCore

/// Turns a custom app's answer into the shape every tile already draws.
///
/// The same conversion `PluginValue.series` makes, against the richer
/// descriptor a connector carries: a connector declares unit, currency and
/// format *per metric* rather than once per directory, so the defaults come
/// from the metric rather than the manifest.
///
/// Converging on `MetricSeries` rather than giving custom apps their own tile
/// is the whole point — one renderer, one formatter, one set of size rules. A
/// local metric that looked subtly unlike a Stripe one would be a bug reported
/// as a design complaint.
extension ConnectorMetricValue {
    /// - Parameters:
    ///   - descriptor: supplies what the run may omit. A scalar returning only
    ///     `value` still arrives complete, so the renderer never has to decide
    ///     what a missing field meant.
    ///   - window: the range the widget asked for, so `from`/`to` describe the
    ///     window the number is for rather than the runner's default.
    public func series(
        descriptor: ConnectorMetricDescriptor,
        window: PluginWindow,
        generatedAt: Date = Date()
    ) -> MetricSeries {
        let currency = currency ?? descriptor.currency

        return MetricSeries(
            // Nil, and that is the signal. A custom app has no integration row
            // on the server, which is what stops `adoptConnections` and the
            // "which account?" subtitle trying to resolve one.
            integrationId: nil,
            metric: descriptor.id,
            unit: descriptor.unit,
            // Dropped on anything that is not money. A count carrying a
            // currency renders as "$412 stars" if any formatter trusts it.
            currency: descriptor.unit == .currency ? currency : nil,
            value: value,
            previousValue: previousValue,
            delta: PluginValue.delta(value: value, previous: previousValue),
            points: points,
            granularity: window.granularity,
            range: window.range,
            from: ISO8601.string(from: window.from),
            to: ISO8601.string(from: window.to),
            format: descriptor.format ?? MetricFormat(),
            // What the *provider* said, when it said anything. `asOf` is the
            // age of the number; the run that fetched it is always now, and
            // reporting the run time would make a cached figure look fresh.
            generatedAt: asOf ?? ISO8601.string(from: generatedAt),
            stale: false,
            // Nil for anything that is not a list, so a tile can tell "not a
            // list" from "a list with nothing in it".
            items: items
        )
    }
}

/// Which app and which of its metrics a widget points at.
///
/// A connector widget needs two ids where a single-metric plugin needed one,
/// and `NotchWidget.customMetricId` is one string. Rather than add a field to
/// a persisted wire shape, the two are packed as `app/metric` — and a value
/// with no slash is read as a legacy single-metric plugin, which is what every
/// already-stored widget is.
public struct CustomMetricRef: Sendable, Hashable {
    public let appId: String?
    public let metricId: String

    /// True when this names a connector rather than a standalone metric.
    public var isConnector: Bool { appId != nil }

    public init(appId: String?, metricId: String) {
        self.appId = appId
        self.metricId = metricId
    }

    public init(packed: String) {
        // `split(separator:maxSplits:)` rather than `components`: a metric id
        // cannot contain a slash, but a malformed value should resolve to
        // *something* rather than crash, and taking the first slash keeps the
        // app id unambiguous.
        let parts = packed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            self.appId = String(parts[0])
            self.metricId = String(parts[1])
        } else {
            self.appId = nil
            self.metricId = packed
        }
    }

    public var packed: String {
        guard let appId else { return metricId }
        return "\(appId)/\(metricId)"
    }
}
