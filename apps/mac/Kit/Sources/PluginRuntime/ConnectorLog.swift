import Foundation
import MetricsCore

/// One log file per custom app, written where a person can find it.
///
/// A custom app is code somebody wrote that afternoon, usually with an agent,
/// against an API neither of them has read carefully. It goes wrong. Before
/// this, the only trace of *why* was the message on the tile, which is one
/// line with no request in it and no history: a metric that failed an hour
/// ago and works now left nothing behind at all.
///
/// So every run appends a block: what was asked for, what each metric
/// answered, which hosts were called and what they returned, and anything the
/// connector itself passed to `ctx.log`. That is the thing you paste back
/// into an agent to get the connector fixed, which is why the format is plain
/// text and not a structured log nobody can read without a tool.
///
/// Separate from `plugins/<id>.log`, which holds raw stderr for the older
/// single-metric format. This one is a record of *runs*, and stderr is only
/// one of the things in it.
public enum ConnectorLog {
    /// Bounded, because an app refreshing every five minutes writes forever
    /// on a machine whose owner never asked for a log.
    static let maxLines = 2_000

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        // UTC and a fixed locale: these get compared against a provider's own
        // logs, which are always UTC, and pasted between machines.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    public static func url(for id: String) -> URL {
        AppPaths.connectorLogs.appendingPathComponent("\(id).log")
    }

    /// What one run is worth recording.
    public struct Run: Sendable {
        public let verb: String
        public let requested: [String]
        public let durationMs: Double?
        public let outcomes: [String]
        public let httpCalls: [String]
        public let connectorLogs: [String]
        public let stderr: String
        public let failure: String?

        public init(
            verb: String, requested: [String], durationMs: Double? = nil,
            outcomes: [String] = [], httpCalls: [String] = [], connectorLogs: [String] = [],
            stderr: String = "", failure: String? = nil
        ) {
            self.verb = verb
            self.requested = requested
            self.durationMs = durationMs
            self.outcomes = outcomes
            self.httpCalls = httpCalls
            self.connectorLogs = connectorLogs
            self.stderr = stderr
            self.failure = failure
        }
    }

    public static func append(id: String, run: Run) {
        var lines: [String] = []
        let header = [
            stamp.string(from: Date()),
            run.verb,
            run.requested.isEmpty ? nil : run.requested.joined(separator: ", "),
            run.durationMs.map { "\(Int($0))ms" },
        ].compactMap { $0 }.joined(separator: "  ")
        lines.append("=== \(header)")

        if let failure = run.failure { lines.append("  run failed: \(failure)") }
        for outcome in run.outcomes { lines.append("  \(outcome)") }
        // The requests, with their status. A 401 here and a working tile
        // beside it is the shape of a scope problem, and neither line says
        // that on its own.
        for call in run.httpCalls { lines.append("  http \(call)") }
        for message in run.connectorLogs { lines.append("  log \(message)") }

        let errorText = run.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !errorText.isEmpty {
            for line in errorText.split(separator: "\n") { lines.append("  stderr \(line)") }
        }

        write(id: id, lines: lines)
    }

    private static func write(id: String, lines: [String]) {
        let url = url(for: id)
        try? FileManager.default.createDirectory(
            at: AppPaths.connectorLogs, withIntermediateDirectories: true)

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        // Rewritten whole rather than appended, so the cap is applied on every
        // write. An append-only file with a trim that runs "sometimes" is a
        // file that is over its cap most of the time.
        let kept = (existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            + lines)
            .suffix(maxLines)
        try? kept.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Whether there is anything to open. The menu item is disabled without
    /// it, because a Finder window onto a file that does not exist is worse
    /// than a greyed-out item.
    public static func exists(id: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }
}
