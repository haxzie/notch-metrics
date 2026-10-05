import MetricsCore
import SwiftUI

/// What a widget is currently showing.
public enum TileState: Equatable, Sendable {
    case loading
    case value(MetricSeries)
    case failed(reason: String)
    case needsSetup(String)
}

/// One tile in the notch: source mark, label, headline figure, optional chart.
///
/// Renders *something* in every state. A tile that disappears while it loads
/// makes the whole row reflow under the pointer, and one that shows an error
/// dialog is worse than one showing a stale number with a mark against it.
public struct WidgetTile: View {
    public let widget: NotchWidget
    public let state: TileState
    public let accent: Color
    /// Drives the hover affordance. Only meaningful while rearranging — a
    /// highlight on a tile the user cannot move is a promise the UI does not
    /// keep.
    public let isEditing: Bool

    @State private var isHovered = false

    public init(widget: NotchWidget, state: TileState, accent: Color, isEditing: Bool = false) {
        self.widget = widget
        self.state = state
        self.accent = accent
        self.isEditing = isEditing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            source
            Text(title)
                .font(.system(size: labelSize, weight: .regular))
                .foregroundStyle(NotchTheme.secondaryText)
                .lineLimit(1)
                .padding(.top, 2)

            Spacer(minLength: 4)
            value
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(NotchTheme.tileFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    highlighted ? NotchTheme.editHighlight : NotchTheme.tileStroke,
                    lineWidth: highlighted ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onHover { hovering in
            // Tracked unconditionally rather than only in edit mode, so the
            // border is already correct on the frame edit mode turns on —
            // otherwise the tile under the pointer stays unhighlighted until
            // it moves.
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.12), value: highlighted)
    }

    private var highlighted: Bool { isEditing && isHovered }

    /// Where the number came from, as a mark rather than a word.
    ///
    /// A monochrome SF Symbol per provider, not the vendor's own logo: shipping
    /// third-party marks means an asset pipeline, a licence question for each
    /// one, and a release every time somebody rebrands. The manifest's
    /// `iconPath` exists for when that is worth doing.
    private var source: some View {
        HStack(spacing: 4) {
            Image(systemName: sourceSymbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(accent)
            if widget.size != .small, let name = sourceName {
                Text(name)
                    .font(.system(size: symbolSize - 1, weight: .semibold))
                    .foregroundStyle(NotchTheme.tertiaryText)
            }
            Spacer(minLength: 0)
            if case .value(let series) = state, series.stale {
                // Stale data is shown dimmed rather than replaced by a
                // spinner: yesterday's MRR beats nothing while a provider is
                // down, as long as it says so.
                Image(systemName: "clock")
                    .font(.system(size: 8))
                    .foregroundStyle(NotchTheme.tertiaryText)
                    .help("Showing the last value we could fetch.")
            }
        }
    }

    @ViewBuilder
    private var value: some View {
        switch state {
        case .loading:
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.07))
                .frame(height: valueFontSize * 0.8)
                .frame(maxWidth: valueFontSize * 3.2, alignment: .leading)

        case .value(let series):
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(MetricFormatter.display(series))
                        .font(.system(size: valueFontSize, weight: .regular, design: .rounded))
                        .foregroundStyle(
                            series.stale ? NotchTheme.secondaryText : NotchTheme.primaryText
                        )
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        // Rolls the digits rather than cross-fading the string,
                        // so a refresh reads as the number changing.
                        .contentTransition(.numericText(value: series.value))

                    if let delta = MetricFormatter.delta(series.delta), widget.size != .small {
                        Text(delta)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(
                                (series.delta?.percent ?? 0) >= 0
                                    ? NotchTheme.positive : NotchTheme.negative)
                    }
                }

                if widget.chart != .none, series.points.count > 1, widget.size != .small {
                    chart(for: series).frame(height: chartHeight)
                }
            }

        case .failed(let reason):
            hint(reason, symbol: "exclamationmark.triangle.fill")

        case .needsSetup(let text):
            hint(text, symbol: "link")
        }
    }

    /// At the smallest size there is room for a glyph and nothing else; words
    /// wrap and clip mid-syllable, which reads as a layout bug.
    @ViewBuilder
    private func hint(_ text: String, symbol: String) -> some View {
        if widget.size == .small {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NotchTheme.tertiaryText)
                .accessibilityLabel(text)
                .help(text)
        } else {
            Label(text, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NotchTheme.tertiaryText)
                .lineLimit(1)
                .help(text)
        }
    }

    @ViewBuilder
    private func chart(for series: MetricSeries) -> some View {
        let values = series.points.map(\.v)
        switch widget.chart {
        case .bars: MiniBars(values: values, tint: accent)
        case .sparkline: Sparkline(values: values, tint: accent)
        case .none: EmptyView()
        }
    }

    private var title: String {
        widget.title ?? widget.metric ?? widget.customMetricId ?? "Metric"
    }

    private var sourceName: String? {
        if widget.kind == .customMetric { return "Custom" }
        return nil
    }

    private var sourceSymbol: String {
        switch widget.kind {
        case .customMetric: "curlybraces"
        case .divider: "minus"
        case .providerMetric:
            switch widget.metric {
            case "mrr", "revenue": "creditcard.fill"
            case "active_subscribers", "new_subscribers": "person.2.fill"
            case "churned_subscribers": "person.fill.xmark"
            case "refunds": "arrow.uturn.backward"
            default: "chart.line.uptrend.xyaxis"
            }
        }
    }

    private var cornerRadius: CGFloat { widget.size == .small ? 12 : 16 }
    private var horizontalPadding: CGFloat { widget.size == .small ? 11 : 14 }
    private var verticalPadding: CGFloat { widget.size == .small ? 9 : 13 }
    private var symbolSize: CGFloat { widget.size == .small ? 10 : 12 }
    private var labelSize: CGFloat { widget.size == .small ? 10 : 12 }

    private var valueFontSize: CGFloat {
        switch widget.size {
        case .small: 18
        case .wide: 24
        case .square: 34
        case .hero: 44
        }
    }

    private var chartHeight: CGFloat {
        switch widget.size {
        case .small: 0
        case .wide: 18
        case .square: 26
        case .hero: 54
        }
    }
}
