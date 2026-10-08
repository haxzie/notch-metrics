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
    /// Which app the number came from. Supplies the mark, the name and the
    /// tile's accent — two Stripe tiles should look like two Stripe tiles,
    /// not like tile one and tile two.
    public let app: MetricApp
    public let state: TileState
    /// Drives the hover affordance. Only meaningful while rearranging — a
    /// highlight on a tile the user cannot move is a promise the UI does not
    /// keep.
    public let isEditing: Bool
    /// What the account is called. Falls back to the app's name, which is all
    /// there is for a gallery preview or a widget with nothing connected.
    public var connectionName: String?
    /// Whether the pointer is over this tile.
    ///
    /// Passed in rather than tracked here. A local `.onHover` is a second
    /// opinion about the same pointer, and it disagreed with the canvas's:
    /// the highlight landed on one tile while the badges landed on another.
    /// One source, resolved from the pointer against the grid.
    public let isHovered: Bool

    public init(
        widget: NotchWidget, app: MetricApp, state: TileState, isEditing: Bool = false,
        isHovered: Bool = false, connectionName: String? = nil
    ) {
        self.widget = widget
        self.app = app
        self.state = state
        self.isEditing = isEditing
        self.connectionName = connectionName
        self.isHovered = isHovered
    }

    private var accent: Color { NotchTheme.accent(for: app) }
    /// The widget's own colour first, then the app's, then the theme's lift.
    /// A widget can say "this one is lime" without the app catalogue having
    /// to learn about it.
    private var chartTint: Color {
        if let hex = widget.chartStyle?.tintHex, let colour = Color(hex: hex) { return colour }
        return NotchTheme.chartTint(for: app)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            source
            Text(title)
                .font(.system(size: labelSize, weight: .regular))
                .foregroundStyle(NotchTheme.secondaryText)
                .lineLimit(1)
                .padding(.top, labelGap)

            // A Spacer either side rather than one above: the number sits in
            // the middle of whatever height is left under the label, which
            // keeps it on the same line across tiles of different heights.
            // Pinned to the bottom, a 2x2 and a 2x1 side by side had their
            // figures at different heights and the row read as misaligned.
            Spacer(minLength: 0)
            value
            Spacer(minLength: 0)

            // Always the bottom edge, never under the number. The chart used
            // to live inside the value stack, so it floated with the figure
            // and sat at a different height on every tile.
            if case .value(let series) = state,
               widget.chart != .none, series.points.count > 1, widget.size != .small {
                chart(for: series)
                    .frame(height: chartHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                // The same translucent fill in edit mode as out of it. Edit
                // mode used to swap in a near-solid dark, which made the
                // tiles turn opaque the moment you started arranging them —
                // so the thing you were rearranging did not look like the
                // thing you would end up with.
                .fill(NotchTheme.tileFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    highlighted ? NotchTheme.editHighlight : NotchTheme.tileStroke,
                    lineWidth: highlighted ? 2 : 1)
        )
        // A backstop, not the fix. The sizes above are tuned to fit, but a
        // long number or a future span should crop at the corner rather than
        // paint over it.
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.12), value: highlighted)
    }

    private var highlighted: Bool { isEditing && isHovered }

    /// Which app the number came from, as a mark and a name.
    ///
    /// The real brand mark, same as everywhere else.
    ///
    /// This used to be the SF Symbol, which for Dodo Payments meant a generic
    /// bird tinted `#111111` — the wrong logo, and near-invisible against a
    /// dark tile. A symbol is a reasonable fallback for a connector with no
    /// vendored mark; it is not a substitute for one that has it.
    private var source: some View {
        HStack(spacing: 4) {
            ConnectorIcon(app: app, size: markSize)
            if widget.size != .small {
                Text(connectionName ?? app.name)
                    .font(.system(size: symbolSize - 1, weight: .semibold))
                    .foregroundStyle(NotchTheme.tertiaryText)
                    .lineLimit(1)
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
                    Text(MetricFormatter.display(series, override: widget.format))
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
        case .bars:
            MiniBars(values: values, tint: chartTint)
        case .sparkline:
            Sparkline(
                values: values, tint: chartTint,
                fill: widget.chartStyle?.fill ?? true,
                fillOpacity: widget.chartStyle?.fillOpacity ?? 0.45)
        case .none: EmptyView()
        }
    }

    private var title: String {
        widget.title ?? widget.metric ?? widget.customMetricId ?? "Metric"
    }



    /// The smallest span: one cell, room for a mark and a number.
    private var isTiny: Bool { widget.size.cols == 1 && widget.size.rows == 1 }

    private var cornerRadius: CGFloat { isTiny ? 12 : 16 }
    private var horizontalPadding: CGFloat { isTiny ? 11 : 14 }
    /// A one-row tile is 84pt tall and has to hold a mark, a label, a figure
    /// and a chart. Thirteen points of padding top and bottom does not leave
    /// room for all four, which is how the content came to overflow its own
    /// rounded corners.
    private var verticalPadding: CGFloat { widget.size.rows == 1 ? 8 : 13 }
    private var symbolSize: CGFloat { isTiny ? 10 : 12 }
    /// Slightly larger than the old glyph: a mark inside a rounded tile needs
    /// the extra point or two to stay readable once its own corners are cut.
    private var markSize: CGFloat { isTiny ? 13 : 15 }

    /// Between the source row and the metric's own label.
    ///
    /// At 2 the two lines read as one block and the app name looked like a
    /// heading the label was wrapped from. A 1x1 keeps it tighter — there is
    /// no app name up there to separate from.
    private var labelGap: CGFloat { isTiny ? 3 : 7 }
    private var labelSize: CGFloat { isTiny ? 10 : 12 }

    /// Scales with the span rather than switching on four presets, now that
    /// every size between 1x1 and the full grid can exist.
    ///
    /// Driven by width and height together: a 6x1 is wide but short, and
    /// sizing its figure off the width alone overflows the tile vertically.
    private var valueFontSize: CGFloat {
        let byWidth = 14 + CGFloat(widget.size.cols) * 5.5
        // One row is the tight case and gets its own number rather than a
        // formula that happens to be close: everything else above it is a
        // fixed height, so what is left for the figure is known.
        let byHeight: CGFloat = widget.size.rows == 1 ? 21 : 10 + CGFloat(widget.size.rows) * 17
        return min(min(byWidth, byHeight), 48)
    }

    private var chartHeight: CGFloat {
        guard widget.size.rows > 1 || widget.size.cols > 1 else { return 0 }
        if widget.size.rows == 1 { return 12 }
        return min(CGFloat(widget.size.rows) * 24 - 6, 60)
    }
}
