import Foundation
import MetricsCore
import Testing

@testable import Providers

/// OpenAI's statuses, in the buckets the caller acts differently on.
///
/// Tested through `failure(for:)` rather than over a stubbed session: what is
/// worth pinning is which bucket each status lands in, and above all that the
/// 401 says *which kind* of key is needed.
@Suite("openai failures")
struct OpenAIFailureTests {
    private func response(_ status: Int, body: String = "", headers: [String: String] = [:])
        -> ProviderHTTP.Response
    {
        ProviderHTTP.Response(status: status, headers: headers, body: Data(body.utf8))
    }

    /// The one worth being deliberate about on this connector. A plain
    /// "rejected your key" is indistinguishable from a typo, and the
    /// overwhelmingly common cause is a perfectly valid `sk-proj-` key that
    /// can never read the usage report — so the message has to name the kind,
    /// or the user regenerates the same kind again.
    @Test("a rejected key names the kind of key the usage report needs")
    func badKey() {
        for status in [401, 403] {
            #expect(
                OpenAIProvider.failure(for: response(status))
                    == .authFailed(
                        "OpenAI would not read your usage. This needs an organisation Admin key, "
                            + "not a project or user key."))
        }
    }

    /// OpenAI's own words survive, even though the status bucket is ours: it
    /// quotes the admin-key wording above for 401 and 403 only.
    @Test("a 401 keeps our wording rather than OpenAI's")
    func badKeyWording() {
        let failure = OpenAIProvider.failure(
            for: response(401, body: #"{"error":{"message":"Incorrect API key provided: sk-pr***"}}"#))
        // Not the quoted key. A provider is free to echo the credential we
        // just sent it, and this string is headed for a user's screen.
        #expect(failure.message.contains("organisation Admin key"))
    }

    @Test("a spent quota carries the wait OpenAI asked for")
    func rateLimited() {
        let failure = OpenAIProvider.failure(for: response(429, headers: ["Retry-After": "20"]))
        #expect(failure == .rateLimited("OpenAI's rate limit is spent.", retryAfter: 20))
    }

    @Test("a 5xx is their outage, retried rather than reported as a bad key")
    func down() {
        #expect(
            OpenAIProvider.failure(for: response(503)) == .providerDown("OpenAI is having trouble."))
    }

    /// Throwing the body away leaves "OpenAI returned 400" on screen, and the
    /// cause then has to be guessed from outside the system.
    @Test("any other 4xx keeps the explanation OpenAI sent")
    func explained() {
        let failure = OpenAIProvider.failure(
            for: response(400, body: #"{"error":{"message":"Invalid bucket_width: 1w"}}"#))
        #expect(failure == .badResponse("Invalid bucket_width: 1w"))
    }

    /// An HTML error page in a notch tile is worse than the bare status it
    /// would replace.
    @Test("an unreadable body falls back to the status")
    func unexplained() {
        #expect(
            OpenAIProvider.failure(for: response(418, body: "<html>no</html>"))
                == .badResponse("OpenAI returned 418."))
    }
}

@Suite("openai credentials")
struct OpenAICredentialTests {
    /// The form will not submit an empty required field, so this is a bug
    /// rather than user error — but it reaches a live API either way, and an
    /// empty bearer token reads back as a revoked key.
    @Test("a missing admin key is refused before any request is made")
    func missingKey() {
        #expect(throws: ProviderFailure.self) {
            try OpenAIProvider.credentials(["project_id": "proj_1"])
        }
    }

    /// The project really is optional: left empty, every report totals the
    /// whole organisation. The failure this pins is sending the parameter
    /// anyway — OpenAI reads an empty `project_ids[]` as a project whose id
    /// is the empty string and answers with zeroes.
    @Test("an absent or blank project id is nil, not an empty string")
    func optionalProject() throws {
        #expect(try OpenAIProvider.credentials(["admin_key": "sk-admin-x"]).projectId == nil)
        #expect(
            try OpenAIProvider.credentials(["admin_key": "sk-admin-x", "project_id": "  "])
                .projectId == nil)
        #expect(
            try OpenAIProvider.credentials(["admin_key": "sk-admin-x", "project_id": " proj_1 "])
                .projectId == "proj_1")
    }

    @Test("the project filter is appended only when there is a project")
    func query() {
        let withProject = OpenAIProvider.query(
            "/organization/costs", params: ["limit": "1", "bucket_width": "1d"],
            projectId: "proj_1")
        // Sorted, so a request is reproducible in a log and in a test, with
        // the repeated-key array last.
        #expect(
            withProject
                == "https://api.openai.com/v1/organization/costs"
                    + "?bucket_width=1d&limit=1&project_ids%5B%5D=proj_1")

        let whole = OpenAIProvider.query(
            "/organization/costs", params: ["limit": "1"], projectId: nil)
        #expect(!whole.contains("project_ids"))
    }
}

