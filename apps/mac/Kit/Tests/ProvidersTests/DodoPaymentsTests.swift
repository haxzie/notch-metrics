import Foundation
import MetricsCore
import Testing

@testable import Providers

/// Dodo's statuses, in the buckets the caller acts differently on.
///
/// Tested through `failure(for:)` rather than over a stubbed session: what is
/// worth pinning is which bucket each status lands in, and above all that a
/// key missing one scope does not mark the whole connection broken.
@Suite("dodo failures")
struct DodoFailureTests {
    private func response(_ status: Int, body: String = "", headers: [String: String] = [:])
        -> ProviderHTTP.Response
    {
        ProviderHTTP.Response(status: status, headers: headers, body: Data(body.utf8))
    }

    /// The mode is in the message because the commonest cause of a 401 is a
    /// key issued in the other environment, and "rejected the key" sends
    /// somebody off to make a new key instead of changing the dropdown.
    @Test("a rejected key is an auth failure and names the environment")
    func badKey() {
        let failure = DodoPaymentsProvider.failure(for: response(401), mode: .test)
        #expect(
            failure
                == .authFailed("Dodo Payments rejected that key for the test environment."))
    }

    /// The one worth being deliberate about. A key without
    /// `subscriptions:read` is a statement about one resource; calling it an
    /// auth failure would mark the connection broken and ask the user to
    /// replace a key that reads payments perfectly well.
    @Test("a missing scope is unsupported, not an auth failure")
    func scoped() {
        #expect(
            DodoPaymentsProvider.failure(for: response(403))
                == .unsupported("That key may not read this part of the account."))
    }

    @Test("a spent quota carries the wait Dodo asked for")
    func rateLimited() {
        let failure = DodoPaymentsProvider.failure(
            for: response(429, headers: ["Retry-After": "12"]))
        #expect(failure == .rateLimited("Dodo Payments' rate limit is spent.", retryAfter: 12))
    }

    @Test("a 5xx is their outage, retried rather than reported as a bad key")
    func down() {
        #expect(
            DodoPaymentsProvider.failure(for: response(502))
                == .providerDown("Dodo Payments is having trouble."))
    }

    /// Three shapes because this API has been seen to use all three, and
    /// throwing the body away leaves a bare status on screen with the cause to
    /// be guessed from outside the system.
    @Test("any other 4xx keeps the explanation Dodo sent, in each shape it sends it")
    func explained() {
        let bodies = [
            #"{"message":"invalid page_size"}"#,
            #"{"detail":"invalid page_size"}"#,
            #"{"error":{"message":"invalid page_size"}}"#,
        ]
        for body in bodies {
            #expect(
                DodoPaymentsProvider.failure(for: response(400, body: body))
                    == .badResponse("invalid page_size"))
        }
    }

    /// An HTML error page in a notch tile is worse than the bare status it
    /// would replace.
    @Test("an unreadable body falls back to the status")
    func unexplained() {
        #expect(
            DodoPaymentsProvider.failure(for: response(418, body: "<html>no</html>"))
                == .badResponse("Dodo Payments returned 418."))
    }
}

/// The host is chosen by the declared mode, never inferred from the key.
@Suite("dodo mode")
struct DodoModeTests {
    @Test("the mode picks the host")
    func hosts() {
        #expect(DodoPaymentsProvider.Mode.live.baseURL == "https://live.dodopayments.com")
        #expect(DodoPaymentsProvider.Mode.test.baseURL == "https://test.dodopayments.com")
    }

    /// Both hosts are on the allowlist, because the mode is per connection and
    /// the allowlist is per adapter.
    @Test("both hosts are reachable and nothing else is")
    func allowlist() {
        let hosts = DodoPaymentsProvider().allowedHosts
        #expect(ProviderHTTP.hostAllowed("live.dodopayments.com", in: hosts))
        #expect(ProviderHTTP.hostAllowed("test.dodopayments.com", in: hosts))
        #expect(!ProviderHTTP.hostAllowed("dodopayments.com", in: hosts))
        #expect(!ProviderHTTP.hostAllowed("live.dodopayments.com.attacker.net", in: hosts))
    }

