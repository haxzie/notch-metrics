import Foundation
import MetricsCore
import Testing

@testable import Providers

@Suite("npm package names")
struct NpmPackageNameTests {
    private func window(_ package: String) -> MetricWindow {
        MetricWindow(
            metric: "downloads", from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 86_400), granularity: .day,
            wantSeries: true, params: ["package": package])
    }

    @Test("accepts a plain and a scoped name")
    func accepts() throws {
        #expect(try NpmProvider.packageFor(window("react")) == "react")
        #expect(try NpmProvider.packageFor(window("@scope/name")) == "@scope/name")
        // npm names are lower case, and a pasted "React" is a 404 that reads
        // as a missing package.
        #expect(try NpmProvider.packageFor(window(" React ")) == "react")
    }

    /// The value reaches a request path, and the manifest's `pattern` is only
    /// a hint the app renders. A traversal that got past this would address a
    /// different endpoint on a host the allowlist is perfectly happy with.
    @Test("refuses anything that is not a package name")
    func refuses() {
        for bad in ["../../etc", "a b", "name?query=1", "name#frag", ""] {
            #expect(throws: ProviderFailure.self) {
                _ = try NpmProvider.packageFor(window(bad))
            }
        }
    }

    /// A scope's slash has to survive as a slash, and everything else has to
    /// be escaped. `@scope/name` is two segments, not one with a literal `@/`.
    @Test("encodes each segment and keeps the scope's slash")
    func encoding() {
        #expect(NpmProvider.encode("react") == "react")
        #expect(NpmProvider.encode("@scope/name") == "%40scope/name")
    }
}

@Suite("npm days")
struct NpmDayTests {
    /// npm counts against a UTC day and publishes nothing else, so the day
    /// sent must be the UTC day whatever zone the reader is in.
    @Test("formats the UTC day, not the local one")
    func formatting() {
        // 23:30 UTC on 1 October is already 2 October in Tokyo.
        let late = Date(timeIntervalSince1970: 1_790_983_800)
        #expect(NpmProvider.day(late).count == 10)
        #expect(NpmProvider.day(late).hasPrefix("20"))
    }

    /// Midday rather than midnight. A UTC midnight parsed into a zone behind
    /// UTC lands on the day before, which shifts every bar in the chart one
    /// place to the left of where npm put it.
    @Test("reads a day label as the middle of that UTC day")
    func midday() throws {
        let at = try #require(NpmProvider.instant(ofDay: "2026-10-01"))

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(utc.component(.hour, from: at) == 12)
        #expect(utc.component(.day, from: at) == 1)

        // The thing that actually matters: still 1 October in Los Angeles.
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        #expect(la.component(.day, from: at) == 1)
    }

    @Test("an unreadable label is dropped rather than bucketed at the epoch")
    func unreadable() {
        #expect(NpmProvider.instant(ofDay: "not-a-day") == nil)
    }
}

@Suite("npm failures")
struct NpmFailureTests {
    private func response(_ status: Int, headers: [String: String] = [:])
        -> ProviderHTTP.Response
    {
        ProviderHTTP.Response(status: status, headers: headers, body: Data())
    }

    /// Blames the package, not the connection. The same token answers every
    /// other tile, so marking the integration broken would ask somebody to
    /// replace a credential that works.
    @Test("a 404 is about one package, not the token")
    func notFound() {
        let failure = NpmProvider.failure(for: response(404), subject: "npm")
        #expect(failure == .unsupported(
            "That package could not be read. Check the name, and that this token can see it."))
    }

    /// Nothing here sends a credential, so a 401 cannot be a bad key.
    /// Reporting it as one would send somebody looking for a token they
    /// never entered.
    @Test("a refusal is npm's problem, not a credential's")
    func refused() {
        #expect(
            NpmProvider.failure(for: response(401), subject: "npm")
                == .providerDown("npm refused the request."))
    }

    @Test("a spent quota carries the wait npm asked for")
    func rateLimited() {
        let failure = NpmProvider.failure(
            for: response(429, headers: ["Retry-After": "30"]), subject: "npm")
        #expect(failure == .rateLimited("npm asked us to wait.", retryAfter: 30))
    }

    @Test("npm is in the registry, reaching only the statistics host")
    func registered() throws {
        #expect(ProviderRegistry.isLocal("npm"))
        let adapter = try #require(ProviderRegistry.adapter(for: "npm"))
        // One host: the registry is never reached, because there is no
        // identity to look up.
        #expect(adapter.allowedHosts == ["api.npmjs.org"])
    }
}

