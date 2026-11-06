import Foundation
import MetricsCore
import Testing

@testable import Providers

/// RevenueCat's statuses, in the buckets the caller acts differently on.
///
/// Tested through `failure(for:)` rather than over the network: what is worth
/// pinning is which bucket each status lands in, and that a key missing one
/// permission does not mark the whole connection broken.
@Suite("revenuecat failures")
struct RevenueCatFailureTests {
    private func response(_ status: Int, body: String = "", headers: [String: String] = [:])
        -> ProviderHTTP.Response
    {
        ProviderHTTP.Response(status: status, headers: headers, body: Data(body.utf8))
    }

    @Test("a rejected key is an auth failure, and carries RevenueCat's own words")
    func badKey() {
        let failure = RevenueCatProvider.failure(
            for: response(401, body: #"{"message":"Invalid API key"}"#))
        #expect(failure == .authFailed("Invalid API key"))
    }

    /// The one worth being deliberate about, and the one place this adapter
    /// departs from the Worker's generic status mapping. A Charts-only key —
    /// the least privilege these metrics need — gets a 403 from `/projects`.
    /// Calling that an auth failure would ask the user to replace a key that
    /// answers every metric they asked for.
    @Test("a missing permission is unsupported, not an auth failure")
    func missingPermission() {
        let failure = RevenueCatProvider.failure(for: response(403))
        #expect(failure == .unsupported("That key may not read this part of the project."))
    }

    @Test("a project that is gone is a fact about the project, not a bad request")
    func missingProject() {
        let failure = RevenueCatProvider.failure(for: response(404))
        #expect(failure == .unsupported("RevenueCat has no such project or metric."))
    }

    @Test("a spent quota carries the wait RevenueCat asked for")
    func rateLimited() {
        let failure = RevenueCatProvider.failure(for: response(429, headers: ["Retry-After": "30"]))
        #expect(failure == .rateLimited("RevenueCat's rate limit is spent.", retryAfter: 30))
    }

    /// A nil wait would have the refresh loop retry on its own tick, which on
    /// a spent quota is immediately — and the Charts domain allows 25 calls a
    /// minute.
    @Test("and a minute when it asked for nothing")
    func rateLimitedSilently() {
        #expect(
            RevenueCatProvider.failure(for: response(429))
                == .rateLimited("RevenueCat's rate limit is spent.", retryAfter: 60))
    }

    @Test("a 5xx is their outage, retried rather than reported as a bad key")
    func down() {
        #expect(
            RevenueCatProvider.failure(for: response(503))
                == .providerDown("RevenueCat is having trouble."))
    }

    @Test("any other 4xx keeps the explanation RevenueCat sent")
    func explained() {
        let failure = RevenueCatProvider.failure(
            for: response(400, body: #"{"message":"currency is not supported"}"#))
        #expect(failure == .badResponse("currency is not supported"))
    }

    @Test("and says the status when it sent none")
    func unexplained() {
        #expect(
            RevenueCatProvider.failure(for: response(418)) == .badResponse("RevenueCat returned 418."))
    }
}

@Suite("revenuecat credentials")
struct RevenueCatCredentialTests {
    /// The field is optional and hidden in some builds of the connect sheet,
    /// so an empty string is the common case rather than the odd one. Left
    /// as `""` it would be interpolated into a path and address
    /// `/projects//metrics/overview`.
    @Test("an empty project id is absent, not a project called empty string")
    func emptyProject() throws {
        let creds = try RevenueCatProvider.Credentials([
            "secret_key": "sk_test_01234567890123456789", "project_id": "  ",
        ])
        #expect(creds.projectId == nil)
    }

    @Test("a typed project id is kept, trimmed")
    func typedProject() throws {
        let creds = try RevenueCatProvider.Credentials([
            "secret_key": "sk_test_01234567890123456789", "project_id": " proj1ab2c3d4 ",
        ])
        #expect(creds.projectId == "proj1ab2c3d4")
    }

    /// The form will not submit an empty required field, so this is a bug
    /// rather than user error — but it reaches a live API either way, and an
    /// empty bearer token reads back as a revoked key.
    @Test("a missing secret key is refused before any request is made")
    func missingKey() {
        #expect(throws: ProviderFailure.self) {
            _ = try RevenueCatProvider.Credentials(["project_id": "proj1ab2c3d4"])
        }
    }

