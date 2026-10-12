import Foundation
import MetricsAPI
import MetricsCore

/// Deterministic notifications, for screenshots and for `NOTCH_DEBUG_ALERTS`.
///
/// Fixed strings and fixed offsets rather than anything seeded from a hash or
/// from `Date()`: a screenshot of this pane has to be byte-identical run to
/// run, or it is useless for spotting a layout regression. Same discipline as
/// `WidgetSample`.
enum AlertSample {
    /// Anchored to the start of today rather than to a fixed instant.
    ///
    /// A fixed epoch is stable forever but puts every sample row weeks in the
    /// past, so the "Today" and "Yesterday" grouping — the paths most worth
    /// looking at — were never exercised. This is identical for the whole of a
    /// day, which is as much determinism as a screenshot comparison needs.
    private static let base: Date = {
        let now = Date()
        return Calendar.current.startOfDay(for: now).addingTimeInterval(11 * 3_600)
    }()

    static let banner = make(
        id: "sample_banner",
        seq: 412,
        provider: "stripe",
        title: "Payment received",
        body: "Ada Lovelace · Pro · yearly",
        amount: 9_900,
        url: "https://dashboard.stripe.com/payments/ch_1",
        minutesAgo: 1)

    /// Twelve rows across three connections, spanning today, yesterday and
    /// last week, with one of each severity and one body long enough to need
    /// its second line truncated.
    static let feed: [NotchAlert] = [
        banner,
        make(
            id: "s2", seq: 411, provider: "stripe", title: "MRR crossed $10,000",
            body: nil, amount: nil, url: nil, minutesAgo: 95, severity: .info),
        make(
            id: "s3", seq: 410, provider: "github", title: "Issue opened",
            body: "Crash when the notch is dragged to a second display while a widget is mid-refresh",
            amount: nil, url: "https://github.com/haxzie/notch-metrics/issues/1",
            minutesAgo: 240, integrationId: "int_github"),
        make(
            id: "s4", seq: 409, provider: "stripe", title: "Payment received",
            body: "grace@example.com", amount: 5_000,
            url: "https://dashboard.stripe.com/payments/ch_2", minutesAgo: 400),
        make(
            id: "s5", seq: 408, provider: "polar", title: "Payment received",
            body: "Linus · Team seat", amount: 2_900, url: nil, minutesAgo: 1_500,
            integrationId: "int_polar"),
        make(
            id: "s6", seq: 407, provider: "stripe", title: "Stripe needs reconnecting",
            body: "The credentials were rejected. Reconnect to start the numbers again.",
            amount: nil, url: nil, minutesAgo: 1_600, severity: .warning, read: true),
        make(
            id: "s7", seq: 406, provider: "github", title: "Pull request opened",
            body: "Sweep every metric against every range it offers", amount: nil,
            url: nil, minutesAgo: 9_000, read: true, integrationId: "int_github"),
    ]

    static let connections: [AlertConnectionSummary] = [
        AlertConnectionSummary(
            integrationId: "int_stripe", provider: "stripe", label: "Acme Inc",
            unread: 3, total: 4),
        AlertConnectionSummary(
            integrationId: "int_github", provider: "github", label: "haxzie/notch-metrics",
            unread: 1, total: 2),
        // A connection with nothing to report still appears: the case a feed of
        // rows alone cannot express.
        AlertConnectionSummary(
            integrationId: "int_polar", provider: "polar", label: "Polar", unread: 1, total: 1),
    ]

    private static func make(
        id: String,
        seq: Int,
        provider: String,
        title: String,
        body: String?,
        amount: Int?,
        url: String?,
        minutesAgo: Int,
        severity: AlertSeverity = .success,
        read: Bool = false,
        integrationId: String = "int_stripe"
    ) -> NotchAlert {
        let at = base.addingTimeInterval(-Double(minutesAgo) * 60)
        return NotchAlert(
            id: id, seq: seq, integrationId: integrationId, provider: provider,
            connectionLabel: provider.capitalized, typeId: "payment_received",
            severity: severity, title: title, body: body, amount: amount,
            currency: amount == nil ? nil : "USD", url: url,
            occurredAt: ISO8601.string(from: at), createdAt: ISO8601.string(from: at),
            read: read, alert: true)
    }