    /// A connection stored before the field existed, or with a hand-edited
    /// value, is live: that is where nearly every key is issued, and its
    /// failure mode is a plain 401 rather than silently empty data.
    @Test("an absent or unrecognised mode is live")
    func defaulted() {
        #expect(DodoPaymentsProvider.mode(in: [:]) == .live)
        #expect(DodoPaymentsProvider.mode(in: ["mode": "sandbox"]) == .live)
        #expect(DodoPaymentsProvider.mode(in: ["mode": "Test"]) == .test)
    }

    @Test("the id matches the catalogue's so one table routes both")
    func identifier() {
        #expect(DodoPaymentsProvider().id == "dodopayments")
    }
}

/// The arithmetic, which is the part a port silently gets wrong.
@Suite("dodo arithmetic")
struct DodoArithmeticTests {
    private func subscription(
        _ amount: Double, _ currency: String, interval: String = "Month", count: Int = 1
    ) -> DodoSubscription {
        decode(
            DodoSubscription.self,
            """
            {"subscription_id":"sub_1","status":"active",
             "recurring_pre_tax_amount":\(amount),"currency":"\(currency)",
             "payment_frequency_interval":"\(interval)","payment_frequency_count":\(count),
             "created_at":"2026-01-01T00:00:00.000Z"}
            """)
    }

    /// Dodo capitalises its intervals. Lower-cased before `toMonthly`, which
    /// would otherwise fall through to its unknown-interval case and report a
    /// yearly plan's whole price as one month of MRR.
    @Test("a capitalised interval still normalises")
    func capitalised() {
        let row = subscription(12_000, "USD", interval: "Year")
        #expect(
            toMonthly(
                row.recurringPreTaxAmount,
                interval: row.paymentFrequencyInterval.lowercased(),
                intervalCount: row.paymentFrequencyCount) == 1000)
        // The failure this guards: the raw string is not a case `toMonthly`
        // knows, so it comes back untouched.
        #expect(
            toMonthly(
                row.recurringPreTaxAmount, interval: row.paymentFrequencyInterval,
                intervalCount: row.paymentFrequencyCount) == 12_000)
    }

    /// Summing mixed currencies at 1:1 is the kind of wrong that looks right.
    @Test("other currencies are dropped and named in the note")
    func currencies() {
        let rows = [
            subscription(1000, "USD"), subscription(900, "EUR"), subscription(800, "GBP"),
            subscription(700, "EUR"),
        ]
        let split = DodoPaymentsProvider.splitByCurrency(rows, preferred: "usd")
        #expect(split.kept.count == 1)
        #expect(split.note == "EUR and GBP excluded; totals are USD only.")
    }

    @Test("one currency produces no note at all")
    func singleCurrency() {
        let split = DodoPaymentsProvider.splitByCurrency(
            [subscription(1000, "USD")], preferred: "USD")
        #expect(split.note == nil)
    }

    /// Named rather than silent: a figure computed from the first 2,000 rows
    /// of a larger book is an undercount, and a tile cannot say so on its own.
    @Test("hitting the page cap says the figure is an undercount")
    func truncation() {
        #expect(
            DodoPaymentsProvider.truncationNote(true)
                == "Only the first 2000 records were read, so this is an undercount.")
        #expect(DodoPaymentsProvider.truncationNote(false) == nil)
    }

    @Test("notes are joined, and nothing is joined to nothing")
    func notes() {
        #expect(DodoPaymentsProvider.join("one.", nil, "two.") == "one. two.")
        #expect(DodoPaymentsProvider.join(nil, nil) == nil)
    }
}

