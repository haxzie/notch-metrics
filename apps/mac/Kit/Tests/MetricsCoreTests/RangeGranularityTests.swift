import Testing

@testable import MetricsCore

/// `TimeRange.defaultGranularity` mirrors `DEFAULT_GRANULARITY` in
/// `packages/schemas`. The two being the same choice made twice is what lets
/// the configure pane decide, without asking the server, which ranges a
/// metric's declared `granularities` can answer for.
@Suite("range to granularity")
struct RangeGranularityTests {
    @Test("matches the server's table")
    func matchesTheServer() {
        #expect(TimeRange.day.defaultGranularity == .hour)
        #expect(TimeRange.week.defaultGranularity == .day)
        #expect(TimeRange.month.defaultGranularity == .day)
        #expect(TimeRange.quarter.defaultGranularity == .week)
        #expect(TimeRange.year.defaultGranularity == .month)
    }

    /// The combinations that were offered and then failed on the tile. Both
    /// AI connectors bucket tokens by hour, day or week and cost by day or
    /// week, so "12m" is unanswerable for either and "24h" for spend.
    @Test("the ranges the AI connectors cannot serve are the ones that errored")
    func aiConnectorRanges() {
        let tokens: [Granularity] = [.hour, .day, .week]
        let spend: [Granularity] = [.day, .week]

        func offered(_ granularities: [Granularity]) -> [TimeRange] {
            TimeRange.allCases.filter { granularities.contains($0.defaultGranularity) }
        }

        #expect(offered(tokens) == [.day, .week, .month, .quarter])
        #expect(!offered(tokens).contains(.year))

        #expect(offered(spend) == [.week, .month, .quarter])
        #expect(!offered(spend).contains(.day))
        #expect(!offered(spend).contains(.year))
    }

    /// A snapshot metric declares one granularity and would otherwise offer
    /// five ranges, four of which mean nothing to it.
    @Test("a day-only metric offers only the day-bucketed ranges")
    func dayOnly() {
        let offered = TimeRange.allCases.filter { [Granularity.day].contains($0.defaultGranularity) }
        #expect(offered == [.week, .month])
    }
}
