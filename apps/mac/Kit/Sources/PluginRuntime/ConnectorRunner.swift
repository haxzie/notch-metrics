import Foundation
import MetricsCore

/// One metric's answer from a connector run.
///
/// Mirrors `LocalMetricOutcome` in `@notchmetrics/core`. A list rather than a
/// single result because a connector run asks for several metrics at once:
/// one broken endpoint must fail its own tile and leave the others alone.
public enum ConnectorMetricOutcome: Sendable {
    case success(id: String, metric: String, result: ConnectorMetricValue)
    case failure(id: String, metric: String, code: PluginFailureCode, message: String)

    /// Which request this answers — the widget's own id.
    ///
    /// The only thing that tells two answers apart when both are for the same
    /// metric, which is what two tiles on one metric with different params
    /// are. `metric` is identical for both.
    public var id: String {
        switch self {
        case let .success(id, _, _), let .failure(id, _, _, _): id
        }
    }

    public var metric: String {
        switch self {
        case let .success(_, metric, _), let .failure(_, metric, _, _): metric
        }
    }
}

extension ConnectorMetricOutcome: Codable {
    private enum Keys: String, CodingKey { case ok, id, metric, result, code, message }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let metric = try c.decode(String.self, forKey: .metric)
        // Defaulted to the metric id for a runner that predates the field, so
        // a single-widget run still matches. Two widgets on one metric would
        // collide there — but that runner could not have told them apart
        // anyway, and the app ships its own.
        let id = try c.decodeIfPresent(String.self, forKey: .id) ?? metric
        if try c.decode(Bool.self, forKey: .ok) {
            self = .success(
                id: id, metric: metric,
                result: try c.decode(ConnectorMetricValue.self, forKey: .result))
        } else {
            self = .failure(
                id: id, metric: metric,
                code: try c.decode(PluginFailureCode.self, forKey: .code),
                message: try c.decode(String.self, forKey: .message))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id)
        try c.encode(metric, forKey: .metric)
        switch self {
        case let .success(_, _, result):
            try c.encode(true, forKey: .ok)
            try c.encode(result, forKey: .result)
        case let .failure(_, _, code, message):
            try c.encode(false, forKey: .ok)
            try c.encode(code, forKey: .code)
            try c.encode(message, forKey: .message)
        }
    }
}

/// What one metric returned. Mirrors `LocalMetricResult`.
public struct ConnectorMetricValue: Codable, Sendable, Hashable {
    public let value: Double
    public let previousValue: Double?
    public let points: [MetricPoint]
    public let items: [MetricListItem]?
    public let currency: String?
    public let note: String?
    public let asOf: String?

    public init(
        value: Double, previousValue: Double? = nil, points: [MetricPoint] = [],
        items: [MetricListItem]? = nil, currency: String? = nil, note: String? = nil,
        asOf: String? = nil
    ) {
        self.value = value
        self.previousValue = previousValue
        self.points = points
        self.items = items
        self.currency = currency
        self.note = note
        self.asOf = asOf
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decode(Double.self, forKey: .value)
        previousValue = try c.decodeIfPresent(Double.self, forKey: .previousValue)
        // Defaulted rather than required: the schema fills these in, but a
        // result decoded from an older runner must not fail the whole run.
        points = try c.decodeIfPresent([MetricPoint].self, forKey: .points) ?? []
        items = try c.decodeIfPresent([MetricListItem].self, forKey: .items)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        asOf = try c.decodeIfPresent(String.self, forKey: .asOf)
    }
}

/// The runner's single line of stdout for a connector run.
public struct ConnectorRunResult: Codable, Sendable {
    public let ok: Bool
    public let outcomes: [ConnectorMetricOutcome]
    public let durationMs: Double
    public let httpCalls: [PluginHttpCall]
    public let logs: [String]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decode(Bool.self, forKey: .ok)
        outcomes = try c.decode([ConnectorMetricOutcome].self, forKey: .outcomes)
        durationMs = try c.decodeIfPresent(Double.self, forKey: .durationMs) ?? 0
        httpCalls = try c.decodeIfPresent([PluginHttpCall].self, forKey: .httpCalls) ?? []
        logs = try c.decodeIfPresent([String].self, forKey: .logs) ?? []
    }
}

