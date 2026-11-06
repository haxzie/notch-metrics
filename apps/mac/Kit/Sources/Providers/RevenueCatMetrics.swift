import Foundation
import MetricsCore

/// RevenueCat's metrics, read on this Mac.
///
/// Ported from `packages/integrations/src/providers/revenuecat/index.ts`. The
/// arithmetic is deliberately the same arithmetic, down to the minor-unit
/// exponent and which currencies are asked for — a widget must not change its
/// number because the fetch moved off the Worker.
///
/// Five of the six metrics are cards off RevenueCat's own Overview, which is
/// a fixed set of figures it has already computed. A window is meaningless
/// for those: the snapshots are "now" and the 28-day cards are 28 days
/// whatever the widget asked for, and the manifest's methodology strings say
/// so. Only `revenue` takes a window, and only it compares.
extension RevenueCatProvider {
    /// The currencies RevenueCat will report in.
    ///
    /// Anything else is a 400, so the request omits the parameter and falls
    /// back to the project's default — and the response says which currency
    /// it actually used, which is what the note on the answer repeats.
    static let reportingCurrencies: Set<String> = [
        "USD", "EUR", "GBP", "AUD", "CAD", "JPY", "BRL",
        "KRW", "CNY", "MXN", "SEK", "PLN", "NZD", "CHF",
    ]

    /// Whether a card is money or a headcount. The Overview mixes both.
    enum Unit: Sendable {
        case currency
        case count
    }

    /// Which Overview card backs each widget, and what kind of figure it is.
    ///
    /// One table rather than a `case` per metric with the card id inline: the
    /// widget ids and RevenueCat's card ids differ for three of the five
    /// (`active_subscribers` reads `active_subscriptions`), and that mapping
    /// is the part a port transcribes wrongly.
    static let overviewCards: [String: (card: String, unit: Unit)] = [
        "mrr": ("mrr", .currency),
        "active_subscribers": ("active_subscriptions", .count),
        "trials": ("active_trials", .count),
        "new_users": ("new_customers", .count),
        "active_users": ("active_users", .count),
    ]

    public func fetch(
        _ credentials: [String: String], window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let creds = try Credentials(credentials)

        if let card = Self.overviewCards[window.metric] {
            let projectId = try await projectId(creds: creds, http: http)
            let body = try await overview(
                creds: creds, projectId: projectId, http: http,
                preferredCurrency: window.preferredCurrency)
            return try Self.value(
                from: body, card: card.card, unit: card.unit,
                preferredCurrency: window.preferredCurrency)
        }

        if window.metric == "revenue" {
            let projectId = try await projectId(creds: creds, http: http)
            return try await revenueTotal(
                creds: creds, projectId: projectId, window: window, http: http)
        }

        // Not a bug: the catalogue is the Worker's and lists metrics this
        // build has not been taught yet. The caller falls back to the API.
        throw ProviderFailure.unsupported(
            "This build cannot read RevenueCat's \(window.metric) yet.")
    }

    // MARK: - Metrics

    /// One card off the Overview, as a figure the tile can draw.
    ///
    /// Pure, and separate from the request for that reason: the conversion
    /// and the missing-card case are what a port gets wrong, and both are
    /// testable here without a stubbed session.
    static func value(
        from overview: Overview, card: String, unit: Unit, preferredCurrency: String
    ) throws -> MetricValue {
        guard let metric = overview.metrics?.first(where: { $0.id == card }),
              let raw = metric.value
        else {
            throw ProviderFailure.badResponse("RevenueCat's overview did not include \(card).")
        }

        let currency = (overview.currency ?? "USD").uppercased()
        switch unit {
        case .currency:
            return MetricValue(
                value: minorUnits(raw, currency: currency),
                currency: currency,
                note: currencyNote(reported: currency, preferredCurrency: preferredCurrency))
        case .count:
            // A headcount carries no currency, so the tile must not be told
            // one — a count with a currency on it renders as money.
            return MetricValue(value: raw.rounded(), currency: nil)
        }
    }

    /// Gross revenue over the window, straight from the endpoint that backs
    /// the dashboard's own figure.
    ///
    /// No series: the endpoint totals one inclusive date range per call and
    /// the Charts domain allows 25 calls a minute, so a thirty-point
    /// sparkline would be a minute of rate budget per widget. The single
    /// point is the total stamped at the end of the window, which is what the
    /// Worker emits for a total-shaped metric.
    private func revenueTotal(
        creds: Credentials, projectId: String, window: MetricWindow, http: ProviderHTTP
    ) async throws -> MetricValue {
        let path = "/projects/\(Self.pathSegment(projectId))/metrics/revenue"

        func total(from: Date, to: Date) async throws -> RevenueMetric {
            var params = [
                "start_date": Self.isoDay(from, timeZone: window.timeZone),
                "end_date": Self.isoDay(to, timeZone: window.timeZone),
                "revenue_type": "revenue",
            ]
            if let currency = Self.reportingCurrency(for: window.preferredCurrency) {
                params["currency"] = currency
            }
            return try await get(
                RevenueMetric.self, path, creds: creds, http: http, params: params)
        }

        let current = try await total(from: window.from, to: window.to)
        let currency = (current.currency ?? "USD").uppercased()
        let value = Self.minorUnits(current.value ?? 0, currency: currency)

        // Honoured rather than always fetched: this is a second live request
        // against a 25-a-minute domain, and a tile with no delta on it would
        // be paying that for nothing. The TS descriptor sets `compare: true`
        // on this metric and on no other, which is where the flag comes from.
        var previousValue: Double?
        if window.comparePrevious {
            let earlier = Self.previousWindow(from: window.from, to: window.to)
            let previous = try await total(from: earlier.from, to: earlier.to)
            previousValue = Self.minorUnits(
                previous.value ?? 0,
                currency: (previous.currency ?? currency).uppercased())
        }

        return MetricValue(
            value: value,
            previousValue: previousValue,
            // The end of the window, not this instant: this is a total *to*
            // `to`, and stamping it now would put the bar in tomorrow.
            points: [MetricPoint(t: ISO8601DateFormatter().string(from: window.to), v: value)],
            currency: currency,
            note: Self.currencyNote(
                reported: currency, preferredCurrency: window.preferredCurrency))
    }