    /// What the three sample connections can notify about.
    ///
    /// Demo mode never reaches the network, so without this the settings pane
    /// demos as three rows of "doesn't send notifications yet" — which is a
    /// true statement about a machine with no catalogue and a misleading one
    /// about the feature.
    static let definitions: [String: [AlertDefinition]] = [
        "stripe": [
            AlertDefinition(
                id: "payment_failed", kind: "event", label: "Failed payment",
                shortLabel: "Failed payment", severity: .warning,
                methodology:
                    "A charge Stripe declined, with the reason it gave. A charge that fails and "
                    + "is then retried successfully still arrives once, when it fails.",
                defaultEnabled: true, userConfigurable: true, minIntervalSeconds: 60),
            AlertDefinition(
                id: "payment_received", kind: "event", label: "New payment",
                shortLabel: "New payment", severity: .success,
                methodology:
                    "A charge that succeeded. One that fails and is later retried successfully "
                    + "arrives once, when it succeeds.",
                defaultEnabled: false, userConfigurable: true, minIntervalSeconds: 60),
            AlertDefinition(
                id: "refund_issued", kind: "event", label: "Refund issued",
                shortLabel: "Refund", severity: .info,
                methodology:
                    "A charge refunded in full or in part. The amount shown is what was "
                    + "refunded, not what was originally charged.",
                defaultEnabled: false, userConfigurable: true, minIntervalSeconds: 60),
            AlertDefinition(
                id: "metric_threshold_crossed", kind: "threshold",
                label: "MRR crosses a figure", shortLabel: "Threshold", severity: .info,
                methodology:
                    "Checked against the same monthly recurring revenue figure the tile shows, "
                    + "so it can be announced on a reading up to fifteen minutes old.",
                defaultEnabled: false, userConfigurable: true, minIntervalSeconds: 3600),
        ],
        "polar": [
            AlertDefinition(
                id: "payment_received", kind: "event", label: "New payment",
                shortLabel: "New payment", severity: .success,
                methodology: "An order that completed. Refunds are not announced here.",
                defaultEnabled: false, userConfigurable: true, minIntervalSeconds: 60)
        ],
    ]

    static let settings = AlertSettings(
        revision: 1,
        enabled: true,
        quietFromMinute: 22 * 60,
        quietToMinute: 8 * 60,
        subscriptions: [
            AlertSubscription(
                id: "nsub_1", integrationId: "int_stripe", typeId: "payment_failed",
                enabled: true, params: [:], threshold: nil, minIntervalSeconds: 60),
            AlertSubscription(
                id: "nsub_2", integrationId: "int_stripe", typeId: "payment_received",
                enabled: true, params: [:], threshold: nil, minIntervalSeconds: 60),
            AlertSubscription(
                id: "nsub_3", integrationId: "int_stripe", typeId: "refund_issued",
                enabled: false, params: [:], threshold: nil, minIntervalSeconds: 60),
            // Left unconfigured on purpose, so the "needs a figure" warning is
            // visible in the demo.
            AlertSubscription(
                id: "nsub_4", integrationId: "int_stripe", typeId: "metric_threshold_crossed",
                enabled: false, params: [:], threshold: nil, minIntervalSeconds: 3600),
            AlertSubscription(
                id: "nsub_5", integrationId: "int_polar", typeId: "payment_received",
                enabled: false, params: [:], threshold: nil, minIntervalSeconds: 60),
        ])

    /// The same three connections the sample feed names, as the Connections
    /// pane's model wants them.
    static let connectionsForDemo: [Integration] = [
        Integration(
            id: "int_stripe", provider: "stripe", label: "Acme Inc", status: "ok",
            credentialHint: "rk_live_…4f2a", accountLabel: "acct_1Nx · Acme Inc",
            accountCurrency: "USD", enabledMetrics: ["mrr", "revenue"],
            availableMetrics: ["mrr", "revenue", "recent_payments"],
            lastSyncedAt: nil, lastErrorAt: nil, lastErrorCode: nil,
            createdAt: "2026-09-01T12:00:00.000Z"),
        Integration(
            id: "int_github", provider: "github", label: "haxzie/notch-metrics",
            status: "ok", credentialHint: "gho_…8c21", accountLabel: "haxzie",
            accountCurrency: nil, enabledMetrics: ["stars"],
            availableMetrics: ["stars", "open_issues"],
            lastSyncedAt: nil, lastErrorAt: nil, lastErrorCode: nil,
            createdAt: "2026-09-04T12:00:00.000Z"),
        // Broken on purpose, so the reconnect affordance is visible beside the
        // notification one rather than only in a bug report.
        Integration(
            id: "int_polar", provider: "polar", label: "Polar", status: "auth_failed",
            credentialHint: "polar_…9df1", accountLabel: nil, accountCurrency: "USD",
            enabledMetrics: ["revenue"], availableMetrics: ["revenue", "recent_payments"],
            lastSyncedAt: nil, lastErrorAt: nil, lastErrorCode: "auth_failed",
            createdAt: "2026-09-08T12:00:00.000Z"),
    ]
}
