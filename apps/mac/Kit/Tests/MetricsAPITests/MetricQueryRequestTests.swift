import MetricsCore
import Testing

@testable import MetricsAPI

/// The bucket a request asks for has to follow its range.
///
/// `NotchWidget.granularity` is frozen when the widget is created and no
/// control has ever changed it, so a widget seeded with the metric's first
/// granularity kept asking for that bucket while the user moved the range.
/// Both LLM connectors list `hour` first, so a 90-day tile asked for ninety
/// days of hourly buckets and the adapter refused the walk.
@Suite("MetricQueryRequest")
struct MetricQueryRequestTests {
    private func widget(range: TimeRange, stored: Granularity) -> NotchWidget {
        NotchWidget(
            id: "w", kind: .providerMetric, appId: "openai", integrationId: "int_1",
            metric: "output_tokens", granularity: stored, range: range)
    }

    @Test("derives the bucket from the range, not from the widget's stored one")
    func derivesFromRange() {
        let request = MetricQueryRequest(widget: widget(range: .quarter, stored: .hour))
        #expect(request.range == "90d")
        #expect(request.granularity == "week")
    }

    @Test("every range maps to the bucket the server would have chosen", arguments: [
        (TimeRange.day, "hour"), (.week, "day"), (.month, "day"),
        (.quarter, "week"), (.year, "month"),
    ])
    func everyRange(range: TimeRange, expected: String) {
        // Stored deliberately wrong, so a regression that reads it fails here.
        let request = MetricQueryRequest(widget: widget(range: range, stored: .hour))
        #expect(request.granularity == expected)
    }

    /// `AppEnvironment.commit` decides whether an answer that has just arrived
    /// still belongs to its tile by comparing the request the widget would
    /// make *now* against the one that was sent. That is only sound while
    /// every setting which changes the number is part of the request, so each
    /// one gets a case here: a field that stops showing up in the comparison
    /// lets a four-to-ten-second batch write a stale number onto a tile whose
    /// picker has already moved, under the new window's title.
    @Test("a setting that changes the number changes the request")
    func settingsReachTheRequest() {
        let base = NotchWidget(
            id: "w", kind: .providerMetric, appId: "github", integrationId: "int_1",
            metric: "stars", granularity: .day, range: .month, chart: .sparkline,
            params: ["repo": "a/b"])
        let asked = MetricQueryRequest(widget: base)

        #expect(MetricQueryRequest(widget: base) == asked)

        var other = base
        other.range = .quarter
        #expect(MetricQueryRequest(widget: other) != asked)

        other = base
        other.params["repo"] = "c/d"
        #expect(MetricQueryRequest(widget: other) != asked)

        other = base
        other.params.removeValue(forKey: "repo")
        #expect(MetricQueryRequest(widget: other) != asked)

        other = base
        other.integrationId = "int_2"
        #expect(MetricQueryRequest(widget: other) != asked)

        other = base
        other.metric = "forks"
        #expect(MetricQueryRequest(widget: other) != asked)

        // Not cosmetic: a tile with no chart asks the adapter to skip the
        // series, so the answer carries different content.
        other = base
        other.chart = ChartKind.none
        #expect(MetricQueryRequest(widget: other) != asked)
    }

    /// The other half of the same bargain. A rename or a resize must *not*
    /// read as a new question, or every such edit would discard an answer
    /// already in flight and put the tile back to a skeleton.
    @Test("a cosmetic change leaves the request alone")
    func cosmeticsDoNot() {
        var widget = NotchWidget(
            id: "w", kind: .providerMetric, appId: "github", integrationId: "int_1",
            metric: "stars", granularity: .day, range: .month)
        let asked = MetricQueryRequest(widget: widget)

        widget.name = "Renamed"
        widget.size = .wide
        widget.link = "https://example.com"
        widget.format = WidgetFormat(compact: false)
        #expect(MetricQueryRequest(widget: widget) == asked)
    }
}
