import Foundation

/// How a widget renders its number, overriding what the series says.
///
/// The series already carries a `unit`, and that is the right default — the
/// adapter knows whether it fetched money or a count. This exists for the
/// cases the adapter cannot know: whether *this* tile, at *this* size, wants
/// "1.2M" or "1,243,901", and whether a ratio should read as a percentage.
///
/// Every field is optional and nil means "use the series". A widget with no
/// format at all behaves exactly as before, which is what keeps an existing
/// `layout.json` working.
public struct WidgetFormat: Codable, Sendable, Hashable {
    /// Overrides the series' own unit. Rarely needed, but a count the adapter
    /// reports as `count` is sometimes really a percentage.
    public var style: MetricUnit?
    /// `true` forces k/M/B, `false` forces the full number.
    public var compact: Bool?
    /// Only meaningful when the number is not compacted.
    public var decimals: Int?
    public var prefix: String?
    public var suffix: String?

    public init(
        style: MetricUnit? = nil, compact: Bool? = nil, decimals: Int? = nil,
        prefix: String? = nil, suffix: String? = nil
    ) {
        self.style = style
        self.compact = compact
        self.decimals = decimals
        self.prefix = prefix
        self.suffix = suffix
    }

    public static let automatic = WidgetFormat()
}
