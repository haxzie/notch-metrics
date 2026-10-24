import Foundation
import MetricsCore

/// Turns a plugin's answer into the shape every tile already draws.
///
/// `MetricSeries` says in its own doc comment that it is decoded "from the
/// Worker **and** from local plugins", and `integrationId` is `String?` for
/// exactly this — but the conversion was never written, so a custom metric
/// could run and still had nothing to render. This is that missing half.
///
/// The point of converging here rather than giving plugins their own tile is
/// that there is then one renderer, one formatter and one set of size rules.
/// A local metric that looked subtly unlike a Stripe one would be a bug
/// reported as a design complaint.
extension PluginValue {
    /// - Parameters:
    ///   - manifest: supplies what the run may omit — the unit, the currency
    ///     and the number format are declared once and need not be repeated
    ///     on every result.
    ///   - window: the range the widget asked for, so `from`/`to` describe the
    ///     window the number is actually for rather than the runner's default.
    public func series(
        manifest: PluginManifest,
        window: PluginWindow,
        generatedAt: Date = Date()
    ) -> MetricSeries {
        // The run may override the unit — a metric that returns a duration one
        // day and a count the next is badly designed, but the schema allows
        // saying so, and silently keeping the manifest's would mislabel it.
        let unit = unit ?? manifest.unit
        let currency = currency ?? manifest.currency

        return MetricSeries(
            // Nil, and that is the signal. A plugin has no integration row on
            // the server, which is what stops `adoptConnections` and the
            // "which account?" subtitle trying to resolve one.
            integrationId: nil,
            metric: manifest.id,
            unit: unit,
            currency: unit == .currency ? currency : nil,
            value: value,
            previousValue: previousValue,
            delta: Self.delta(value: value, previous: previousValue),
            // A plugin that reports no series gets no points rather than one
            // invented at `now`: a single reading drawn as a line is the flat
            // line that looks like data.
            points: series ?? [],
            granularity: window.granularity,
            range: window.range,
            from: ISO8601.string(from: window.from),
            to: ISO8601.string(from: window.to),
            format: manifest.format,
            // What the *provider* said, when it said anything. `asOf` is the
            // age of the number; the run that fetched it is always now, and
            // reporting the run time would make a cached figure look fresh.
            generatedAt: asOf ?? ISO8601.string(from: generatedAt),
            stale: false,
            // Plugins have no list shape yet. Nil rather than empty, so a tile
            // can tell "not a list" from "a list with nothing in it".
            items: nil
        )
    }

    /// Absolute always; percent only where it means something.
    ///
    /// Zero to five is an infinite increase, not a 100% one, and a tile that
    /// renders `+∞%` — or worse, `+100%` — is worse than one that renders the
    /// absolute change alone.
    static func delta(value: Double, previous: Double?) -> MetricDelta? {
        guard let previous else { return nil }
        let absolute = value - previous
        guard previous != 0 else { return MetricDelta(absolute: absolute, percent: nil) }
        return MetricDelta(absolute: absolute, percent: absolute / abs(previous) * 100)
    }
}

/// The window a plugin run was for.
///
/// Carried alongside the result rather than derived from it because the runner
/// does not currently echo the window back: `PluginRunner` passes no
/// `--from`/`--to`, so the runner applies its own default of the last thirty
/// days. Whoever schedules the run knows the widget's range and is the only
/// honest source for this.
public struct PluginWindow: Sendable, Hashable {
    public let range: TimeRange
    public let granularity: Granularity
    public let from: Date
    public let to: Date

    public init(range: TimeRange, granularity: Granularity, from: Date, to: Date) {
        self.range = range
        self.granularity = granularity
        self.from = from
        self.to = to
    }

    /// The window for a range, ending now.
    ///
    /// The granularity is the one the range implies, which is the same table
    /// the configure pane uses to decide which ranges to offer — so a tile and
    /// its picker cannot disagree about what "30d" means.
    public static func of(_ range: TimeRange, now: Date = Date()) -> PluginWindow {
        PluginWindow(
            range: range,
            granularity: range.defaultGranularity,
            from: now.addingTimeInterval(-range.duration),
            to: now
        )
    }
}
