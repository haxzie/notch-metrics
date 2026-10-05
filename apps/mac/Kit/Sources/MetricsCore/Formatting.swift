import Foundation

/// Renders a metric for a tile that is sometimes 56 points wide.
public enum MetricFormatter {
    /// Currency values arrive in minor units; everything else is a plain number.
    public static func display(_ series: MetricSeries, compact: Bool? = nil) -> String {
        let useCompact = compact ?? series.format?.compact ?? true

        switch series.unit {
        case .currency:
            let major = series.value / 100
            return currency(major, code: series.currency ?? "USD", compact: useCompact)
        case .count:
            return useCompact ? abbreviated(series.value) : integer(series.value)
        case .ratio:
            return String(format: "%.1f%%", series.value * 100)
        case .duration:
            return duration(series.value)
        case .bytes:
            return bytes(series.value)
        }
    }

    public static func currency(_ amount: Double, code: String, compact: Bool) -> String {
        let symbol = symbols[code] ?? "\(code) "
        // Compacted above four figures, because "$1,284,500" does not fit a
        // 2x1 tile and truncating it mid-number is worse than rounding it.
        if compact, abs(amount) >= 10_000 { return symbol + abbreviated(amount) }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = abs(amount) >= 1_000 ? 0 : 2
        formatter.minimumFractionDigits = 0
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

    public static func integer(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
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