@Suite("dodo payments decoding")
struct DodoPaymentDecodeTests {
    private func payment(
        subscriptionId: String? = nil, subscriptionIds: [String]? = nil
    ) -> DodoPayment {
        let single = subscriptionId.map { "\"\($0)\"" } ?? "null"
        let many = subscriptionIds.map { "[\($0.map { "\"\($0)\"" }.joined(separator: ","))]" }
            ?? "null"
        return decode(
            DodoPayment.self,
            """
            {"payment_id":"pay_1","total_amount":2500,"currency":"usd","status":"succeeded",
             "created_at":"2026-02-01T10:00:00.000Z","customer":{"name":"Ada","email":"a@b.c"},
             "subscription_id":\(single),"subscription_ids":\(many)}
            """)
    }

    /// The failure this guards: Dodo added `subscription_ids` for a checkout
    /// that bought several subscriptions, and a payment can carry either
    /// field. Checking only the singular counts a bundle renewal as a
    /// one-time sale and inflates the one-time figure.
    @Test("a bundle renewal is not a one-time sale")
    func oneTime() {
        #expect(payment().isOneTime)
        #expect(!payment(subscriptionId: "sub_1").isOneTime)
        #expect(!payment(subscriptionIds: ["sub_1", "sub_2"]).isOneTime)
    }

    /// Money is minor units, never divided here. 2500 is $25.00 and the
    /// formatter is the only thing that knows that.
    @Test("an amount stays in minor units")
    func minorUnits() {
        #expect(payment().totalAmount == 2500)
    }

    /// An empty list has been seen to omit `items` altogether, and a decode
    /// failure there would report a working key as an unreadable response.
    @Test("a list with no items decodes rather than failing")
    func emptyList() {
        let body = decode(DodoPaymentsProvider.DodoList<DodoPayment>.self, "{}")
        #expect((body.items ?? []).isEmpty)
    }
}

