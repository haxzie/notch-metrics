import Testing

@testable import MetricsCore

/// A tile's title carries the time window when the number depends on one.
struct WidgetTitleTests {
    @Test("a windowed metric gets its range after a middle dot")
    func windowed() {
        let widget = NotchWidget(appId: "stripe", metric: "revenue", title: "Revenue", range: .month)
        #expect(widget.displayTitle(showingRange: true) == "Revenue · 30d")
    }

    @Test("every range spells itself the way the picker does")
    func ranges() {
        let expected: [TimeRange: String] = [
            .day: "24h", .week: "7d", .month: "30d", .quarter: "90d", .year: "12m",
        ]
        for (range, suffix) in expected {
            let widget = NotchWidget(appId: "stripe", metric: "revenue", title: "Revenue", range: range)
            #expect(widget.displayTitle(showingRange: true) == "Revenue · \(suffix)")
        }
    }

    @Test("a snapshot keeps its plain title")
    func snapshot() {
        // MRR is a reading of the book right now. "MRR · 30d" would claim a
        // window the number does not have.
        let widget = NotchWidget(appId: "stripe", metric: "mrr", title: "MRR", range: .month)
        #expect(widget.displayTitle(showingRange: false) == "MRR")
    }

    @Test("a widget with no title falls back to its metric, then its plugin")
    func fallbacks() {
        #expect(NotchWidget(appId: "stripe", metric: "revenue").displayTitle(showingRange: true)
            == "revenue · 30d")
        #expect(NotchWidget(kind: .customMetric, customMetricId: "github-stars").baseTitle
            == "github-stars")
        #expect(NotchWidget().baseTitle == "Metric")
    }

    @Test("the metric key names a provider metric by app and a custom one by plugin")
    func keys() {
        #expect(NotchWidget(appId: "stripe", metric: "revenue").metricKey == "stripe/revenue")
        #expect(
            NotchWidget(kind: .customMetric, appId: "github", customMetricId: "github-stars")
                .metricKey == "custom/github-stars")
        #expect(NotchWidget(kind: .divider).metricKey == nil)
    }
}
