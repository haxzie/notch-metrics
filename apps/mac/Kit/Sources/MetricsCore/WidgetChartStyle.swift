import Foundation

/// How a widget draws its chart.
///
/// Lives on the widget rather than in the theme or the app catalogue, for the
/// same reason `WidgetFormat` does: the app knows its brand colour, but only
/// the widget knows what *this* tile should look like. Dodo Payments' chart
/// being lime rather than their near-black primary was a one-line patch in
/// the catalogue; the next one would have been another, and the one after
/// that.
///
/// Every field is optional and nil means "fall back", so a widget with no
/// style renders from the app's colours exactly as before.
public struct WidgetChartStyle: Codable, Sendable, Hashable {
    /// `RRGGBB`. Overrides the app's chart colour for this widget alone.
    public var tintHex: String?
    /// The area under the line. Nil means filled.
    public var fill: Bool?
    /// Opacity at the top of the gradient. It always falls to zero at the
    /// bottom — that is the gradient, not a configurable.
    public var fillOpacity: Double?

    public init(tintHex: String? = nil, fill: Bool? = nil, fillOpacity: Double? = nil) {
        self.tintHex = tintHex
        self.fill = fill
        self.fillOpacity = fillOpacity
    }

    public static let automatic = WidgetChartStyle()
}