/// The revenue arithmetic, over rows already fetched.
///
/// `revenueValue` is split out of the walk for exactly this: which payments
/// count, which currency, and which half of a widened range they land in are
/// the things a port gets quietly wrong, and none of them needs a network.
@Suite("dodo revenue")
struct DodoRevenueTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: iso)!
    }

    /// 8 to 16 March, so the preceding period is the eight days before it.
    private func window(
        _ metric: String = "revenue", comparePrevious: Bool, wantSeries: Bool = true
    ) -> MetricWindow {
        MetricWindow(
            metric: metric,
            from: date("2026-03-08T00:00:00Z"), to: date("2026-03-16T00:00:00Z"),
            granularity: .day, wantSeries: wantSeries, comparePrevious: comparePrevious,
            timeZone: utc, preferredCurrency: "USD")
    }

    private func payment(
        _ id: String, at: String, amount: Double, currency: String = "usd",
        status: String = "succeeded", subscriptionId: String? = nil
    ) -> DodoPayment {
        decode(
            DodoPayment.self,
            """
            {"payment_id":"\(id)","total_amount":\(amount),"currency":"\(currency)",
             "status":"\(status)","created_at":"\(at)","customer":null,
             "subscription_id":\(subscriptionId.map { "\"\($0)\"" } ?? "null")}
            """)
    }

    /// The previous period has to be the window's own length, or the delta is
    /// between a month and a fortnight.
    @Test("comparing widens the fetched range backwards by the window's length")
    func widened() {
        #expect(
            DodoPaymentsProvider.fetchFrom(window(comparePrevious: true))
                == date("2026-02-28T00:00:00Z"))
    }

    /// The flag doubles the rows read, so a tile with no delta on it must not
    /// pay for the extra pages.
    @Test("not comparing asks for the requested window and nothing more")
    func notWidened() {
        #expect(
            DodoPaymentsProvider.fetchFrom(window(comparePrevious: false))
                == date("2026-03-08T00:00:00Z"))
    }

    @Test("the earlier half is the previous value and the later half the headline")
    func halves() {
        let rows = [
            payment("old_1", at: "2026-03-01T10:00:00.000Z", amount: 400),
            payment("old_2", at: "2026-03-07T23:59:00.000Z", amount: 600),
            payment("new_1", at: "2026-03-09T10:00:00.000Z", amount: 1000),
            payment("new_2", at: "2026-03-15T10:00:00.000Z", amount: 500),
        ]
        let value = DodoPaymentsProvider.revenueValue(
            rows, truncated: false, window: window(comparePrevious: true), include: { _ in true })

        #expect(value.value == 1500)
        #expect(value.previousValue == 1000)
        // The chart is the window the widget asked for, even though twice as
        // much was fetched: eight days, with the earlier half left out.
        #expect(value.points.count == 9)
        #expect(value.points.reduce(0) { $0 + $1.v } == 1500)
    }

    /// The failure worth pinning. The window's edges are instants and a
    /// bucket is a whole day, so a headline summed from the buckets would
    /// pull the preceding period's money into the figure on screen.
    @Test("a payment in the hours before the window does not reach the headline")
    func edge() {
        let rows = [
            payment("old", at: "2026-03-07T22:00:00.000Z", amount: 900),
            payment("new", at: "2026-03-08T02:00:00.000Z", amount: 100),
        ]
        let value = DodoPaymentsProvider.revenueValue(
            rows, truncated: false, window: window(comparePrevious: true), include: { _ in true })

        #expect(value.value == 100)
        #expect(value.previousValue == 900)
    }

    @Test("no comparison leaves the previous value nil rather than zero")
    func noCompare() {
        let value = DodoPaymentsProvider.revenueValue(
            [payment("a", at: "2026-03-09T10:00:00.000Z", amount: 250)],
            truncated: false, window: window(comparePrevious: false), include: { _ in true })

        #expect(value.value == 250)
        #expect(value.previousValue == nil)
    }

    /// Gross, and only money that actually arrived: `processing` has not been
    /// captured and `requires_capture` may never be.
    @Test("only succeeded payments count, in the user's currency")
    func filtered() {
        let rows = [
            payment("a", at: "2026-03-09T10:00:00.000Z", amount: 1000),
            payment("b", at: "2026-03-10T10:00:00.000Z", amount: 5000, status: "processing"),
            payment("c", at: "2026-03-11T10:00:00.000Z", amount: 7000, currency: "eur"),
        ]
        let value = DodoPaymentsProvider.revenueValue(
            rows, truncated: false, window: window(comparePrevious: false), include: { _ in true })

        #expect(value.value == 1000)
        #expect(value.note == "EUR excluded; totals are USD only.")
    }

    /// One-time sales are the same walk with a different filter, because the
    /// list has no server-side way to ask for either — so the comparison and
    /// the currency handling have to hold for both.
    @Test("one-time sales exclude subscription renewals on both halves")
    func oneTime() {
        let rows = [
            payment("old_sub", at: "2026-03-02T10:00:00.000Z", amount: 900, subscriptionId: "s_1"),
            payment("old_buy", at: "2026-03-03T10:00:00.000Z", amount: 300),
            payment("new_sub", at: "2026-03-10T10:00:00.000Z", amount: 800, subscriptionId: "s_1"),
            payment("new_buy", at: "2026-03-11T10:00:00.000Z", amount: 200),
        ]
        let value = DodoPaymentsProvider.revenueValue(
            rows, truncated: false, window: window("one_time_sales", comparePrevious: true),
            include: { $0.isOneTime })

        #expect(value.value == 200)
        #expect(value.previousValue == 300)
    }

    /// A tile with no chart on it should not carry the points it will not
    /// draw, but the headline is the same either way.
    @Test("a tile with no chart still gets the number")
    func noSeries() {
        let value = DodoPaymentsProvider.revenueValue(
            [payment("a", at: "2026-03-09T10:00:00.000Z", amount: 250)],
            truncated: false,
            window: window(comparePrevious: false, wantSeries: false), include: { _ in true })

        #expect(value.points.isEmpty)
        #expect(value.value == 250)
    }
}

/// The list shape, which nothing else in this target exercises yet.
@Suite("dodo recent payments")
struct DodoRecentPaymentsTests {
    private func payment(
        id: String, at: String, amount: Double, currency: String = "usd",
        name: String? = "Ada", email: String? = "ada@example.com"
    ) -> DodoPayment {
        decode(
            DodoPayment.self,
            """
            {"payment_id":"\(id)","total_amount":\(amount),"currency":"\(currency)",
             "status":"succeeded","created_at":"\(at)",
             "customer":{"name":\(json(name)),"email":\(json(email))},
             "subscription_id":null}
            """)
    }

