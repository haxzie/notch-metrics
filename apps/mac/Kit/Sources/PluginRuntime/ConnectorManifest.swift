import Foundation
import MetricsCore

/// A field the app renders — a credential on the connect sheet, or a
/// per-widget parameter in the configure pane.
///
/// Mirrors `AuthField` in `@notchmetrics/core`. `type` is an enum with an
/// `unknown` fallback rather than a set of booleans: an app meeting an
/// unfamiliar *type* can fall back to a text field, whereas one meeting an
/// unfamiliar *flag* would render a secret in plain sight.
public struct ConnectorAuthField: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case string, secret, select, url, boolean
        case unknown

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    public struct Option: Codable, Sendable, Hashable {
        public let value: String
        public let label: String
    }

    public let key: String
    public let label: String
    public let type: Kind
    public let required: Bool
    public let placeholder: String?
    public let help: String?
    public let pattern: String?
    public let options: [Option]?
    public let `default`: String?

    /// An unknown type is treated as a secret, not as plain text.
    ///
    /// The safe direction: showing a visible field masked is a cosmetic
    /// annoyance, while showing a masked field in the clear puts somebody's
    /// token on screen in a screen-share.
    public var isSecret: Bool { type == .secret || type == .unknown }
}

/// A credential the app holds and hands to a connector.
///
/// The narrow exception to "credentials come from the connect form": a token
/// already on the machine that rotates far too often to paste. An app receives
/// one only by naming it here, and the Settings row says which, so it is
/// visible rather than ambient.
public enum HostCredential: String, Codable, Sendable, Hashable {
    /// The Claude Code subscription OAuth token.
    case claudeCodeOAuth = "claude_code_oauth"
    /// A kind added after this build shipped. Decoded rather than refused, and
    /// never supplied — the app cannot hand over a credential it has no idea
    /// how to fetch.
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HostCredential(rawValue: raw) ?? .unknown
    }

    /// Named as the user would recognise it, not as the manifest spells it.
    public var displayName: String {
        switch self {
        case .claudeCodeOAuth: "your Claude Code sign-in"
        case .unknown: "an unknown credential"
        }
    }
}

/// How a custom app authenticates.
///
/// There is no OAuth arm and there will not be: a refresh needs a client
/// secret, and a client secret on a laptop is a published client secret.
public enum ConnectorAuthMode: String, Codable, Sendable, Hashable {
    /// A free or public API, or an app holding its own credential in its code.
    /// Nothing is asked of the user and no Keychain entry is read.
    case none
    /// The user supplies the fields the manifest declares — as a form in the
    /// app, never through a browser. A local app has no redirect URI.
    case apiKey = "api_key"
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ConnectorAuthMode(rawValue: raw) ?? .unknown
    }
}

/// What kind of metric this is — the same four arms the built-in providers use.
public enum ConnectorMetricShape: Sendable, Hashable {
    case scalar
    case series(granularities: [Granularity], compare: Bool)
    case total(granularities: [Granularity], compare: Bool)
    case list(limit: Int)
    /// A shape added after this app shipped.
    ///
    /// Kept rather than refused, so one unfamiliar metric does not invalidate
    /// the whole connector and take its other metrics down with it.
    case unknown(kind: String)

    /// Whether this metric's number depends on the widget's time window.
    ///
    /// Not the same question as `supportsSeries`, which is why the tile asks
    /// this one. A `total` draws no line and a `list` draws rows, but both are
    /// aggregates *of a window* — change the window and the number changes, so
    /// the window belongs in the title. Only a `scalar` is a reading taken
    /// now, and `unknown` is treated as one: a tile gaining a range it does
    /// not use is the worse mistake.
    public var usesTimeWindow: Bool {
        switch self {
        case .series, .total, .list: true
        case .scalar, .unknown: false
        }
    }

    public var kindName: String {
        switch self {
        case .scalar: "scalar"
        case .series: "series"
        case .total: "total"
        case .list: "list"
        case let .unknown(kind): kind
        }
    }
}

