import Foundation
import MetricsCore
import Testing

@testable import MetricsAPI

private func series(_ value: Double) -> MetricSeries {
    MetricSeries(
        integrationId: "int_1", metric: "stars", unit: .count, currency: nil, value: value,
        previousValue: nil, delta: nil, points: [], granularity: .day, range: .month,
        from: "2026-09-09T00:00:00Z", to: "2026-10-09T00:00:00Z", format: nil,
        generatedAt: "2026-10-09T00:00:00Z", stale: false)
}

/// A disposable directory, so these never touch the real cache.
private func scratch() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("metrics-cache-\(UUID().uuidString)")
    return url
}

@Suite("MetricsCache")
struct MetricsCacheTests {
    @Test("a widget repointed at another repository does not read the first one's number")
    func paramsSeparateEntries() async throws {
        let cache = MetricsCache(directory: scratch())
        await cache.store(
            series(412), widgetID: "w1", range: .month, params: ["repository": "owner/a"])

        // Same widget, same range, different repository. Without the params in
        // the key this returns 412 and the tile shows it under owner/b.
        let other = await cache.load(
            widgetID: "w1", range: .month, params: ["repository": "owner/b"])
        #expect(other == nil)

        let same = await cache.load(
            widgetID: "w1", range: .month, params: ["repository": "owner/a"])
        #expect(same?.value == 412)
    }

    @Test("a widget with no parameters keeps the file it already had")
    func paramlessKeyIsUnchanged() async throws {
        let directory = scratch()
        let cache = MetricsCache(directory: directory)
        await cache.store(series(7), widgetID: "w1", range: .month)

        // The name an older build wrote, byte for byte. A changed one would
        // quietly discard every cached number on the update that shipped it.
        let expected = directory.appendingPathComponent("w1-30d.json")
        #expect(FileManager.default.fileExists(atPath: expected.path))
        #expect(await cache.load(widgetID: "w1", range: .month)?.value == 7)
    }

    @Test("the key survives a relaunch, so the cache is not write-only")
    func digestIsStableAcrossInstances() async throws {
        let directory = scratch()
        let params = ["repository": "owner/a"]

        await MetricsCache(directory: directory).store(
            series(99), widgetID: "w1", range: .month, params: params)

        // A fresh actor with an empty memory layer, which is what the next
        // launch is. `hashValue` would be seeded differently and miss.
        let reopened = MetricsCache(directory: directory)
        #expect(await reopened.load(widgetID: "w1", range: .month, params: params)?.value == 99)
    }

    @Test("parameter order does not split one widget across two entries")
    func orderDoesNotMatter() async throws {
        let cache = MetricsCache(directory: scratch())
        await cache.store(
            series(5), widgetID: "w1", range: .month,
            params: ["repository": "owner/a", "branch": "main"])
        let reordered = await cache.load(
            widgetID: "w1", range: .month,
            params: ["branch": "main", "repository": "owner/a"])
        #expect(reordered?.value == 5)
    }
}
