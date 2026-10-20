import Foundation
import MetricsCore

// The request bodies and response shapes the app actually uses.

/// One metric, asked for.
///
/// `Equatable` so a refresh can ask whether the widget it is about to write an
/// answer onto is still asking the question that was sent. This is the whole
/// question — no field of a widget that changes the number is missing from
/// here — which is what makes that comparison trustworthy.
public struct MetricQueryRequest: Codable, Sendable, Equatable {
    public let integrationId: String
    public let metric: String
    public let granularity: String?
    public let range: String
    public let series: Bool
    /// The widget's own arguments — a GitHub repository, say. Part of the
    /// server's cache key, so two tiles on one connection stay distinct.
    public let params: [String: String]

    public init(widget: NotchWidget) {
        self.integrationId = widget.integrationId ?? ""
        self.metric = widget.metric ?? ""
        // Derived from the range, not read off the widget.
        //
        // `widget.granularity` is frozen when the widget is created — the
        // browser seeds it from `granularities.first` — and no control has
        // ever changed it, so it stayed whatever the metric happened to list
        // first while the range moved underneath it. For both LLM connectors
        // that is `hour`, so a 90-day tile asked for ninety days of hourly
        // buckets and the adapter refused a walk it would never finish.
        //
        // The server derives the same value from the range when none is
        // sent, and the configure pane filters the range picker on this
        // table too — three places agreeing is the point.
        self.granularity = widget.range.defaultGranularity.rawValue
        self.range = widget.range.rawValue
        // A tile with no chart does not need the series, and saying so lets
        // the adapter skip a page walk rather than computing data nobody draws.
        self.series = widget.chart != .none
        self.params = widget.params
    }
}

public struct MetricBatchBody: Codable, Sendable {
    public let requests: [MetricQueryRequest]
}

public struct ProviderManifestList: Codable, Sendable {
    public let version: String
    public let providers: [ProviderManifest]
}

public struct ConnectorOAuth: Codable, Sendable, Hashable {
    /// What the user is granting, in their language rather than the
    /// provider's scope strings.
    public let scopeSummary: [String]
    /// Whether authorising is enough, or whether they still have to pick a
    /// property, site or ad account afterwards.
    public let requiresSelection: Bool
    public let selectionLabel: String?
}

public struct ProviderManifest: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    /// "revenue" | "analytics" | "marketing" | "crm". A plain string with a
    /// fallback rather than an enum, so a category added on the server does
    /// not make the whole catalogue fail to decode.
    public let category: String
    public let tagline: String
    public let docsUrl: String
    /// The provider's own app, for a tile that is clicked. Optional: a
    /// provider with no web app has nowhere to send anybody.
    public let dashboardUrl: String?
    public let iconPath: String
    public let accentColor: String
    /// Search synonyms. Optional on the wire: a non-optional array would
    /// make an older server's response fail to decode entirely, which is the
    /// failure this codebase goes out of its way to avoid.
    public let keywords: [String]?
    public let authMode: String
    /// Present only when `authMode` is "oauth2".
    public let oauth: ConnectorOAuth?
    public let fields: [AuthField]
    public let metrics: [MetricDescriptor]
    public let allowedHosts: [String]
    public let status: String
    public let minAppVersion: String

    /// Whether this build can render the provider's credentials form at all.
    ///
    /// The whole point of serving manifests is shipping a provider with no app
    /// release — but a provider needing a field type this build has never heard
    /// of cannot be rendered, and a half-drawn form submits a credential set
    /// the adapter will reject. Better to offer an update.
    public var isConnectable: Bool { status != "coming_soon" }
    public var needsOAuth: Bool { authMode == "oauth2" }

    public func isRenderable(by appVersion: String) -> Bool {
        guard let required = SemanticVersion(minAppVersion),
              let current = SemanticVersion(appVersion)
        else { return true }
        return current >= required
    }
}

public struct AuthField: Codable, Sendable, Hashable {
    public let key: String
    public let label: String
    public let type: String
    public let required: Bool
    public let placeholder: String?
    public let help: String?
    public let pattern: String?
    public let options: [AuthFieldOption]?
    public let `default`: String?

    /// An unknown field type falls back to a plain text field.
    ///
    /// This is what makes `type` an enum rather than a `masked: true` flag: an
    /// unfamiliar type still renders something usable, where an unfamiliar flag
    /// would render a secret in plain text.
    public var isSecret: Bool { type == "secret" }
}

public struct AuthFieldOption: Codable, Sendable, Hashable {
    public let value: String
    public let label: String
}

public struct MetricDescriptor: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    public let shortLabel: String
    public let unit: MetricUnit
    public let granularities: [Granularity]
    public let supportsSeries: Bool
    public let supportsCompare: Bool
    /// Search synonyms. Optional on the wire: a non-optional array would
    /// make an older server's response fail to decode entirely, which is the
    /// failure this codebase goes out of its way to avoid.
    public let keywords: [String]?
    public let help: String?
    /// Fields the *widget* supplies, rendered in the configure pane.
    ///
    /// Declared per metric because they differ within one connector: GitHub's
    /// stars need a repository and its followers do not. Optional on the wire
    /// so an older server's catalogue still decodes.
    public let params: [AuthField]?
    /// Always present. "MRR" is somebody's definition and this is ours.
    public let methodology: String
    /// Where this number lives in the provider's app, with `{param}`
    /// placeholders the widget's own parameters fill. Optional on the wire:
    /// most metrics have no page of their own and fall back to the
    /// connector's `dashboardUrl`. See `WidgetLink`.
    public let linkTemplate: String?
}

