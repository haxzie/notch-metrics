import Foundation

/// Where a tile goes when it is clicked.
///
/// Three answers in order: what the user set on this widget, what the metric's
/// own template says for the parameters this widget carries, and the
/// provider's dashboard. A tile with none of those is not clickable, rather
/// than clickable and useless.
///
/// Resolved in the app from the catalogue rather than stored on the widget, so
/// a provider that moves its dashboard — or gains a deep link it never had —
/// fixes every existing tile with a Worker deploy.
public enum WidgetLink {
    /// The templates a resolution needs, keyed as `NotchWidget.metricKey` is
    /// (`"github/stars"`) for a metric, and by app id (`"github"`) for a
    /// provider's dashboard.
    public struct Catalogue: Sendable, Equatable {
        public var byMetric: [String: String]
        public var byApp: [String: String]

        public init(byMetric: [String: String] = [:], byApp: [String: String] = [:]) {
            self.byMetric = byMetric
            self.byApp = byApp
        }
    }

    public static func resolve(_ widget: NotchWidget, in catalogue: Catalogue) -> URL? {
        if let own = widget.link, let url = safeURL(own) { return url }
        if let template = widget.metricKey.flatMap({ catalogue.byMetric[$0] }),
            let filled = fill(template, with: widget.params),
            let url = safeURL(filled)
        {
            return url
        }
        return catalogue.byApp[widget.appId].flatMap(safeURL)
    }

    /// Parses, and refuses anything that is not a web page.
    ///
    /// The widget's own link is user input that ends up at
    /// `NSWorkspace.open` — which will happily launch a `file:` URL, or hand a
    /// `x-apple-...` one to whatever claims the scheme. A tile opens web
    /// pages; everything else is a no.
    static func safeURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
            url.host?.isEmpty == false
        else { return nil }
        return url
    }

    /// Substitutes `{key}` from `params`.
    ///
    /// A placeholder with nothing to fill it takes its query item with it —
    /// an unset branch means every branch, and `?query=branch%3A` means a
    /// search for the empty string. The same hole in the *path* gives up
    /// entirely, so the caller can fall back to the dashboard rather than
    /// open a URL with a gap in it.
    static func fill(_ template: String, with params: [String: String]) -> String? {
        let parts = template.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard let path = parts.first.map(String.init) else { return nil }
        guard let filledPath = substitute(path, params), !filledPath.hasPlaceholder else {
            return nil
        }
        guard parts.count == 2 else { return filledPath }

        let query =
            String(parts[1])
            .split(separator: "&", omittingEmptySubsequences: true)
            .compactMap { item -> String? in
                let filled = substitute(String(item), params)
                return filled?.hasPlaceholder == false ? filled : nil
            }
        return query.isEmpty ? filledPath : "\(filledPath)?\(query.joined(separator: "&"))"
    }

    private static func substitute(_ text: String, _ params: [String: String]) -> String? {
        var out = text
        for (key, value) in params {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Encoded per segment. A branch is `feature/x` as often as not, and
            // a repository is two segments — so slashes stay, and the
            // characters that would end the path or start a new parameter do
            // not.
            let encoded =
                trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
                .replacingOccurrences(of: "?", with: "%3F")
                .replacingOccurrences(of: "&", with: "%26")
                .replacingOccurrences(of: "#", with: "%23") ?? trimmed
            out = out.replacingOccurrences(of: "{\(key)}", with: encoded)
        }
        return out
    }
}

extension String {
    /// Whether a `{placeholder}` survived substitution.
    fileprivate var hasPlaceholder: Bool {
        guard let open = firstIndex(of: "{") else { return false }
        return self[open...].contains("}")
    }
}