    /// A project id is user-typed and goes into a path. Interpolated raw, a
    /// stray slash would address a different endpoint on an allowed host —
    /// which the allowlist cannot catch, because the host is right.
    @Test("a project id is escaped before it becomes a path segment")
    func escaped() {
        #expect(RevenueCatProvider.pathSegment("proj1ab2c3d4") == "proj1ab2c3d4")
        #expect(RevenueCatProvider.pathSegment("a_b-c~d") == "a_b-c~d")
        // Dots escaped as well as the slash. `pathSegment` allows only
        // alphanumerics and `-_~`, which is stricter than it strictly needs
        // to be and deliberately so: the id is user-typed, and a traversal
        // that survives one layer of decoding is the failure this exists to
        // stop. The test previously asserted the looser `..%2Fprojects`,
        // which the implementation's own comment contradicts.
        #expect(RevenueCatProvider.pathSegment("../projects") == "%2E%2E%2Fprojects")
    }
}

/// The arithmetic, which is the part a port silently gets wrong.
@Suite("revenuecat money")
struct RevenueCatMoneyTests {
    /// RevenueCat sends a decimal in major units and the rest of the app
    /// wants integer minor units. Multiplying by 100 regardless would make
    /// every yen figure a hundred times too large.
    @Test("a decimal major amount becomes integer minor units")
    func twoPlaces() {
        #expect(RevenueCatProvider.minorUnits(12.34, currency: "USD") == 1234)
        #expect(RevenueCatProvider.minorUnits(1234.5, currency: "eur") == 123_450)
    }

    @Test("a zero-decimal currency is not multiplied")
    func zeroPlaces() {
        #expect(RevenueCatProvider.minorUnits(1234, currency: "JPY") == 1234)
        #expect(RevenueCatProvider.minorUnits(1234, currency: "KRW") == 1234)
    }

    @Test("a three-decimal currency is multiplied by a thousand")
    func threePlaces() {
        #expect(RevenueCatProvider.minorUnits(1.234, currency: "KWD") == 1234)
    }

    /// Floating point arrives at 1233.9999999999998 for this one, and a
    /// fractional minor unit on the headline figure is a rendering bug
    /// waiting to happen.
    @Test("the result is a whole number of minor units")
    func rounded() {
        let value = RevenueCatProvider.minorUnits(12.34, currency: "USD")
        #expect(value == value.rounded())
    }

    /// Asking for a currency RevenueCat does not report in is a 400, not a
    /// fallback, so the parameter has to be left off entirely.
    @Test("an unsupported preference is left off the request")
    func reportingCurrency() {
        #expect(RevenueCatProvider.reportingCurrency(for: "usd") == "USD")
        #expect(RevenueCatProvider.reportingCurrency(for: "INR") == nil)
    }

    @Test("and the answer says which currency came back instead")
    func note() {
        #expect(RevenueCatProvider.currencyNote(reported: "USD", preferredCurrency: "usd") == nil)
        #expect(
            RevenueCatProvider.currencyNote(reported: "USD", preferredCurrency: "INR")
                == "RevenueCat cannot report in INR, so this is in USD.")
    }
}

@Suite("revenuecat overview cards")
struct RevenueCatOverviewTests {
    private func overview(_ metrics: [(String, Double?)], currency: String? = "USD")
        -> RevenueCatProvider.Overview
    {
        let cards: [String] = metrics.map { card in
            let value: String = card.1.map { String($0) } ?? "null"
            return #"{"id":"\#(card.0)","value":\#(value)}"#
        }
        let json: String = cards.joined(separator: ",")
        let body = #"{"currency":\#(currency.map { "\"\($0)\"" } ?? "null"),"metrics":[\#(json)]}"#
        return try! JSONDecoder().decode(
            RevenueCatProvider.Overview.self, from: Data(body.utf8))
    }

    @Test("a money card is converted to minor units and carries the currency")
    func money() throws {
        let value = try RevenueCatProvider.value(
            from: overview([("mrr", 1234.56)]), card: "mrr", unit: .currency,
            preferredCurrency: "USD")
        #expect(value.value == 123_456)
        #expect(value.currency == "USD")
        #expect(value.note == nil)
    }

    /// A count with a currency on it renders as money, which for "412 active
    /// trials" reads as $4.12.
    @Test("a count is rounded and carries no currency")
    func count() throws {
        let value = try RevenueCatProvider.value(
            from: overview([("active_subscriptions", 412.0)]), card: "active_subscriptions",
            unit: .count, preferredCurrency: "USD")
        #expect(value.value == 412)
        #expect(value.currency == nil)
    }