/// What the app asks a connector for. Mirrors `MetricRequest`.
public struct ConnectorMetricRequest: Codable, Sendable {
    /// The widget this is for. Echoed back on the outcome, and the only thing
    /// that distinguishes two requests for the same metric.
    public let id: String
    public let metric: String
    public let params: [String: String]
    public let range: String
    public let granularity: String
    public let from: String
    public let to: String
    public let comparePrevious: Bool

    public init(
        id: String, metric: String, window: PluginWindow, params: [String: String] = [:]
    ) {
        self.id = id
        self.metric = metric
        self.params = params
        self.range = window.range.rawValue
        self.granularity = window.granularity.rawValue
        self.from = ISO8601.string(from: window.from)
        self.to = ISO8601.string(from: window.to)
        self.comparePrevious = true
    }
}

/// Runs a custom app: one process, every metric asked for.
///
/// This is the difference between the connector format being light and being
/// a fork bomb. Six tiles from one app used to mean six Node launches per
/// tick, each re-reading the credential and re-paying start-up; here it is one
/// launch that answers all six, mirroring what `/v1/metrics/batch` does
/// server-side.
public struct ConnectorRunner: Sendable {
    private let tools: RunnerTools
    private let secrets: any SecretStore

    public init(
        secrets: any SecretStore,
        node: URL? = nil,
        script: URL? = nil,
        fileExists: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) throws {
        self.secrets = secrets
        self.tools = try RunnerTools(node: node, script: script, fileExists: fileExists)
    }

    /// Reads the credentials the manifest declares, and only those.
    ///
    /// Keyed by `.plugin(connectorId, key)` — the same Keychain naming the
    /// single-metric path uses, which is what the MCP server writes. A
    /// credential the manifest does not declare is never read, so a value left
    /// behind by an earlier version of the app is not quietly handed over.
    private func credentials(for connector: LoadedConnector) -> [String: String] {
        guard let manifest = connector.manifest else { return [:] }
        var declared: [String: String] = [:]
        for field in manifest.auth {
            if let value = try? secrets.string(for: .plugin(connector.id, field.key)) {
                declared[field.key] = value
            }
        }
        // Credentials the app holds, for apps that named them. Added under the
        // credential's own key, so the connector reads
        // `ctx.credentials.claude_code_oauth` exactly as it reads one the user
        // typed — it never learns which came from where.
        for credential in manifest.supportedHostCredentials {
            if case let .value(token) = HostCredentials.lookup(credential) {
                declared[credential.rawValue] = token
            }
        }
        return declared
    }

    /// Why a declared host credential is unusable, if any is.
    ///
    /// Checked before the run rather than after: an app whose token has
    /// expired fails every metric with the same reason, and that reason is
    /// something the user can act on, where "runtime error" from inside the
    /// connector is not.
    public func hostCredentialProblem(_ connector: LoadedConnector) -> String? {
        guard let manifest = connector.manifest else { return nil }
        for credential in manifest.supportedHostCredentials {
            if let reason = HostCredentials.lookup(credential).tileReason { return reason }
        }
        return nil
    }

    /// Asks one connector for several metrics.
    public func run(
        _ connector: LoadedConnector, metrics: [ConnectorMetricRequest]
    ) async throws -> [ConnectorMetricOutcome] {
        guard let manifest = connector.manifest else {
            throw PluginRunnerError.failed(.manifest, "This app has no usable manifest.")
        }
        guard !metrics.isEmpty else { return [] }

        let payload = RunInput(credentials: credentials(for: connector), requests: metrics)
        let output = try await RunnerProcess.run(
            tools: tools,
            arguments: ["fetch", "--dir", connector.directory.path],
            workingDirectory: connector.directory,
            input: try JSONEncoder().encode(payload),
            // The manifest's timeout is per connector, not per metric, and the
            // runner applies it to the batch. Two seconds of grace so it gets
            // to report its own deadline before the watchdog kills it.
            killAfter: Double(manifest.timeoutMs) / 1000 + 2.0)

        RunnerProcess.appendLog(id: connector.id, stderr: output.stderr)

        let requested = metrics.map(\.metric)

        if output.killed || output.status == PluginExit.timeout {
            ConnectorLog.append(
                id: connector.id,
                run: .init(
                    verb: "fetch", requested: requested, stderr: output.stderrText,
                    failure: "timed out after \(manifest.timeoutMs)ms"))
            throw PluginRunnerError.timedOut
        }

        guard let line = output.firstLine,
            let result = try? JSONDecoder().decode(ConnectorRunResult.self, from: Data(line.utf8))
        else {
            // The case the log earns its keep on: the runner printed
            // something that is not a result, so the tile can only say
            // "unreadable" while the reason is in stderr.
            ConnectorLog.append(
                id: connector.id,
                run: .init(
                    verb: "fetch", requested: requested, stderr: output.stderrText,
                    failure: "the runner printed no usable result"))
            throw PluginRunnerError.unreadableOutput(output.errorTail)
        }

        ConnectorLog.append(
            id: connector.id,
            run: .init(
                verb: "fetch", requested: requested, durationMs: result.durationMs,
                outcomes: result.outcomes.map(Self.describe),
                httpCalls: result.httpCalls.map(Self.describe),
                connectorLogs: result.logs, stderr: output.stderrText))

        return result.outcomes
    }

