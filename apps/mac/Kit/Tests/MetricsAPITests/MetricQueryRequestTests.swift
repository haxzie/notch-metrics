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
}
