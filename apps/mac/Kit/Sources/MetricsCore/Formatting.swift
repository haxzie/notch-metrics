import Foundation

/// Renders a metric for a tile that is sometimes 56 points wide.
public enum MetricFormatter {
    /// Currency values arrive in minor units; everything else is a plain number.
    ///
    /// `override` is the widget's own format and wins over the series, which
    /// in turn wins over the defaults. The adapter knows whether it fetched
    /// money; only the tile knows whether it has room for all the digits.
    public static func display(
        _ series: MetricSeries, override: WidgetFormat? = nil, compact: Bool? = nil
    ) -> String {
        let style = override?.style ?? series.unit
        let useCompact = compact ?? override?.compact ?? series.format?.compact ?? true
        // The series' own, where the widget has not overridden it. Search
        // Console sends `decimals: 1` with an average position precisely so
        // the tile reads 8.4 rather than 8 — and this used to read only the
        // widget's, so the adapter's instruction was dropped and a rank
        // rounded to the integer it is never quoted as.
        let decimals = override?.decimals ?? series.format?.decimals

        let body: String
        switch style {
        case .currency:
            let major = series.value / 100
            body = currency(
                major, code: series.currency ?? "USD", compact: useCompact, decimals: decimals)
        case .count:
            body = useCompact ? abbreviated(series.value) : integer(series.value, decimals: decimals)
        case .ratio:
            body = String(format: "%.\(decimals ?? 1)f%%", series.value * 100)
        case .duration:
            body = duration(series.value)
        case .bytes:
            body = bytes(series.value)
        }

        let prefix = override?.prefix ?? series.format?.prefix ?? ""
        let suffix = override?.suffix ?? series.format?.suffix ?? ""
        return prefix + body + suffix
    }

    public static func currency(
        _ amount: Double, code: String, compact: Bool, decimals: Int? = nil
    ) -> String {
        let symbol = symbols[code] ?? "\(code) "
        // Compacted from four figures, matching `count`. The two thresholds
        // used to differ — 10,000 here and 1,000 there — so $9,800 rendered
        // in full beside 9.8k of anything else, on tiles the same width.
        if compact, abs(amount) >= 1_000 { return symbol + abbreviated(amount) }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = decimals ?? (abs(amount) >= 1_000 ? 0 : 2)
        // Cents are all-or-nothing. With a floor of zero, $428.60 rendered as
        // "$428.6" — a figure that is not a price in any currency, and the
        // sort of thing somebody notices on a screenshot before they notice
        // anything else.
        formatter.minimumFractionDigits =
            formatter.maximumFractionDigits > 0 && amount != amount.rounded()
            ? min(2, formatter.maximumFractionDigits) : 0
        // Explicit, because NumberFormatter defaults to half-*even* — so
        // $1,284.50 would render as $1,284. Banker's rounding is right for
        // statistics and wrong for a figure somebody is going to compare
        // against their Stripe dashboard.
        formatter.roundingMode = .halfUp
        return symbol + (formatter.string(from: NSNumber(value: amount)) ?? "\(amount)")
    }

    public static func abbreviated(_ value: Double) -> String {
        let magnitude = abs(value)
        let sign = value < 0 ? "-" : ""
        switch magnitude {
        case 1_000_000_000...:
            return "\(sign)\(trim(magnitude / 1_000_000_000))B"
        case 1_000_000...:
            return "\(sign)\(trim(magnitude / 1_000_000))M"
        case 1_000...:
            return "\(sign)\(trim(magnitude / 1_000))k"
        default:
            return integer(value)
        }
    }

    /// Drops a trailing ".0" so tiles read "12k" rather than "12.0k".
    private static func trim(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }

    public static func integer(_ value: Double, decimals: Int? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = decimals ?? 0
        return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    public static func duration(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return String(format: "%.1fh", seconds / 3600)
    }

    public static func bytes(_ value: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary)
    }

    /// "just now", "4m", "2h", "3d" — the age of a list row.
    ///
    /// Units only, no "ago": a list row has about 30 points for its time
    /// and the column reads as ages without the word.
    public static func age(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        if seconds < 86_400 * 30 { return "\(Int(seconds / 86_400))d" }
        return "\(Int(seconds / (86_400 * 30)))mo"
    }

    /// A list row's amount: minor units in, "$49.00" out, never compacted.
    ///
    /// A row is a single payment and the exact figure is the point of
    /// listing it. The headline compacts; rows do not.
    public static func amount(_ minor: Double, code: String) -> String {
        currency(minor / 100, code: code, compact: false, decimals: 2)
    }

    /// "+7.9%" / "−3.2%", with a true minus sign rather than a hyphen.
    public static func delta(_ delta: MetricDelta?) -> String? {
        guard let percent = delta?.percent else { return nil }
        let sign = percent >= 0 ? "+" : "\u{2212}"
        return "\(sign)\(String(format: "%.1f", abs(percent)))%"
    }

    private static let symbols: [String: String] = [
        "USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥", "INR": "₹",
        "AUD": "A$", "CAD": "C$", "CHF": "CHF ", "SEK": "kr ", "BRL": "R$",
    ]
}
