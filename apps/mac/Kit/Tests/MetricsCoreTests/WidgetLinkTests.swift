import Foundation
import Testing

@testable import MetricsCore

/// The tile's click, which is the one place a widget's own parameters become a
/// URL — and a URL that opens in the user's browser, which is why the rules
/// about what does *not* resolve matter as much as the happy path.
struct WidgetLinkTests {
    let catalogue = WidgetLink.Catalogue(
        byMetric: [
            "github/stars": "https://github.com/{repository}/stargazers",
            "github/ci_runs": "https://github.com/{repository}/actions?query=branch%3A{branch}",
        ],
        byApp: ["github": "https://github.com", "stripe": "https://dashboard.stripe.com"])

    func widget(
        app: String = "github", metric: String? = "stars", params: [String: String] = [:],
        link: String? = nil
    ) -> NotchWidget {
        NotchWidget(
            id: "w1", kind: .providerMetric, appId: app, metric: metric, params: params, link: link)
    }

    @Test("a metric's template is filled from the widget's own parameters")
    func fillsFromParams() {
        let url = WidgetLink.resolve(
            widget(params: ["repository": "haxzie/notch-metrics"]), in: catalogue)
        #expect(url?.absoluteString == "https://github.com/haxzie/notch-metrics/stargazers")
    }

    @Test("an unset parameter takes its query item with it")
    func dropsEmptyQueryItem() {
        // "Every branch" is what Actions shows with no filter at all.
        // `?query=branch%3A` is a search for a branch named "".
        let all = WidgetLink.resolve(
            widget(metric: "ci_runs", params: ["repository": "a/b"]), in: catalogue)
        #expect(all?.absoluteString == "https://github.com/a/b/actions")

        let one = WidgetLink.resolve(
            widget(metric: "ci_runs", params: ["repository": "a/b", "branch": "main"]),
            in: catalogue)
        #expect(one?.absoluteString == "https://github.com/a/b/actions?query=branch%3Amain")
    }

    @Test("a branch with a slash in it survives, and one with an ampersand cannot escape")
    func encodesParameters() {
        let slash = WidgetLink.resolve(
            widget(metric: "ci_runs", params: ["repository": "a/b", "branch": "feature/thing"]),
            in: catalogue)
        #expect(slash?.absoluteString.hasSuffix("branch%3Afeature/thing") == true)

        let hostile = WidgetLink.resolve(
            widget(metric: "ci_runs", params: ["repository": "a/b", "branch": "x&per_page=100"]),
            in: catalogue)
        #expect(hostile?.query == "query=branch%3Ax%26per_page=100")
    }

    @Test("a hole in the path falls back to the dashboard rather than opening it")
    func fallsBackWhenPathIsUnfilled() {
        // A GitHub tile with no repository yet. Opening
        // github.com/{repository}/stargazers is a 404 with extra steps.
        #expect(WidgetLink.resolve(widget(), in: catalogue)?.absoluteString == "https://github.com")
    }

    @Test("a metric with no template of its own still opens the provider")
    func fallsBackToDashboard() {
        let url = WidgetLink.resolve(widget(app: "stripe", metric: "mrr"), in: catalogue)
        #expect(url?.absoluteString == "https://dashboard.stripe.com")
    }

    @Test("a provider with nowhere to send anybody is not clickable")
    func noLinkAtAll() {
        #expect(WidgetLink.resolve(widget(app: "plausible", metric: "visitors"), in: catalogue)
            == nil)
    }

    @Test("the widget's own link wins over both")
    func overrideWins() {
        let url = WidgetLink.resolve(
            widget(params: ["repository": "a/b"], link: "https://ci.example.com/board"),
            in: catalogue)
        #expect(url?.absoluteString == "https://ci.example.com/board")
    }

    @Test("a link that is not a web page is refused, not opened")
    func refusesNonWebSchemes() {
        // This reaches `NSWorkspace.open`, which will launch a file or hand a
        // custom scheme to whatever claims it. A tile opens web pages.
        for hostile in [
            "file:///etc/passwd", "javascript:alert(1)", "x-apple-helpme://run", "notchmetrics://x",
            "", "   ", "https://",
        ] {
            let url = WidgetLink.resolve(
                widget(app: "nowhere", metric: nil, link: hostile), in: catalogue)
            #expect(url == nil, "\(hostile) should not resolve")
        }
    }

    @Test("a custom metric's tile falls back on its own app, not on nothing")
    func customMetric() {
        let widget = NotchWidget(
            id: "w2", kind: .customMetric, appId: "github", customMetricId: "github-stars")
        #expect(
            WidgetLink.resolve(widget, in: catalogue)?.absoluteString == "https://github.com")
    }
}