public struct Integration: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let provider: String
    public let label: String
    public let status: String
    public let credentialHint: String
    public let accountLabel: String?
    public let accountCurrency: String?
    public let enabledMetrics: [String]
    public let availableMetrics: [String]
    public let lastSyncedAt: String?
    public let lastErrorAt: String?
    public let lastErrorCode: String?
    public let createdAt: String

    /// Explicit, because the memberwise one is internal to this module and the
    /// app target builds these for demo mode and for tests.
    public init(
        id: String,
        provider: String,
        label: String,
        status: String,
        credentialHint: String,
        accountLabel: String?,
        accountCurrency: String?,
        enabledMetrics: [String],
        availableMetrics: [String],
        lastSyncedAt: String?,
        lastErrorAt: String?,
        lastErrorCode: String?,
        createdAt: String
    ) {
        self.id = id
        self.provider = provider
        self.label = label
        self.status = status
        self.credentialHint = credentialHint
        self.accountLabel = accountLabel
        self.accountCurrency = accountCurrency
        self.enabledMetrics = enabledMetrics
        self.availableMetrics = availableMetrics
        self.lastSyncedAt = lastSyncedAt
        self.lastErrorAt = lastErrorAt
        self.lastErrorCode = lastErrorCode
        self.createdAt = createdAt
    }
}

public struct BillingState: Codable, Sendable, Hashable {
    public let plan: String
    public let status: String
    public let trialEndsAt: String?
    public let currentPeriodEnd: String?
    public let graceUntil: String?
    public let cancelAtPeriodEnd: Bool
    public let hasCustomer: Bool
}

public struct AccountUser: Codable, Sendable, Hashable {
    public let id: String
    public let name: String?
    public let email: String
    public let image: String?
    public let timezone: String
    public let preferredCurrency: String
    public let createdAt: String
}

public struct MeResponse: Codable, Sendable {
    public let user: AccountUser
    public let billing: BillingState
    public let counts: Counts

    public struct Counts: Codable, Sendable {
        public let integrations: Int
        public let widgets: Int
    }
}

public struct DesktopTokenResponse: Codable, Sendable {
    public let token: String
    public let user: AccountUser
    public let billing: BillingState
}

public struct WidgetLayoutResponse: Codable, Sendable {
    public let revision: Int
    public let widgets: [NotchWidget]
}

/// `GET /v1/connectors` — everything the app can connect to, grouped.
///
/// The settings UI renders from this rather than from anything compiled in,
/// which is the property that lets a connector ship without a Mac release.
public struct ConnectorCatalogue: Codable, Sendable {
    public let version: String
    public let categories: [ConnectorCategoryGroup]

    public var allConnectors: [ConnectorEntry] { categories.flatMap(\.connectors) }
}

public struct ConnectorCategoryGroup: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let label: String
    public let connectors: [ConnectorEntry]

    // A struct's memberwise initialiser is internal however public its
    // properties are, so without this a caller outside this module can decode
    // a group but not build one — which is what filtering a category down to
    // the connectors worth showing amounts to.
    public init(id: String, label: String, connectors: [ConnectorEntry]) {
        self.id = id
        self.label = label
        self.connectors = connectors
    }
}

public struct ConnectorEntry: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let category: String
    public let tagline: String
    public let docsUrl: String
    /// The provider's own app, for a tile that is clicked. Optional: a
    /// provider with no web app has nowhere to send anybody.
    public let dashboardUrl: String?
    public let accentColor: String
    /// Search synonyms. Optional on the wire: a non-optional array would
    /// make an older server's response fail to decode entirely, which is the
    /// failure this codebase goes out of its way to avoid.
    public let keywords: [String]?
    public let authMode: String
    public let oauth: ConnectorOAuth?
    public let fields: [AuthField]
    public let metrics: [MetricDescriptor]
    /// What this connector can notify about.
    ///
    /// Optional on the wire, like `keywords` and for the same reason: a
    /// connector that notifies about nothing omits the key, and an older server
    /// that has never heard of the field must not fail the decode of the whole
    /// catalogue and blank every widget.
    public let notifications: [AlertDefinition]?
    public let status: String
    public let minAppVersion: String
    /// Accounts the signed-in user has already connected for this connector.
    /// Empty when signed out — the catalogue is readable either way.
    public let connections: [ConnectorConnection]

    public var isConnectable: Bool { status != "coming_soon" }
    public var isConnected: Bool { !connections.isEmpty }
}

public struct ConnectorConnection: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let label: String
    public let status: String

    public var needsAttention: Bool { status == "auth_failed" }
}
