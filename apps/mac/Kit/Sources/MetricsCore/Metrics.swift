import Foundation

/// The normalised metric shape, decoded from the Worker and from local plugins.
///
/// Hand-written rather than generated. Generating these from the zod schemas
/// means a Node step inside the Xcode build, so the app could not be built
/// without the monorepo installed — a real cost on every CI run and every new
/// machine, to avoid a few dozen lines that change rarely.
///
/// Drift is caught instead by `ContractTests`, which decodes every committed
/// `contracts/fixtures/*.json`. A renamed field fails there, by name.
public enum MetricUnit: String, Codable, Sendable, CaseIterable {
    case currency, count, ratio, duration, bytes

    /// Unknown values decode to `.count` rather than failing.
    ///
    /// This is what actually buys "add a provider without shipping the app". A
    /// strict enum would make one unfamiliar value fail the decode of the whole
    /// response, so a Worker that started sending a new unit would break every
    /// installed copy at once.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MetricUnit(rawValue: raw) ?? .count
    }
}

public enum Granularity: String, Codable, Sendable {
    case hour, day, week, month

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Granularity(rawValue: raw) ?? .day
    }
}

public enum TimeRange: String, Codable, Sendable, CaseIterable {
    case day = "24h"
    case week = "7d"
    case month = "30d"
    case quarter = "90d"
    case year = "12m"

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TimeRange(rawValue: raw) ?? .month
    }

    /// The bucket the server will choose for this range.
    ///
    /// Mirrors `DEFAULT_GRANULARITY` in `packages/schemas`. A widget sends a
    /// range and no granularity, so the two are the same choice made twice —
    /// which is what lets a metric's declared `granularities` say which
    /// ranges it can actually answer for.
    ///
    /// Duplicated rather than fetched because it decides what the configure
    /// pane may offer, and a pane that cannot lay out its own picker until
    /// the network answers is worse than one constant kept in step.
    public var defaultGranularity: Granularity {
        switch self {
        case .day: .hour
        case .week, .month: .day
        case .quarter: .week
        case .year: .month
        }
    }

    /// How long the range is, for the one caller that has to say so itself.
    ///
    /// Mirrors `RANGE_DURATION_MS` in `packages/schemas`, and exists for the
    /// same reason `defaultGranularity` does: a widget normally sends a range
    /// and lets the server derive the window, so the Mac never needed this.
    /// A **local** metric has no server to derive anything — whoever runs the
    /// plugin must hand it a `from` and a `to`, and they have to be the same
    /// window the Worker would have chosen or the two paths disagree about
    /// what "30d" means.
    ///
    /// `.year` is 365 days, not twelve calendar months, exactly as the table
    /// in `packages/schemas` has it. Approximating it differently here would
    /// be a day's drift that only shows up at the end of February.
    public var duration: TimeInterval {
        let day: TimeInterval = 24 * 60 * 60
        switch self {
        case .day: return day
        case .week: return 7 * day
        case .month: return 30 * day
        case .quarter: return 90 * day
        case .year: return 365 * day
        }
    }

    public var label: String {
        switch self {
        case .day: "24 hours"
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        case .year: "12 months"
        }
    }
}

public struct MetricPoint: Codable, Sendable, Hashable {
    /// ISO-8601 at the start of the bucket.
    public let t: String
    public let v: Double

    public init(t: String, v: Double) {
        self.t = t
        self.v = v
    }

    public var date: Date? { ISO8601.parse(t) }
}

public struct MetricFormat: Codable, Sendable, Hashable {
    public let decimals: Int
    public let compact: Bool
    public let prefix: String
    public let suffix: String

    public init(decimals: Int = 0, compact: Bool = true, prefix: String = "", suffix: String = "") {
        self.decimals = decimals
        self.compact = compact
        self.prefix = prefix
        self.suffix = suffix
    }
}

public struct MetricDelta: Codable, Sendable, Hashable {
    public let absolute: Double
    /// Null when the previous window was zero — 0 → 5 has no percentage.
    public let percent: Double?

    // A struct's memberwise initialiser is internal however public its
    // properties are, so without this the type is decode-only outside this
    // module.
    public init(absolute: Double, percent: Double?) {
        self.absolute = absolute
        self.percent = percent
    }
}

/// One row of a list widget. Mirrors `MetricListItem` in `packages/schemas`.
/// What a list row's outcome was, where it has one.
///
/// The adapter's collapsing of the provider's own vocabulary — GitHub alone
/// has nine words for how a workflow run ended. Matching on those here would
/// mean an app release every time one was added; this is four cases that can
/// be drawn, and `unknown` for a fifth nobody has thought of yet.
public enum MetricListItemState: String, Codable, Sendable, Hashable {
    case succeeded
    case failed
    case running
    case neutral
    /// Anything the server starts sending that this build predates.
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MetricListItemState(rawValue: raw) ?? .unknown
    }
}