/// The page budget, which is what stops a long range becoming a tile that
/// spins forever.
@Suite("openai walk planning")
struct OpenAIPlanTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let day: TimeInterval = 24 * 60 * 60

    private func window(
        days: Double, granularity: Granularity, comparePrevious: Bool,
        metric: String = "tokens", wantSeries: Bool = true
    ) -> MetricWindow {
        let to = Date(timeIntervalSince1970: 1_800_000_000)
        return MetricWindow(
            metric: metric, from: to.addingTimeInterval(-days * day), to: to,
            granularity: granularity, wantSeries: wantSeries,
            comparePrevious: comparePrevious, timeZone: utc, preferredCurrency: "USD")
    }

    /// Read off the window rather than assumed. These metrics default to
    /// `hour`, which is how a 90-day tile came to ask for 2,160 hourly
    /// buckets — a walk no page budget could finish.
    @Test("the bucket width follows the granularity asked for")
    func width() {
        #expect(OpenAIProvider.bucketWidth(.hour) == "1h")
        #expect(OpenAIProvider.bucketWidth(.day) == "1d")
        #expect(OpenAIProvider.bucketWidth(.week) == "1d")
    }

    @Test("comparing widens the fetched range backwards by the window's length")
    func widened() throws {
        let asked = window(days: 30, granularity: .day, comparePrevious: true)
        let plan = try OpenAIProvider.planWalk(window: asked, width: "1d")
        #expect(plan.comparePrevious)
        #expect(plan.start == asked.from.addingTimeInterval(-30 * day))
    }

    @Test("not comparing asks for the requested window and nothing more")
    func notWidened() throws {
        let asked = window(days: 30, granularity: .day, comparePrevious: false)
        let plan = try OpenAIProvider.planWalk(window: asked, width: "1d")
        #expect(!plan.comparePrevious)
        #expect(plan.start == asked.from)
    }

    /// Degrades before it fails. 90 days of daily buckets is three requests
    /// and fits; 90 plus its comparison window is six and does not. A number
    /// with no delta is still the number somebody asked for.
    @Test("the comparison window is dropped before the range is refused")
    func degrades() throws {
        let asked = window(days: 90, granularity: .day, comparePrevious: true)
        let plan = try OpenAIProvider.planWalk(window: asked, width: "1d")
        #expect(!plan.comparePrevious)
        #expect(plan.start == asked.from)
    }

    /// Hourly buckets buy 28 days, not 124, so the same range plans
    /// differently depending on the granularity.
    @Test("an hourly walk has a much shorter reach than a daily one")
    func hourlyBudget() throws {
        let fits = try OpenAIProvider.planWalk(
            window: window(days: 10, granularity: .hour, comparePrevious: true), width: "1h")
        #expect(fits.comparePrevious)

        let doesNot = try OpenAIProvider.planWalk(
            window: window(days: 20, granularity: .hour, comparePrevious: true), width: "1h")
        #expect(!doesNot.comparePrevious)

        #expect(throws: ProviderFailure.self) {
            try OpenAIProvider.planWalk(
                window: window(days: 40, granularity: .hour, comparePrevious: false), width: "1h")
        }
    }

    /// The failure this connector shipped with: a range longer than the walk
    /// can reach has to say so, rather than being discovered as a tile that
    /// never settles.
    @Test("a range past the budget is refused with the reach in the message")
    func refused() {
        let outcome = Result {
            try OpenAIProvider.planWalk(
                window: window(days: 365, granularity: .day, comparePrevious: false),
                width: "1d")
        }
        guard case .failure(let error) = outcome, let failure = error as? ProviderFailure else {
            Issue.record("a yearly range was planned rather than refused")
            return
        }
        #expect(failure.message.contains("124 days"))
    }

    /// Checked before any request, so an hourly spend tile costs nothing to
    /// refuse. The cost report has no hourly bucket at all.
    @Test("hourly spend is refused without reaching the network")
    func hourlySpend() async {
        let http = ProviderHTTP(allowedHosts: ["api.openai.com"])
        let outcome = await Result {
            try await OpenAIProvider().fetch(
                ["admin_key": "sk-admin-x"],
                window: window(days: 1, granularity: .hour, comparePrevious: false,
                               metric: "api_spend"),
                http: http)
        }
        guard case .failure(let error) = outcome, let failure = error as? ProviderFailure else {
            Issue.record("an hourly spend window was fetched rather than refused")
            return
        }
        #expect(failure.message.contains("once a day"))
    }

    /// Not a bug: the catalogue is the Worker's and lists metrics this build
    /// has not been taught. The caller falls back to the API on this.
    @Test("a metric this build has not been taught says so rather than failing obscurely")
    func unknownMetric() async {
        let http = ProviderHTTP(allowedHosts: ["api.openai.com"])
        let outcome = await Result {
            try await OpenAIProvider().fetch(
                ["admin_key": "sk-admin-x"],
                window: window(days: 1, granularity: .day, comparePrevious: false,
                               metric: "images_generated"),
                http: http)
        }
        #expect(throws: ProviderFailure.self) { try outcome.get() }
    }
}

