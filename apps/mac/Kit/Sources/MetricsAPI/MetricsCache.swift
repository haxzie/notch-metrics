import Foundation
import MetricsCore

/// Last-known-good metric data, on disk as plain JSON.
///
/// Not SwiftData. This is "the last thirty points for eight widgets" — no
/// relationships, no queries, no sync. SwiftData would add a model container
/// lifecycle, migration ceremony and actor-isolation friction under Swift 6,
/// in exchange for nothing this app needs.
public actor MetricsCache {
    private let directory: URL
    private var memory: [String: MetricSeries] = [:]

    public init(directory: URL = AppPaths.metricCache) {
        self.directory = directory
    }

    private func key(widgetID: String, range: TimeRange) -> String {
        "\(widgetID)-\(range.rawValue)"
    }

    public func load(widgetID: String, range: TimeRange) -> MetricSeries? {
        let cacheKey = key(widgetID: widgetID, range: range)
        if let hit = memory[cacheKey] { return hit }

        let url = directory.appendingPathComponent("\(cacheKey).json")
        guard let data = try? Data(contentsOf: url),
              let series = try? JSONDecoder().decode(MetricSeries.self, from: data)
        else { return nil }

        memory[cacheKey] = series
        return series
    }

    public func store(_ series: MetricSeries, widgetID: String, range: TimeRange) {
        let cacheKey = key(widgetID: widgetID, range: range)
        memory[cacheKey] = series

        guard let data = try? JSONEncoder().encode(series) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("\(cacheKey).json"), options: .atomic)
    }

    /// Drops entries nothing has read in a fortnight. Called at launch.
    public func evict(olderThan days: Int = 14) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }

        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    public func clear() {
        memory.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }
}
