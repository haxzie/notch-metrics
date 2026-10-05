import Foundation
import MetricsCore

public struct PluginSecretDeclaration: Codable, Sendable, Hashable {
    public let key: String
    public let label: String
    public let help: String?
    public let required: Bool
}

/// Mirrors `packages/schemas/src/plugin.ts`. Kept in step by the contract
/// fixtures, which this decodes in `ContractTests`.
public struct PluginManifest: Codable, Sendable, Hashable, Identifiable {
    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let shortLabel: String
    public let description: String
    public let unit: MetricUnit
    public let currency: String?
    public let format: MetricFormat
    public let granularities: [Granularity]
    public let supportsSeries: Bool
    public let refreshIntervalSeconds: Int
    public let secrets: [PluginSecretDeclaration]
    public let allowedHosts: [String]
    public let timeoutMs: Int
    public let entry: String
    public let author: String?
    public let createdAt: String
    public let updatedAt: String

    /// The app floors this regardless of what the manifest asks for. A metric
    /// that wants to run every second is a metric that will get its API key
    /// rate-limited and drain a battery doing it.
    public var effectiveRefreshInterval: TimeInterval {
        max(60, TimeInterval(refreshIntervalSeconds))
    }
}

public struct PluginHttpCall: Codable, Sendable, Hashable {
    public let host: String
    public let method: String
    public let status: Int?
    public let ms: Double
    public let blocked: Bool
}

public struct PluginValue: Codable, Sendable, Hashable {
    public let value: Double
    public let unit: MetricUnit?
    public let currency: String?
    public let series: [MetricPoint]?
    public let previousValue: Double?
    public let asOf: String?
}

/// The runner's single line of stdout.
public enum PluginRunResult: Codable, Sendable {
    case success(value: PluginValue, durationMs: Double, httpCalls: [PluginHttpCall], logs: [String])
    case failure(code: PluginFailureCode, message: String, durationMs: Double, httpCalls: [PluginHttpCall], logs: [String])

    private enum Keys: String, CodingKey {
        case ok, result, code, message, durationMs, httpCalls, logs
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let httpCalls = try c.decodeIfPresent([PluginHttpCall].self, forKey: .httpCalls) ?? []
        let logs = try c.decodeIfPresent([String].self, forKey: .logs) ?? []
        let durationMs = try c.decodeIfPresent(Double.self, forKey: .durationMs) ?? 0

        if try c.decode(Bool.self, forKey: .ok) {
            self = .success(
                value: try c.decode(PluginValue.self, forKey: .result),
                durationMs: durationMs, httpCalls: httpCalls, logs: logs)
        } else {
            self = .failure(
                code: try c.decode(PluginFailureCode.self, forKey: .code),
                message: try c.decode(String.self, forKey: .message),
                durationMs: durationMs, httpCalls: httpCalls, logs: logs)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case let .success(value, durationMs, httpCalls, logs):
            try c.encode(true, forKey: .ok)
            try c.encode(value, forKey: .result)
            try c.encode(durationMs, forKey: .durationMs)
            try c.encode(httpCalls, forKey: .httpCalls)
            try c.encode(logs, forKey: .logs)
        case let .failure(code, message, durationMs, httpCalls, logs):
            try c.encode(false, forKey: .ok)
            try c.encode(code, forKey: .code)
            try c.encode(message, forKey: .message)
            try c.encode(durationMs, forKey: .durationMs)
            try c.encode(httpCalls, forKey: .httpCalls)
            try c.encode(logs, forKey: .logs)
        }
    }
}

public enum PluginFailureCode: String, Codable, Sendable {
    case manifest, entry, timeout, policy, runtime
    case badResult = "bad_result"
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PluginFailureCode(rawValue: raw) ?? .unknown
    }

    /// Compact enough for a notch tile.
    public var shortReason: String {
        switch self {
        case .manifest: "Bad manifest"
        case .entry: "No entry"
        case .timeout: "Timed out"
        case .policy: "Blocked"
        case .badResult: "Bad value"
        case .runtime, .unknown: "Failed"
        }
    }
}

/// Exit codes the runner uses, so the app can branch before parsing stdout.
public enum PluginExit {
    public static let ok: Int32 = 0
    public static let runtime: Int32 = 1
    public static let validation: Int32 = 2
    public static let timeout: Int32 = 3
    public static let policy: Int32 = 4
}
