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

    /// The on-disk name for one widget's last-known number.
    ///
    /// The widget's parameters are part of it. A tile repointed from one
    /// repository to another would otherwise load the first one's series and
    /// show it under the second — a real number, attributed to the wrong
    /// thing, and it sits there for as long as the next fetch takes.
    ///
    /// A widget with no parameters keeps exactly the name it already has, so
    /// an app update does not silently discard every cached number on disk.
    private func key(widgetID: String, range: TimeRange, params: [String: String]) -> String {
        let base = "\(widgetID)-\(range.rawValue)"
        guard !params.isEmpty else { return base }
        let canonical = params
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        return "\(base)-\(Self.stableDigest(canonical))"
    }

    /// FNV-1a, because this ends up in a filename.
    ///
    /// Deliberately not `hashValue`: Swift seeds that per process, so a key
    /// built from it would miss every entry the previous launch wrote — a
    /// cache that silently never hits. Digested rather than sanitised because
    /// a repository has a slash in it.
    private static func stableDigest(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 36)
    }

    public func load(widgetID: String, range: TimeRange, params: [String: String] = [:])
        -> MetricSeries?
    {
        let cacheKey = key(widgetID: widgetID, range: range, params: params)
        if let hit = memory[cacheKey] { return hit }

        let url = directory.appendingPathComponent("\(cacheKey).json")
        guard let data = try? Data(contentsOf: url),
              let series = try? JSONDecoder().decode(MetricSeries.self, from: data)
        else { return nil }

        memory[cacheKey] = series
        return series
    }

    public func store(
        _ series: MetricSeries, widgetID: String, range: TimeRange,
        params: [String: String] = [:]
    ) {
        let cacheKey = key(widgetID: widgetID, range: range, params: params)
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