    // MARK: - Window arithmetic

    /// The window immediately before this one, of the same length.
    ///
    /// RevenueCat's date range is *inclusive calendar days*, so the previous
    /// window has to end the day before the current one starts. Ending it on
    /// `from` itself would count the boundary day in both halves, and the
    /// delta would read as growth on a flat book.
    static func previousWindow(from: Date, to: Date) -> (from: Date, to: Date) {
        let day: TimeInterval = 24 * 60 * 60
        let span = to.timeIntervalSince(from)
        let previousTo = from.addingTimeInterval(-day)
        return (from: previousTo.addingTimeInterval(-span), to: previousTo)
    }

    /// `YYYY-MM-DD` in the user's zone. RevenueCat's days are calendar days,
    /// so an instant formatted in UTC puts every evening in the wrong day for
    /// anybody west of Greenwich.
    static func isoDay(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        // `en_US_POSIX`, or a user whose region uses a non-Gregorian calendar
        // gets a Buddhist-era year in the query string and a 400 back.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Money

    /// A decimal major-unit amount as integer minor units.
    ///
    /// RevenueCat reports money as a decimal in major units; ours is integer
    /// minor units, so $12.34 is 1234 and ¥1234 is 1234. The exponent depends
    /// on the currency, and the exceptions are the whole reason this is a
    /// table: multiplying by 100 would make every yen figure a hundred times
    /// too large and every dinar a tenth of what it is.
    ///
    /// The same table as `MINOR_UNIT_EXPONENT` in
    /// `packages/integrations/src/normalise.ts`.
    static func minorUnits(_ amount: Double, currency: String) -> Double {
        let exponent: Int
        switch currency.uppercased() {
        case "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW",
             "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF":
            exponent = 0
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND":
            exponent = 3
        default:
            exponent = 2
        }
        return (amount * pow(10, Double(exponent))).rounded()
    }

    /// The `currency` parameter to send, or nil to take the project's default.
    ///
    /// Asking for one RevenueCat does not report in is a 400, not a fallback,
    /// so an unsupported preference has to be left off the request entirely.
    static func reportingCurrency(for preferred: String) -> String? {
        let want = preferred.uppercased()
        return reportingCurrencies.contains(want) ? want : nil
    }

    /// Says so when RevenueCat could not report in the currency the user wanted.
    static func currencyNote(reported: String, preferredCurrency: String) -> String? {
        let want = preferredCurrency.uppercased()
        guard reported != want else { return nil }
        return "RevenueCat cannot report in \(want), so this is in \(reported)."
    }

    // MARK: - Requests

    /// The Overview, optionally in a currency the user asked for.
    ///
    /// `preferredCurrency` is nil from `verify`, which has no window and so no
    /// preference to pass: the currency it reports is then the project's own,
    /// which is the honest answer to "what does this account count in".
    func overview(
        creds: Credentials, projectId: String, http: ProviderHTTP,
        preferredCurrency: String? = nil
    ) async throws -> Overview {
        var params: [String: String] = [:]
        if let preferredCurrency, let currency = Self.reportingCurrency(for: preferredCurrency) {
            params["currency"] = currency
        }
        return try await get(
            Overview.self, "/projects/\(Self.pathSegment(projectId))/metrics/overview",
            creds: creds, http: http, params: params)
    }

    /// The project to read, resolved again only when nothing was typed.
    ///
    /// On a poll a pinned project is already settled, so the extra
    /// `/projects` call is spent only by a key that can see exactly one — one
    /// request on a 60-a-minute domain, against a 25-a-minute one for the
    /// metrics themselves.
    private func projectId(creds: Credentials, http: ProviderHTTP) async throws -> String {
        if let projectId = creds.projectId { return projectId }
        return try await resolveProject(creds: creds, http: http).id
    }

    /// A project id inside a path, escaped.
    ///
    /// The id is user-typed. Interpolated raw, a stray `../` would address a
    /// different endpoint on the same allowed host — which the allowlist
    /// cannot see, because the host is right.
    static func pathSegment(_ value: String) -> String {
        // The set `encodeURIComponent` leaves alone, minus the sub-delims
        // nothing in a project id uses. A slash, a dot or a space is escaped.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
