import Foundation
import Testing

@testable import MetricsAPI

private func metric(
    _ id: String, _ label: String, short: String, keywords: [String] = []
) -> MetricDescriptor {
    MetricDescriptor(
        id: id, label: label, shortLabel: short, unit: .count, granularities: [.day],
        supportsSeries: true, supportsCompare: true, keywords: keywords, help: nil,
        methodology: "x")
}

private func app(
    _ id: String, _ name: String, keywords: [String] = [], metrics: [MetricDescriptor]
) -> ConnectorEntry {
    ConnectorEntry(
        id: id, name: name, category: "revenue", tagline: "", docsUrl: "https://example.com",
        accentColor: "#111111", keywords: keywords, authMode: "api_key", oauth: nil, fields: [],
        metrics: metrics, status: "stable", minAppVersion: "0.1.0", connections: [])
}

private let catalogue = [
    app(
        "stripe", "Stripe", keywords: ["payments", "billing"],
        metrics: [
            metric("mrr", "Monthly recurring revenue", short: "MRR", keywords: ["recurring"]),
            metric(
                "churned_subscribers", "Churned subscribers", short: "Churned",
                keywords: ["churn", "cancellations"]),
        ]),
    app(
        "plausible", "Plausible", keywords: ["web analytics", "privacy"],
        metrics: [metric("visitors", "Visitors", short: "Visitors", keywords: ["traffic"])]),
]

@Suite struct WidgetSearchTests {
    @Test("an empty query lists every app with no widgets expanded")
    func empty() {
        let results = WidgetSearch.run("  ", over: catalogue)
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.metrics.isEmpty })
    }

    @Test("matching an app brings all of its widgets")
    func byAppName() {
        let results = WidgetSearch.run("stripe", over: catalogue)
        #expect(results.map(\.app.id) == ["stripe"])
        #expect(results.first?.metrics.count == 2)
    }

    @Test("an app keyword finds the app")
    func byAppKeyword() {
        // Nobody searches for "Plausible" when what they want is analytics.
        #expect(WidgetSearch.run("privacy", over: catalogue).map(\.app.id) == ["plausible"])
    }

    @Test("a widget keyword finds just that widget")
    func byMetricKeyword() {
        let results = WidgetSearch.run("cancellations", over: catalogue)
        #expect(results.map(\.app.id) == ["stripe"])
        #expect(results.first?.metrics.map(\.id) == ["churned_subscribers"])
    }

    @Test("a widget label finds it across apps")
    func byMetricLabel() {
        #expect(WidgetSearch.run("visitors", over: catalogue).map(\.app.id) == ["plausible"])
    }

    @Test("every term has to match, so two words narrow")
    func termsNarrow() {
        // "stripe churn" must not widen to everything called Stripe plus
        // everything about churn.
        let results = WidgetSearch.run("stripe churn", over: catalogue)
        #expect(results.map(\.app.id) == ["stripe"])
        #expect(results.first?.metrics.map(\.id) == ["churned_subscribers"])
    }

    @Test("search is case insensitive")
    func caseInsensitive() {
        #expect(WidgetSearch.run("STRIPE", over: catalogue).map(\.app.id) == ["stripe"])
    }

    @Test("no match is no results, not everything")
    func noMatch() {
        #expect(WidgetSearch.run("kubernetes", over: catalogue).isEmpty)
    }
}