    /// One outcome as a line. The failure message is the point of it, so it
    /// is never truncated.
    static func describe(_ outcome: ConnectorMetricOutcome) -> String {
        switch outcome {
        case let .success(_, metric, value):
            let points = value.points.isEmpty ? "" : " points=\(value.points.count)"
            let rows = (value.items?.count).map { " rows=\($0)" } ?? ""
            return "ok \(metric) value=\(value.value)\(points)\(rows)"
        case let .failure(_, metric, code, message):
            return "failed \(metric) [\(code.rawValue)] \(message)"
        }
    }

    static func describe(_ call: PluginHttpCall) -> String {
        let status = call.status.map(String.init) ?? (call.blocked ? "blocked" : "no response")
        return "\(call.method) \(call.host) \(status) \(Int(call.ms))ms"
    }

    /// Runs `verify`, which is how a credential is checked before it is kept.
    public func verify(_ connector: LoadedConnector) async throws -> ConnectorVerifyResult {
        guard let manifest = connector.manifest else {
            throw PluginRunnerError.failed(.manifest, "This app has no usable manifest.")
        }

        let payload = RunInput(credentials: credentials(for: connector), requests: [])
        let output = try await RunnerProcess.run(
            tools: tools,
            arguments: ["connect", "--dir", connector.directory.path],
            workingDirectory: connector.directory,
            input: try JSONEncoder().encode(payload),
            killAfter: Double(manifest.timeoutMs) / 1000 + 2.0)

        RunnerProcess.appendLog(id: connector.id, stderr: output.stderr)

        if output.killed {
            ConnectorLog.append(
                id: connector.id,
                run: .init(
                    verb: "connect", requested: [], stderr: output.stderrText,
                    failure: "timed out after \(manifest.timeoutMs)ms"))
            throw PluginRunnerError.timedOut
        }
        guard let line = output.firstLine,
            let result = try? JSONDecoder().decode(
                ConnectorVerifyResult.self, from: Data(line.utf8))
        else {
            ConnectorLog.append(
                id: connector.id,
                run: .init(
                    verb: "connect", requested: [], stderr: output.stderrText,
                    failure: "the runner printed no usable result"))
            throw PluginRunnerError.unreadableOutput(output.errorTail)
        }

        // Logged on success too. "The key verified an hour ago and does not
        // now" is a question the tile cannot answer and the file can.
        ConnectorLog.append(
            id: connector.id,
            run: .init(
                verb: "connect", requested: [],
                outcomes: [
                    result.ok
                        ? "ok \(result.result?.accountLabel ?? "connected")"
                        : "failed \(result.message ?? "no reason given")"
                ],
                stderr: output.stderrText))
        return result
    }

    private struct RunInput: Encodable {
        let credentials: [String: String]
        let requests: [ConnectorMetricRequest]
    }
}

/// What `connect` answers. Mirrors the runner's verify envelope.
public struct ConnectorVerifyResult: Codable, Sendable {
    public let ok: Bool
    public let code: PluginFailureCode?
    public let message: String?
    public let result: Details?

    public struct Details: Codable, Sendable {
        public let accountLabel: String?
        public let currency: String?
        public let unavailableMetrics: [String]?
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decode(Bool.self, forKey: .ok)
        code = try c.decodeIfPresent(PluginFailureCode.self, forKey: .code)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        result = try c.decodeIfPresent(Details.self, forKey: .result)
    }
}