    /// The widget ids and RevenueCat's card ids differ for three of the five,
    /// and that mapping is exactly what a port transcribes wrongly.
    @Test("each widget reads the card RevenueCat actually names")
    func cardIds() {
        #expect(RevenueCatProvider.overviewCards["active_subscribers"]?.card == "active_subscriptions")
        #expect(RevenueCatProvider.overviewCards["trials"]?.card == "active_trials")
        #expect(RevenueCatProvider.overviewCards["new_users"]?.card == "new_customers")
        #expect(RevenueCatProvider.overviewCards["mrr"]?.unit == .currency)
        #expect(RevenueCatProvider.overviewCards["active_users"]?.unit == .count)
    }

    /// A null value and an absent card are the same answer to the widget, and
    /// neither may become zero: "MRR is $0" is a claim, and a card
    /// RevenueCat did not send is not evidence for it.
    @Test("a missing or null card is a bad response naming the card, not a zero")
    func missing() {
        #expect(throws: ProviderFailure.badResponse("RevenueCat's overview did not include mrr.")) {
            _ = try RevenueCatProvider.value(
                from: overview([("active_trials", 3)]), card: "mrr", unit: .currency,
                preferredCurrency: "USD")
        }
        #expect(throws: ProviderFailure.badResponse("RevenueCat's overview did not include mrr.")) {
            _ = try RevenueCatProvider.value(
                from: overview([("mrr", nil)]), card: "mrr", unit: .currency,
                preferredCurrency: "USD")
        }
    }

    /// The Overview omits `currency` on a project that has taken no money.
    /// USD is the Worker's fallback, and a decode failure here would blank
    /// the tile instead.
    @Test("an absent currency falls back to USD, as the Worker's does")
    func noCurrency() throws {
        let value = try RevenueCatProvider.value(
            from: overview([("mrr", 10)], currency: nil), card: "mrr", unit: .currency,
            preferredCurrency: "USD")
        #expect(value.currency == "USD")
        #expect(value.value == 1000)
    }
}

@Suite("revenuecat windows")
struct RevenueCatWindowTests {
    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: iso)!
    }

    /// The failure worth pinning. RevenueCat's range is inclusive calendar
    /// days, so a previous window ending on `from` itself counts the boundary
    /// day twice and the delta reads as growth on a flat book.
    @Test("the previous window ends the day before this one starts")
    func previousWindow() {
        let earlier = RevenueCatProvider.previousWindow(
            from: date("2026-02-08T00:00:00Z"), to: date("2026-02-14T00:00:00Z"))

        #expect(RevenueCatProvider.isoDay(earlier.to, timeZone: .gmt) == "2026-02-07")
        #expect(RevenueCatProvider.isoDay(earlier.from, timeZone: .gmt) == "2026-02-01")
    }

    @Test("and is the same length as this one")
    func sameLength() {
        let from = date("2026-02-01T00:00:00Z")
        let to = date("2026-03-01T00:00:00Z")
        let earlier = RevenueCatProvider.previousWindow(from: from, to: to)
        #expect(earlier.to.timeIntervalSince(earlier.from) == to.timeIntervalSince(from))
    }

    /// A day boundary read in UTC puts every evening west of Greenwich in the
    /// wrong calendar day, which for a one-day window is the whole figure.
    @Test("a day is the user's calendar day, not UTC's")
    func zone() {
        let evening = date("2026-02-14T03:00:00Z")
        #expect(RevenueCatProvider.isoDay(evening, timeZone: .gmt) == "2026-02-14")
        #expect(
            RevenueCatProvider.isoDay(
                evening, timeZone: TimeZone(identifier: "America/Los_Angeles")!) == "2026-02-13")
    }
}

@Suite("revenuecat routing")
struct RevenueCatRoutingTests {
    /// The contract, not a failure mode: the catalogue is the Worker's and
    /// lists metrics this build has not been taught. The caller falls back to
    /// the API on `unsupported`, so a wrong error here is a blank tile.
    @Test("a metric this build does not know says so rather than failing obscurely")
    func unknownMetric() async {
        let window = MetricWindow(
            metric: "churned_subscribers", from: Date(), to: Date(), granularity: .day,
            wantSeries: false)
        let outcome = await Result {
            try await RevenueCatProvider().fetch(
                ["secret_key": "sk_test_01234567890123456789", "project_id": "proj1"],
                window: window,
                http: ProviderHTTP(allowedHosts: RevenueCatProvider().allowedHosts))
        }
        #expect(throws: ProviderFailure.self) { try outcome.get() }
    }

    @Test("and every host but RevenueCat's own is refused")
    func hosts() {
        #expect(RevenueCatProvider().id == "revenuecat")
        #expect(
            ProviderHTTP.hostAllowed("api.revenuecat.com", in: RevenueCatProvider().allowedHosts))
        #expect(!ProviderHTTP.hostAllowed("revenuecat.com.attacker.net", in: RevenueCatProvider().allowedHosts))
    }
}