public struct MetricListItem: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// ISO-8601 instant the row happened at.
    public let t: String
    public let label: String
    public let detail: String?
    /// Minor units of `currency`; nil for a row with no amount.
    public let amount: Double?
    public let currency: String?
    public let status: String?
    /// `status` collapsed to something the tile can draw. Nil for a row with
    /// no outcome — a payment is not pass or fail, it just happened.
    public let state: MetricListItemState?

    public init(
        id: String, t: String, label: String, detail: String? = nil, amount: Double? = nil,
        currency: String? = nil, status: String? = nil, state: MetricListItemState? = nil
    ) {
        self.id = id
        self.t = t
        self.label = label
        self.detail = detail
        self.amount = amount
        self.currency = currency
        self.status = status
        self.state = state
    }

    public var date: Date? { ISO8601.parse(t) }
}

public struct MetricSeries: Codable, Sendable, Hashable {
    public let integrationId: String?
    public let metric: String
    public let unit: MetricUnit
    public let currency: String?
    /// Minor units when `unit` is `.currency`. Never a fractional amount.
    public let value: Double
    public let previousValue: Double?
    public let delta: MetricDelta?
    public let points: [MetricPoint]
    public let granularity: Granularity
    public let range: TimeRange
    public let from: String
    public let to: String
    public let format: MetricFormat?
    public let generatedAt: String
    public let stale: Bool
    /// Rows, for a list metric. Nil for a number — and nil, not empty, for
    /// a response from a Worker that predates lists, so the tile can tell
    /// "nothing yet" from "not a list".
    public let items: [MetricListItem]?

    public init(
        integrationId: String?, metric: String, unit: MetricUnit, currency: String?,
        value: Double, previousValue: Double? = nil, delta: MetricDelta? = nil,
        points: [MetricPoint] = [], granularity: Granularity = .day, range: TimeRange = .month,
        from: String = "", to: String = "", format: MetricFormat? = nil,
        generatedAt: String = "", stale: Bool = false, items: [MetricListItem]? = nil
    ) {
        self.integrationId = integrationId
        self.metric = metric
        self.unit = unit
        self.currency = currency
        self.value = value
        self.previousValue = previousValue
        self.delta = delta
        self.points = points
        self.granularity = granularity
        self.range = range
        self.from = from
        self.to = to
        self.format = format
        self.generatedAt = generatedAt
        self.stale = stale
        self.items = items
    }
}

public enum MetricErrorCode: String, Codable, Sendable {
    case authFailed = "auth_failed"
    case rateLimited = "rate_limited"
    case providerDown = "provider_down"
    case unsupported
    case notFound = "not_found"
    case stale
    /// Anything the server starts sending that this build predates.
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MetricErrorCode(rawValue: raw) ?? .unknown
    }

    /// Three words at most. The notch has room for a glyph and a hint, and a
    /// full sentence belongs in Settings where it can be read.
    public var shortReason: String {
        switch self {
        case .authFailed: "Reconnect"
        case .rateLimited: "Rate limited"
        case .providerDown: "Unavailable"
        case .unsupported: "Not supported"
        case .notFound: "Missing"
        case .stale: "Out of date"
        case .unknown: "Error"
        }
    }
}

public struct MetricFailure: Codable, Sendable, Hashable {
    public let integrationId: String?
    public let metric: String
    public let code: MetricErrorCode
    public let message: String
    public let retryAfterSeconds: Int?

    public init(
        integrationId: String?, metric: String, code: MetricErrorCode,
        message: String, retryAfterSeconds: Int?
    ) {
        self.integrationId = integrationId
        self.metric = metric
        self.code = code
        self.message = message
        self.retryAfterSeconds = retryAfterSeconds
    }
}

/// A 200-carried result. `POST /v1/metrics/batch` returns one per request and
/// partial success is the normal case.
public enum MetricResult: Codable, Sendable, Hashable {
    case success(MetricSeries)
    case failure(MetricFailure)

    private enum Keys: String, CodingKey { case ok, series }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        if try container.decode(Bool.self, forKey: .ok) {
            self = .success(try container.decode(MetricSeries.self, forKey: .series))
        } else {
            self = .failure(try MetricFailure(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch self {
        case .success(let series):
            try container.encode(true, forKey: .ok)
            try container.encode(series, forKey: .series)
        case .failure(let failure):
            try container.encode(false, forKey: .ok)
            try failure.encode(to: encoder)
        }
    }

    public var series: MetricSeries? {
        if case .success(let series) = self { return series }
        return nil
    }
}

public struct MetricBatchResponse: Codable, Sendable {
    public let results: [MetricResult]
}

/// ISO-8601 parsing, without a shared mutable formatter.
///
/// `ISO8601DateFormatter` is a class with mutable configuration and is not
/// `Sendable`, so a `static let` of one is global shared mutable state that
/// strict concurrency rejects — correctly, since `formatOptions` could be
/// changed from anywhere. `Date.ISO8601FormatStyle` is a `Sendable` value type
/// and needs no shared instance at all.
public enum ISO8601 {
    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    /// Both forms are accepted. The Worker emits fractional seconds; a plugin
    /// author writing `"2026-10-05"` by hand does not, and rejecting their
    /// perfectly reasonable timestamp would be an unhelpful place to be strict.
    public static func parse(_ string: String) -> Date? {
        (try? withFraction.parse(string)) ?? (try? withoutFraction.parse(string))
    }

    public static func string(from date: Date) -> String {
        date.formatted(withFraction)
    }
}