/// The arithmetic, which is the part a port silently gets wrong.
///
/// Both reports are bucketed by OpenAI itself, so these feed already-dated
/// rows straight into the same functions the walk does: what is worth pinning
/// is the float-to-minor-units conversion, the currency exclusion, and which
/// half of a widened range a bucket lands in. None of them needs a network.
@Suite("openai arithmetic")
struct OpenAIArithmeticTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: iso)!
    }

    /// 8 to 16 March, so the preceding period is the eight days before it.
    private func window(
        _ metric: String = "api_spend", comparePrevious: Bool, wantSeries: Bool = true,
        granularity: Granularity = .day
    ) -> MetricWindow {
        MetricWindow(
            metric: metric,
            from: date("2026-03-08T00:00:00Z"), to: date("2026-03-16T00:00:00Z"),
            granularity: granularity, wantSeries: wantSeries,
            comparePrevious: comparePrevious, timeZone: utc, preferredCurrency: "USD")
    }

    private func cost(
        at: String, dollars: Double?, currency: String = "usd", organizationId: String? = nil
    ) -> (at: Date, result: OpenAIProvider.CostResult) {
        let amount = dollars.map { #"{"value":\#($0),"currency":"\#(currency)"}"# } ?? "null"
        return (
            at: date(at),
            result: decode(
                OpenAIProvider.CostResult.self,
                """
                {"amount":\(amount),
                 "organization_id":\(organizationId.map { "\"\($0)\"" } ?? "null")}
                """)
        )
    }

    /// Dollars as a float is OpenAI's choice. $12.34 has to be 1234, and
    /// nothing downstream divides by a hundred again.
    @Test("dollars as a float become integer minor units")
    func minorUnits() {
        let value = OpenAIProvider.spendValue(
            [cost(at: "2026-03-09T00:00:00Z", dollars: 12.34)],
            window: window(comparePrevious: false), comparePrevious: false)
        #expect(value.value == 1234)
        #expect(value.currency == "USD")
    }

    /// Rounded once per bucket, not per line item. A day of
    /// thousandth-of-a-cent rows rounded individually reports nothing spent at
    /// all, which is the bug this ordering exists to prevent.
    @Test("fractional cents are rounded once over the window, not away per row")
    func fractions() {
        // A tenth of a cent a day for ten days. Rounded per row this is ten
        // zeroes; rounded once it is a cent.
        let rows = (0..<10).map { _ in cost(at: "2026-03-09T00:00:00Z", dollars: 0.001) }
        #expect(
            OpenAIProvider.spendValue(
                rows, window: window(comparePrevious: false), comparePrevious: false
            ).value == 1)
    }

    /// Excluded rather than converted. OpenAI bills in USD today, so this is
    /// a guard against a future that silently sums at 1:1.
    @Test("another currency is excluded and the note says so")
    func foreign() {
        let value = OpenAIProvider.spendValue(
            [
                cost(at: "2026-03-09T00:00:00Z", dollars: 10),
                cost(at: "2026-03-10T00:00:00Z", dollars: 99, currency: "eur"),
            ],
            window: window(comparePrevious: false), comparePrevious: false)
        #expect(value.value == 1000)
        #expect(value.note == "EUR charges were excluded rather than converted.")
    }

    /// A bucket with nothing billed in it is a day with no spend, not a
    /// malformed response.
    @Test("a bucket with no amount is a quiet day rather than an error")
    func emptyBucket() {
        let value = OpenAIProvider.spendValue(
            [
                cost(at: "2026-03-09T00:00:00Z", dollars: nil),
                cost(at: "2026-03-10T00:00:00Z", dollars: 5),
            ],
            window: window(comparePrevious: false), comparePrevious: false)
        #expect(value.value == 500)
        #expect(value.note == nil)
    }

    @Test("the earlier half is the previous value and the later half the headline")
    func halves() {
        let value = OpenAIProvider.spendValue(
            [
                cost(at: "2026-03-01T00:00:00Z", dollars: 4),
                cost(at: "2026-03-07T00:00:00Z", dollars: 6),
                cost(at: "2026-03-09T00:00:00Z", dollars: 10),
                cost(at: "2026-03-15T00:00:00Z", dollars: 5),
            ],
            window: window(comparePrevious: true), comparePrevious: true)

        #expect(value.value == 1500)
        #expect(value.previousValue == 1000)
        // The chart is the window the widget asked for, even though twice as
        // much was fetched: eight days, with the earlier half left out.
        #expect(value.points.count == 9)
        #expect(value.points.reduce(0) { $0 + $1.v } == 1500)
    }

    /// The failure worth pinning. A window edge is an instant and a bucket is
    /// a whole day, so a headline summed from the buckets would pull the
    /// earlier period's spend into the figure on screen.
    @Test("a bucket in the hours before the window does not reach the headline")
    func edge() {
        let value = OpenAIProvider.spendValue(
            [
                cost(at: "2026-03-07T22:00:00Z", dollars: 9),
                cost(at: "2026-03-08T02:00:00Z", dollars: 1),
            ],
            window: window(comparePrevious: true), comparePrevious: true)
        #expect(value.value == 100)
        #expect(value.previousValue == 900)
    }

    /// Nil rather than zero: zero is a delta of minus a hundred per cent on
    /// screen, on a tile that never asked for a delta.
    @Test("no comparison leaves the previous value nil rather than zero")
    func noCompare() {
        let value = OpenAIProvider.spendValue(
            [cost(at: "2026-03-09T00:00:00Z", dollars: 2.5)],
            window: window(comparePrevious: false), comparePrevious: false)
        #expect(value.previousValue == nil)
    }

    /// A tile with no chart on it must not be handed a series to drop.
    @Test("points are withheld when the widget draws no chart")
    func noSeries() {
        let value = OpenAIProvider.spendValue(
            [cost(at: "2026-03-09T00:00:00Z", dollars: 2.5)],
            window: window(comparePrevious: false, wantSeries: false), comparePrevious: false)
        #expect(value.points.isEmpty)
        #expect(value.value == 250)
    }

    /// The rows are dated by their bucket's own start, which is what lets a
    /// week of daily buckets be re-bucketed into one weekly point rather than
    /// seven. Re-bucketing day to day is a no-op, so this is the case that
    /// shows why `bucketSum` is here at all.
    @Test("daily buckets re-bucket to the granularity the chart draws")
    func weekly() {
        let value = OpenAIProvider.spendValue(
            (8...14).map { cost(at: "2026-03-\($0)T12:00:00Z", dollars: 1) },
            window: window(comparePrevious: false, granularity: .week), comparePrevious: false)
        #expect(value.value == 700)
        // Two weekly buckets across this window rather than nine daily ones,
        // with all seven days' spend in the first of them.
        #expect(value.points.count == 2)
        #expect(value.points[0].v == 700)
        #expect(value.points[1].v == 0)
    }

    /// Token counts are a count, not money: no currency on the answer, and
    /// the two columns add up rather than one standing for both.
    @Test("a usage column carries no currency")
    func usageHasNoCurrency() {
        let value = OpenAIProvider.series(
            [(at: date("2026-03-09T00:00:00Z"), amount: 1_500)],
            window: window("tokens", comparePrevious: false), comparePrevious: false,
            currency: nil)
        #expect(value.value == 1500)
        #expect(value.currency == nil)
    }
}

