import Foundation

/// Notification models, decoded from the Worker.
///
/// Named `Alert*` rather than `Notification*` throughout, because `Notification`
/// is a Foundation struct and `NotificationCenter` is AppKit's — both are
/// already used in this app, and a type shadowing either produces an error at
/// the *use* site that points somewhere else entirely. The user-facing word is
/// still "notifications".
///
/// Hand-written, for the same reason as `Metrics.swift`: generating from the zod
/// schemas would put a Node step inside the Xcode build. Drift is caught by
/// `ContractTests`, which decodes the committed fixtures by name.
public enum AlertSeverity: String, Codable, Sendable, CaseIterable {
    case info, success, warning

    /// Unknown values decode to `.info` rather than failing.
    ///
    /// Same bargain as `MetricUnit`: a severity the server invents must not
    /// make the whole feed fail to decode and blank every notification at once.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AlertSeverity(rawValue: raw) ?? .info
    }
}

/// One delivered notification.
public struct NotchAlert: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    /// Per-user monotonic. **A cursor, not a sort key** — see `occurredAt`.
    public let seq: Int
    /// Null once the connection behind it has been removed. The row survives
    /// that on purpose, so `provider` and `connectionLabel` are carried on it.
    public let integrationId: String?
    public let provider: String
    public let connectionLabel: String
    /// A `NotificationTypeId`. A plain `String` with no enum: an unfamiliar type
    /// must render as a generic row, not fail the decode of the whole feed.
    public let typeId: String
    public let severity: AlertSeverity
    public let title: String
    public let body: String?
    /// Minor units of `currency`. Never a float.
    public let amount: Int?
    public let currency: String?
    /// Where clicking this goes. A plain `String`, because a URL the server
    /// sends that this app cannot parse must not fail the whole feed.
    public let url: String?
    /// When the thing happened. **The sort key.**
    public let occurredAt: String
    /// When the server found out. The gap is the latency the user feels.
    public let createdAt: String
    public let read: Bool
    /// False inside quiet hours: file it, do not raise a banner for it.
    public let alert: Bool

    public init(
        id: String,
        seq: Int,
        integrationId: String?,
        provider: String,
        connectionLabel: String,
        typeId: String,
        severity: AlertSeverity,
        title: String,
        body: String?,
        amount: Int?,
        currency: String?,
        url: String?,
        occurredAt: String,
        createdAt: String,
        read: Bool,
        alert: Bool
    ) {
        self.id = id
        self.seq = seq
        self.integrationId = integrationId
        self.provider = provider
        self.connectionLabel = connectionLabel
        self.typeId = typeId
        self.severity = severity
        self.title = title
        self.body = body
        self.amount = amount
        self.currency = currency
        self.url = url
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.read = read
        self.alert = alert
    }

    /// Parsed lazily. A feed of 200 rows does not need 200 `Date` allocations
    /// to be drawn.
    public var occurred: Date? { ISO8601.parse(occurredAt) }

    /// Only an `https` link is ever handed to `NSWorkspace`. The server already
    /// checks the host against the provider's allowlist; this is the second
    /// half of that, on the side that actually opens it.
    public var link: URL? {
        guard let url, let parsed = URL(string: url), parsed.scheme == "https" else { return nil }
        return parsed
    }
}

/// A row of the notification centre's sidebar.
///
/// Separate from the alerts themselves because a connection with nothing to
/// report still has to appear in the list — which a page of rows cannot say.
public struct AlertConnectionSummary: Codable, Sendable, Hashable, Identifiable {
    public let integrationId: String?
    public let provider: String
    public let label: String
    public let unread: Int
    public let total: Int

    public init(
        integrationId: String?, provider: String, label: String, unread: Int, total: Int
    ) {
        self.integrationId = integrationId
        self.provider = provider
        self.label = label
        self.unread = unread
        self.total = total
    }

    /// Stable even for the disconnected bucket, whose `integrationId` is null.
    public var id: String { integrationId ?? "__disconnected__" }
}

/// One page of the feed.
public struct AlertFeedPage: Codable, Sendable {
    /// The next `?since=`: the highest seq that exists, not the highest here.
    public let seq: Int
    public let unread: Int
    public let items: [NotchAlert]
    public let connections: [AlertConnectionSummary]
    /// Older rows exist; `?before=oldestSeq` fetches them.
    public let hasMore: Bool
    /// The next `?before=`. Null on an empty page — a client that treats it as
    /// zero re-requests the whole archive forever.
    public let oldestSeq: Int?
    /// The live-sync gap was too wide to banner row by row. Never set on a
    /// history page: scrolling back is not news.
    public let truncated: Bool
    /// The server's floor on how often to ask again.
    public let pollAfterSeconds: Int

