import Foundation
import Testing

@testable import MetricsCore

@Suite struct WidgetFormatTests {
    private func series(_ value: Double, unit: MetricUnit, currency: String? = nil) -> MetricSeries {
        MetricSeries(
            integrationId: "int", metric: "m", unit: unit, currency: currency, value: value)
    }

    @Test("counts compact to k, M and B")
    func countsCompact() {
        #expect(MetricFormatter.display(series(1_200, unit: .count)) == "1.2k")
        #expect(MetricFormatter.display(series(3_400_000, unit: .count)) == "3.4M")
        #expect(MetricFormatter.display(series(1_100_000_000, unit: .count)) == "1.1B")
    }

    @Test("money compacts from four figures, like a count does")
    func currencyCompacts() {
        // The thresholds used to differ — 10,000 for money, 1,000 for counts —
        // so $9,800 rendered in full beside 9.8k of anything else on tiles the
        // same width.
        #expect(MetricFormatter.display(series(980_000, unit: .currency, currency: "USD")) == "$9.8k")
        #expect(MetricFormatter.display(series(128_450_000, unit: .currency, currency: "USD")) == "$1.3M")
    }

    @Test("a widget can force the full number")
    func widgetOverridesCompact() {
        let full = WidgetFormat(compact: false)
        #expect(
            MetricFormatter.display(series(1_200, unit: .count), override: full) == "1,200")
    }

    @Test("a widget can force compaction on a small number")
    func widgetForcesCompact() {
        let short = WidgetFormat(compact: true)
        #expect(MetricFormatter.display(series(12_300, unit: .count), override: short) == "12.3k")
    }

    @Test("a widget can restate the type")
    func widgetOverridesStyle() {
        // An adapter reporting a conversion rate as a count still wants to
        // read as a percentage.
        let asRatio = WidgetFormat(style: .ratio)
        #expect(MetricFormatter.display(series(0.0734, unit: .count), override: asRatio) == "7.3%")
    }

    @Test("prefix and suffix wrap the number")
    func affixes() {
        let format = WidgetFormat(compact: false, prefix: "~", suffix: " seats")
        #expect(
            MetricFormatter.display(series(42, unit: .count), override: format) == "~42 seats")
    }

    @Test("no format at all behaves exactly as before")
    func nilFormatIsUnchanged() {
        // Every layout.json written before formats existed decodes to nil, and
        // those widgets must not change how they read.
        let s = series(950_000, unit: .currency, currency: "USD")
        #expect(MetricFormatter.display(s, override: nil) == MetricFormatter.display(s))
    }
}