/// The wire shapes, decoded from the bodies these two reports actually send.
@Suite("openai decoding")
struct OpenAIDecodingTests {
    /// Both reports are bucketed by OpenAI itself: a response is buckets of
    /// totals, not rows to sum. The field that matters most is `start_time`,
    /// because that is what dates the row.
    @Test("a usage page decodes its buckets, its cursor and its columns")
    func usagePage() {
        let page = decode(
            OpenAIProvider.Page<OpenAIProvider.UsageResult>.self,
            """
            {"object":"page",
             "data":[{"object":"bucket","start_time":1772928000,"end_time":1773014400,
               "results":[{"object":"organization.usage.completions.result",
                 "input_tokens":1200,"output_tokens":300,"num_model_requests":7}]}],
             "has_more":true,"next_page":"page_AAA"}
            """)

        #expect(page.hasMore == true)
        #expect(page.nextPage == "page_AAA")
        #expect(page.data.count == 1)
        #expect(page.data[0].startTime == 1_772_928_000)
        #expect(page.data[0].results[0].inputTokens == 1200)
        #expect(page.data[0].results[0].outputTokens == 300)
        #expect(page.data[0].results[0].numModelRequests == 7)
    }

    /// The last page sends `has_more` false and a null cursor, and the walk
    /// has to stop on either — an empty cursor with `has_more` set would loop
    /// on the same page until the cap caught it.
    @Test("the last page decodes with no cursor")
    func lastPage() {
        let page = decode(
            OpenAIProvider.Page<OpenAIProvider.CostResult>.self,
            """
            {"object":"page",
             "data":[{"object":"bucket","start_time":1772928000,"end_time":1773014400,
               "results":[{"object":"organization.costs.result",
                 "amount":{"value":1.2345,"currency":"usd"},
                 "line_item":null,"project_id":null,"organization_id":"org-abc"}]}],
             "has_more":false,"next_page":null}
            """)

        #expect(page.hasMore == false)
        #expect(page.nextPage == nil)
        #expect(page.data[0].results[0].organizationId == "org-abc")
        #expect(page.data[0].results[0].amount?.value == 1.2345)
        #expect(page.data[0].results[0].amount?.currency == "usd")
    }
}

/// A wire shape from the JSON a report actually sends.
///
/// These structs are `Decodable` and nothing else — deliberately, since a
/// memberwise initialiser in a test is a second definition of the mapping and
/// would pass while the real one was wrong.
private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
    // swiftlint:disable:next force_try
    try! JSONDecoder().decode(type, from: Data(json.utf8))
}