    public init(
        seq: Int,
        unread: Int,
        items: [NotchAlert],
        connections: [AlertConnectionSummary],
        hasMore: Bool,
        oldestSeq: Int?,
        truncated: Bool,
        pollAfterSeconds: Int
    ) {
        self.seq = seq
        self.unread = unread
        self.items = items
        self.connections = connections
        self.hasMore = hasMore
        self.oldestSeq = oldestSeq
        self.truncated = truncated
        self.pollAfterSeconds = pollAfterSeconds
    }
}

/// The cheap poll's whole answer.
public struct AlertCursor: Codable, Sendable, Hashable {
    public let seq: Int
    public let unread: Int
    public let pollAfterSeconds: Int

    public init(seq: Int, unread: Int, pollAfterSeconds: Int) {
        self.seq = seq
        self.unread = unread
        self.pollAfterSeconds = pollAfterSeconds
    }
}

public struct AlertThreshold: Codable, Sendable, Hashable {
    public let metric: String
    public let comparator: String
    public let value: Double

    public init(metric: String, comparator: String, value: Double) {
        self.metric = metric
        self.comparator = comparator
        self.value = value
    }
}

/// One toggle: a notification type on a connection.
public struct AlertSubscription: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let integrationId: String
    public let typeId: String
    public var enabled: Bool
    public var params: [String: String]
    public var threshold: AlertThreshold?
    public var minIntervalSeconds: Int

    public init(
        id: String,
        integrationId: String,
        typeId: String,
        enabled: Bool,
        params: [String: String],
        threshold: AlertThreshold?,
        minIntervalSeconds: Int
    ) {
        self.id = id
        self.integrationId = integrationId
        self.typeId = typeId
        self.enabled = enabled
        self.params = params
        self.threshold = threshold
        self.minIntervalSeconds = minIntervalSeconds
    }
}

/// The toggles, as the server holds them.
///
/// Note the direction: unlike `WidgetLayout`, **the server is authoritative
/// here** and this is a cache. The server is the evaluator, so a muted type it
/// never generates is bytes never sent and a device wake never taken.
public struct AlertSettings: Codable, Sendable, Hashable {
    public var revision: Int
    public var enabled: Bool
    /// Local minutes from midnight. Minutes rather than a `Date`, or quiet
    /// hours silently move when the user changes timezone.
    public var quietFromMinute: Int?
    public var quietToMinute: Int?
    public var subscriptions: [AlertSubscription]

    public init(
        revision: Int,
        enabled: Bool,
        quietFromMinute: Int?,
        quietToMinute: Int?,
        subscriptions: [AlertSubscription]
    ) {
        self.revision = revision
        self.enabled = enabled
        self.quietFromMinute = quietFromMinute
        self.quietToMinute = quietToMinute
        self.subscriptions = subscriptions
    }
}

/// A notification type a provider declares, as it arrives in the catalogue.
///
/// Rendered at runtime, so a new provider's notifications ship without a Mac
/// release — the same property `MetricDescriptor` has.
public struct AlertDefinition: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: String
    public let label: String
    public let shortLabel: String
    public let severity: AlertSeverity
    /// What exactly makes this fire, rendered under the toggle.
    public let methodology: String
    public let defaultEnabled: Bool
    /// False for the things the product must always be able to say. The Mac
    /// renders a locked row rather than hiding it, so the user can still see
    /// what they will be told.
    public let userConfigurable: Bool
    public let minIntervalSeconds: Int

    public init(
        id: String,
        kind: String,
        label: String,
        shortLabel: String,
        severity: AlertSeverity,
        methodology: String,
        defaultEnabled: Bool,
        userConfigurable: Bool,
        minIntervalSeconds: Int
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.shortLabel = shortLabel
        self.severity = severity
        self.methodology = methodology
        self.defaultEnabled = defaultEnabled
        self.userConfigurable = userConfigurable
        self.minIntervalSeconds = minIntervalSeconds
    }

    public var isThreshold: Bool { kind == "threshold" }
}

/// Where the notification centre should open.
///
/// In `MetricsCore` so `NotchUI` can carry one without knowing what an alert
/// is, which is the same split `ShareRequest` uses.
public struct AlertFocus: Equatable, Sendable {
    public let integrationId: String?
    public let alertID: String?

    public init(integrationId: String?, alertID: String? = nil) {
        self.integrationId = integrationId
        self.alertID = alertID
    }
}