extension ConnectorMetricShape: Codable {
    private enum Keys: String, CodingKey { case kind, granularities, compare, limit }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        let granularities = try c.decodeIfPresent([Granularity].self, forKey: .granularities) ?? []
        let compare = try c.decodeIfPresent(Bool.self, forKey: .compare) ?? true
        switch kind {
        case "scalar": self = .scalar
        case "series": self = .series(granularities: granularities, compare: compare)
        case "total": self = .total(granularities: granularities, compare: compare)
        case "list": self = .list(limit: try c.decodeIfPresent(Int.self, forKey: .limit) ?? 10)
        default: self = .unknown(kind: kind)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(kindName, forKey: .kind)
        switch self {
        case .scalar, .unknown:
            break
        case let .series(granularities, compare), let .total(granularities, compare):
            try c.encode(granularities, forKey: .granularities)
            try c.encode(compare, forKey: .compare)
        case let .list(limit):
            try c.encode(limit, forKey: .limit)
        }
    }
}

/// One metric a connector offers.
public struct ConnectorMetricDescriptor: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let shortLabel: String
    public let unit: MetricUnit
    public let currency: String?
    public let format: MetricFormat?
    public let shape: ConnectorMetricShape
    /// How this number is derived, in one sentence.
    ///
    /// Required by the schema for the same reason it is required of a
    /// built-in: "MRR" is always somebody's definition, and the person
    /// reading the tile in six months is rarely the person who wrote it.
    public let methodology: String
    public let params: [ConnectorAuthField]?
    public let freshnessSeconds: Int?
    public let linkTemplate: String?
}

/// A **local connector**: one app, its credentials, and every metric it offers.
///
/// Mirrors `LocalConnectorManifest` in `@notchmetrics/core`, and is kept in
/// step by `contracts/fixtures/connector-manifest.json`, which the contract
/// tests decode. Hand-written rather than generated, so a renamed field fails
/// the Swift suite by name in CI rather than blanking a user's widgets at
/// launch.
///
/// This is the unit people actually have — *an account*, with several numbers
/// behind it — where a `PluginManifest` is a single metric carrying its own
/// copy of the same token.
public struct ConnectorManifest: Codable, Sendable, Hashable, Identifiable {
    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let description: String
    public let appId: String?
    public let author: String?
    /// The author's own version string. Displayed, never compared: the app
    /// does not upgrade a connector, so this exists only so a person can tell
    /// which build of their own code is installed.
    public let version: String?
    /// What the app looks like, as its manifest declares it.
    ///
    /// Declared inline — a symbol or an emoji — so an agent writing one JSON
    /// file can give its app an icon without producing artwork. The `file`
    /// arm is still there for a real logo.
    public let icon: CustomAppIcon?
    /// How this app authenticates, when it does at all.
    ///
    /// Decoded with an `unknown` fallback so a mode added later does not
    /// invalidate the manifest. Optional because it postdates the format, and
    /// `requiresCredentials` derives the answer from `auth` when it is absent.
    public let authMode: ConnectorAuthMode?
    public let auth: [ConnectorAuthField]
    /// Credentials the **app** supplies, named by the manifest.
    ///
    /// Optional on this side so a manifest written before the field existed
    /// still decodes, and each arm falls back to `unknown` rather than failing
    /// the app — an unfamiliar one simply is not supplied.
    public let hostCredentials: [HostCredential]?
    public let allowedHosts: [String]
    public let metrics: [ConnectorMetricDescriptor]
    public let refreshIntervalSeconds: Int
    public let timeoutMs: Int
    public let entry: String
    public let createdAt: String
    public let updatedAt: String

    /// Floored by the app regardless of what the manifest asks for. A
    /// connector that wants to run every second is one that will get its API
    /// key rate-limited and flatten a battery doing it.
    public var effectiveRefreshInterval: TimeInterval {
        max(60, TimeInterval(refreshIntervalSeconds))
    }

    public var displayVersion: String { version ?? "1.0.0" }

    /// Host credentials this app asks for, minus any this build cannot supply.
    public var supportedHostCredentials: [HostCredential] {
        (hostCredentials ?? []).filter { $0 != .unknown }
    }

    /// Whether this app asks the user for anything.
    ///
    /// The single question every credential surface asks. Derived rather than
    /// read straight off `authMode`, because a manifest written before that
    /// field existed says what it needs through `auth` alone — and because
    /// `unknown` must not be read as "needs nothing", which would hide a form
    /// the app was relying on.
    public var requiresCredentials: Bool {
        switch authMode {
        case .none?: false
        case .apiKey?: !auth.isEmpty
        case .unknown?, nil: !auth.isEmpty
        }
    }
}
