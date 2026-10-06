import Foundation

/// One app and whichever of its widgets matched.
public struct WidgetSearchResult: Identifiable {
    public let app: ConnectorEntry
    public let metrics: [MetricDescriptor]
    public var id: String { app.id }

    public init(app: ConnectorEntry, metrics: [MetricDescriptor]) {
        self.app = app
        self.metrics = metrics
    }
}

public enum WidgetSearch {
    /// Matches app names, app keywords, widget labels and widget keywords.
    ///
    /// Substring rather than fuzzy: with a few hundred terms, fuzzy matching
    /// mostly produces confident wrong answers. Every term in the query has
    /// to match something, so "stripe churn" narrows instead of widening.
    public static func run(_ query: String, over apps: [ConnectorEntry]) -> [WidgetSearchResult] {
        let terms = query
            .lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)

        guard !terms.isEmpty else {
            return apps.map { WidgetSearchResult(app: $0, metrics: []) }
        }

        return apps.compactMap { app in
            let appText = haystack(for: app)

            // An app whose own name matches brings all of its widgets; this
            // is how "stripe" lists everything Stripe can show.
            if terms.allSatisfy({ appText.contains($0) }) {
                return WidgetSearchResult(app: app, metrics: app.metrics)
            }

            let metrics = app.metrics.filter { metric in
                let combined = appText + " " + haystack(for: metric)
                return terms.allSatisfy { combined.contains($0) }
            }
            return metrics.isEmpty ? nil : WidgetSearchResult(app: app, metrics: metrics)
        }
    }

    private static func haystack(for app: ConnectorEntry) -> String {
        ([app.name, app.tagline] + (app.keywords ?? [])).joined(separator: " ").lowercased()
    }

    private static func haystack(for metric: MetricDescriptor) -> String {
        ([metric.label, metric.shortLabel, metric.id] + (metric.keywords ?? []))
            .joined(separator: " ")
            .lowercased()
    }
}