@Suite("npm aggregation gaps")
struct NpmGapTests {
    private func days(_ counts: [Int]) -> [NpmProvider.Range.Day] {
        counts.enumerated().map { index, value in
            NpmProvider.Range.Day(downloads: value, day: "2026-10-0\(index + 1)")
        }
    }

    /// npm backfills late and scattered, not only at the end: September 2026
    /// had gaps on the 7th, 8th and 15th. A note that blamed "today" would be
    /// wrong about both where the zeros are and why.
    /// The bug a live run caught: npm lags a day or two at the end of every
    /// window, so a window ending today always has trailing zeros where the
    /// one before it — entirely in the past — has none. Counting those made
    /// the two windows look incomparable on every single poll, and the delta
    /// never appeared. Only gaps npm has skipped *inside* the window say
    /// anything about how comparable the two are.
    @Test("ignores npm's trailing lag and counts only gaps inside the window")
    func interior() {
        // Two trailing, which every current window has.
        #expect(NpmProvider.interiorGaps(days([100, 200, 300, 0, 0])) == 0)
        // Two inside, which is the patchiness that matters.
        #expect(NpmProvider.interiorGaps(days([100, 0, 0, 400, 500])) == 2)
        // Both kinds: only the interior pair counts.
        #expect(NpmProvider.interiorGaps(days([100, 0, 0, 400, 0])) == 2)
        // Nothing counted at all is not "all gaps interior".
        #expect(NpmProvider.interiorGaps(days([0, 0, 0])) == 0)
    }

    @Test("counts every unaggregated day, wherever it falls")
    func counted() {
        #expect(NpmProvider.unaggregated(days([100, 0, 300, 0, 500])) == 2)
        #expect(NpmProvider.unaggregated(days([100, 200, 300])) == 0)
        // A trailing zero is one case of the same thing, not a special one.
        #expect(NpmProvider.unaggregated(days([100, 200, 0])) == 1)
    }
}

/// npm's "Weekly Downloads" is a trailing seven-day sum, not a calendar week.
///
/// Verified against the live API: react on 4 November 2026 was 248,185,175,
/// which is both what `/downloads/point/last-week` returns and the sum of the
/// seven days ending that day. Calendar weeks gave 116M, 126M and 243M on
/// consecutive weeks, because npm's counts service had no data at all for
/// 13–15 and 19–21 October — the same days for every package.
@Suite("npm weekly trend")
struct NpmWeeklyTests {
    private func day(_ label: String, _ downloads: Int) -> NpmProvider.Range.Day {
        NpmProvider.Range.Day(downloads: downloads, day: label)
    }

    /// Trailing uncounted days drag a rolling total down — react fell from
    /// 248M to 171M across two of them. npm's page ends at the last complete
    /// day instead.
    @Test("trailing uncounted days are dropped, not summed as zero")
    func trailing() {
        let days =
            (1...8).map { day("2026-10-0\($0)", 100) }
            + [day("2026-10-09", 0), day("2026-10-10", 0)]

        var end = days.count
        while end > 0, days[end - 1].downloads == 0 { end -= 1 }
        #expect(end == 8)

        // The last full week of what remains is 700, not the 500 the two
        // trailing zeros would have produced.
        let counted = Array(days[..<end])
        #expect(counted[(end - 7)...(end - 1)].reduce(0) { $0 + $1.downloads } == 700)
    }
}