    private func json(_ value: String?) -> String {
        value.map { "\"\($0)\"" } ?? "null"
    }

    @Test("a row carries the customer's name, the amount and its own currency")
    func row() throws {
        let item = try #require(
            DodoPaymentsProvider.listItem(
                payment(id: "pay_1", at: "2026-02-01T10:00:00.000Z", amount: 2500)))
        #expect(item.id == "pay_1")
        #expect(item.label == "Ada")
        #expect(item.amount == 2500)
        // Upper case, because the headline compares against an upper-cased
        // ISO 4217 code and Dodo sends these lower case.
        #expect(item.currency == "USD")
        #expect(item.status == "succeeded")
        // A payment is not pass or fail, it just happened.
        #expect(item.state == nil)
        #expect(item.date != nil)
    }

    @Test("the email stands in for a missing name, and a word for neither")
    func labels() throws {
        let noName = try #require(
            DodoPaymentsProvider.listItem(
                payment(id: "p", at: "2026-02-01T10:00:00.000Z", amount: 1, name: nil)))
        #expect(noName.label == "ada@example.com")

        let neither = try #require(
            DodoPaymentsProvider.listItem(
                payment(
                    id: "p", at: "2026-02-01T10:00:00.000Z", amount: 1, name: "", email: nil)))
        #expect(neither.label == "Customer")
    }

    /// The sort and the cap are on the timestamp, so a row with an unreadable
    /// one would take a slot at one end of the feed from a payment that really
    /// happened.
    @Test("a row with an unreadable timestamp is dropped rather than placed")
    func unreadableTimestamp() {
        #expect(DodoPaymentsProvider.listItem(payment(id: "p", at: "whenever", amount: 1)) == nil)
    }

    @Test("rows come back newest first and capped at ten")
    func ordering() {
        let rows = (1...14).compactMap { day in
            DodoPaymentsProvider.listItem(
                payment(
                    id: "pay_\(day)",
                    at: String(format: "2026-02-%02dT10:00:00.000Z", day),
                    amount: 100))
        }
        let value = DodoPaymentsProvider.recentPaymentsValue(rows, preferred: "USD")
        let items = value.items ?? []

        #expect(items.count == 10)
        #expect(items.first?.id == "pay_14")
        #expect(items.last?.id == "pay_5")
    }

    /// The headline is not the row count: a tile too short to show rows still
    /// has to say something true, and that is their total in one currency.
    /// Rows in another currency stay in the list with their own code, because
    /// a list can show a currency where a sum cannot.
    @Test("the headline totals only the rows in the user's currency")
    func headline() {
        let rows = [
            payment(id: "a", at: "2026-02-01T10:00:00.000Z", amount: 1000),
            payment(id: "b", at: "2026-02-02T10:00:00.000Z", amount: 2000, currency: "eur"),
            payment(id: "c", at: "2026-02-03T10:00:00.000Z", amount: 500),
        ].compactMap(DodoPaymentsProvider.listItem)

        let value = DodoPaymentsProvider.recentPaymentsValue(rows, preferred: "usd")
        #expect(value.value == 1500)
        #expect(value.currency == "usd")
        #expect((value.items ?? []).count == 3)
        #expect((value.items ?? []).contains { $0.currency == "EUR" })
    }

    @Test("an empty feed is zero rather than an error")
    func empty() {
        let value = DodoPaymentsProvider.recentPaymentsValue([], preferred: "USD")
        #expect(value.value == 0)
        #expect((value.items ?? []).isEmpty)
    }
}

/// Decodes a fixture, failing the test at the call site if it cannot.
///
/// The fixtures are the wire shapes, so decoding them here is part of what is
/// being tested: a renamed `snake_case` key fails by name rather than at a
/// user's launch.
private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
    // swiftlint:disable:next force_try
    try! JSONDecoder().decode(type, from: Data(json.utf8))
}
