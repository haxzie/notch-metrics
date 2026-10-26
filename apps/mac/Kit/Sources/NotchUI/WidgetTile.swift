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
    /// What the account is called. Shown when the widget has no name of its
    /// own; falls back to the app's name, which is all there is for a gallery
    /// preview or a widget with nothing connected.
    public var connectionName: String?
    /// Whether the pointer is over this tile.
    ///
    /// Passed in rather than tracked here. A local `.onHover` is a second
    /// opinion about the same pointer, and it disagreed with the canvas's:
    /// the highlight landed on one tile while the badges landed on another.
    /// One source, resolved from the pointer against the grid.
    public let isHovered: Bool
    /// Whether the metric's number depends on the widget's time window, in
    /// which case the window is written into the title. Comes from the
    /// metric's descriptor, which only the app holds; false until it says so,
    /// because a snapshot gaining a range it does not use is the worse
    /// mistake.
    public let showsRange: Bool

    public init(
        widget: NotchWidget, app: MetricApp, state: TileState, isEditing: Bool = false,
        isHovered: Bool = false, connectionName: String? = nil, showsRange: Bool = false
    ) {
        self.widget = widget
        self.app = app
        self.state = state
        self.isEditing = isEditing
        self.connectionName = connectionName
        self.isHovered = isHovered
        self.showsRange = showsRange
    }

    private var accent: Color { NotchTheme.accent(for: app) }
    /// The widget's own colour first, then the app's, then the theme's lift.
    /// A widget can say "this one is lime" without the app catalogue having
    /// to learn about it.
    private var chartTint: Color {
        if let hex = widget.chartStyle?.tintHex, let colour = Color(hex: hex) { return colour }
        return NotchTheme.chartTint(for: app)
    }

    /// Whether the tile is wide enough, and short enough, to read as a row.
    ///
    /// A long one-row tile stacks badly: the label takes the top, the figure
    /// the middle, and everything past the second column is empty. Wide
    /// enough, the natural reading is left-to-right — what this is, then what
    /// it says — which is also how the list view already reads.
    ///
    /// "Wide enough" starts at three columns. Two is the size where a stacked
    /// label over a figure is exactly right, and where a row has width for
    /// neither.
    ///
    /// Two rows or more have the height for the stacked layout, and that is
    /// what the gauge and the charts are drawn for.
    var readsAsRow: Bool {
        // Three columns, not two. A 2x1 has room for a name or a figure, not
        // both: side by side it truncated everything to "Claude us…", "Out…"
        // and "90…." — three ellipses where there had been a readable tile.
        guard widget.size.rows == 1, widget.size.cols >= 3 else { return false }
        // A list drawn as *text* is already rows and has no headline figure
        // to put on the right, so it keeps the stacked layout at every size.
        // Drawn as a split bar it is one object and sits on a line happily.
        if case .value(let series) = state, series.items != nil {
            return widget.chart == .split
        }
        return true
    }

    /// Name on the left, number on the right, centred against each other.
    ///
    /// The right-hand block is given only the width it needs, so the name has
    /// the rest — a long connection label is what actually runs out of room on
    /// a row, not the figure.
    @ViewBuilder
    private var rowBody: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                source
                titleText
                    .font(.system(size: labelSize, weight: .regular))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .lineLimit(1)
                    .accessibilityLabel(title)
            }

            Spacer(minLength: 8)

            switch state {
            case .loading:
                TileSkeleton(
                    valueHeight: valueFontSize, chartHeight: skeletonChartHeight,
                    chart: widget.chart)
                    .frame(maxWidth: 180)

            case .value(let series) where drawsDistribution(series):
                distribution(series, compact: true)
                    .frame(maxWidth: rowChartWidth)

            case .value(let series) where drawsGauge(series):
                // Sized to the line and kept to the semicircle's own 2:1, so
                // the arc is not clipped by a frame taller than it can fill.
                gauge(for: series)
                    .frame(width: rowGaugeHeight * 2, height: rowGaugeHeight)

            case .value(let series):
                value
                if widget.chart != .none, series.points.count > 1 {
                    chart(for: series)
                        .frame(width: rowChartWidth, height: rowChartHeight)
                }

            default:
                value
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// How much of a row the chart may take.
    ///
    /// Proportional to the tile, not fixed: a 2x1 has barely room for the
    /// figure, where a 6x1 can give the chart half the row and still leave the
    /// name space.
    var rowChartWidth: CGFloat { widget.size.cols >= 4 ? 150 : 90 }
    private var rowChartHeight: CGFloat { 30 }
    /// The arc keeps its own 2:1 so a taller frame cannot clip it.
    private var rowGaugeHeight: CGFloat { 34 }

    @ViewBuilder
    private var stackedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            source
            titleText
                .font(.system(size: labelSize, weight: .regular))
                .foregroundStyle(NotchTheme.secondaryText)
                .lineLimit(1)
                .padding(.top, labelGap)
                .accessibilityLabel(title)

            // A Spacer either side rather than one above: the number sits in
            // the middle of whatever height is left under the label, which
            // keeps it on the same line across tiles of different heights.
            // Pinned to the bottom, a 2x2 and a 2x1 side by side had their
            // figures at different heights and the row read as misaligned.
            if case .loading = state {
                // One view for the whole body rather than a bar here and a
                // block below: the skeleton has to lay out as a unit to sit
                // where the figure and the chart actually will.
                TileSkeleton(
                    valueHeight: valueFontSize, chartHeight: skeletonChartHeight,
                    chart: widget.chart)
            } else if case .value(let series) = state, drawsDistribution(series) {
                // The rows, drawn rather than listed. Same data as the text
                // list below; which one you get is the chart you chose.
                //
                // Height-capped: a tile that grows to fit its content is a
                // tile taller than the one beside it, and the grid's whole
                // premise is that a 2x2 is a 2x2.
                distribution(series, compact: false)
                    .padding(.top, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
            } else if case .value(let series) = state, let items = series.items {
                // A list fills the tile from the label down. The headline
                // figure is dropped: the rows are the number, itemised.
                list(items, stale: series.stale)
                    .padding(.top, 6)
                Spacer(minLength: 0)
            } else if case .value(let series) = state, drawsGauge(series) {
                // In place of the figure, not under it: the arc contains the
                // number, so drawing both would print it twice.
                gauge(for: series)
                    .padding(.top, 2)
            } else {
                Spacer(minLength: 0)
                value
                Spacer(minLength: 0)
            }

            // Always the bottom edge, never under the number. The chart used
            // to live inside the value stack, so it floated with the figure
            // and sat at a different height on every tile.
            //
            // A gauge is drawn above, in the figure's place, and needs no
            // points — which is also why `points.count > 1` cannot gate it.
            if case .value(let series) = state, !drawsGauge(series),
                widget.chart != .none, series.points.count > 1, widget.size != .small
            {
                chart(for: series)
                    .frame(height: chartHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    public var body: some View {
        Group {
            if readsAsRow { rowBody } else { stackedBody }
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
                Text(widget.name ?? connectionName ?? app.name)
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
            // Drawn by `TileSkeleton` in the body, which needs the chart and
            // the figure together to place them.
            EmptyView()

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

    /// The rows of a list widget, as many as the tile has room for.
    ///
    /// Clipped to a count rather than left to overflow: a row cut in half
    /// by the tile's corner reads as a rendering fault, and a row that is
    /// not there reads as a shorter list.
    @ViewBuilder
    private func list(_ items: [MetricListItem], stale: Bool) -> some View {
        if items.isEmpty {
            Text("Nothing yet")
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.tertiaryText)
        } else {
            VStack(alignment: .leading, spacing: listRowSpacing) {
                ForEach(items.prefix(listRows)) { item in
                    row(item, stale: stale)
                }
            }
        }
    }

    private func row(_ item: MetricListItem, stale: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // Leading, and only when the row has an outcome. A payments feed
            // has none, and a column of identical dots down the left of one
            // would be decoration that costs the label its width.
            if let state = item.state {
                StateDot(state: state, size: listFontSize)
            }
            Text(item.label)
                .font(.system(size: listFontSize, weight: .medium))
                .foregroundStyle(stale ? NotchTheme.secondaryText : NotchTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            if let detail = item.detail, widget.size.cols >= 3 {
                Text(detail)
                    .font(.system(size: listFontSize - 1))
                    .foregroundStyle(NotchTheme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 4)
            if let amount = item.amount {
                Text(MetricFormatter.amount(amount, code: item.currency ?? "USD"))
                    .font(.system(size: listFontSize, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    // A refund still lists — it happened — but reads as one.
                    .foregroundStyle(
                        item.status?.contains("refund") == true
                            ? NotchTheme.negative : NotchTheme.primaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let date = item.date, !isTiny {
                Text(MetricFormatter.age(date))
                    .font(.system(size: listFontSize - 2))
                    .foregroundStyle(NotchTheme.tertiaryText)
                    .monospacedDigit()
                    .frame(width: 24, alignment: .trailing)
            }
        }
        .help([item.label, item.detail, item.status].compactMap { $0 }.joined(separator: " · "))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [item.state?.spokenOutcome, item.label, item.detail]
                .compactMap { $0 }.joined(separator: ", "))
    }

    /// Rows per tile height: two on a one-row tile, then three more per row.
    /// Derived from the same 84pt-per-row the grid uses, less the header.
    private var listRows: Int { widget.size.rows == 1 ? 2 : 2 + (widget.size.rows - 1) * 3 }

    /// Rows a *ranked* distribution has room for.
    ///
    /// Fewer than the text list, because a ranked row is three things — the
    /// name, the figure beside it and the bar under it — where a list row is
    /// one line. Reusing the list's budget overflowed a 2x2 and pushed the
    /// tile taller than its neighbours.
    private var rankedRows: Int {
        widget.size.rows <= 1 ? 2 : 3 + (widget.size.rows - 2) * 3
    }
    /// Lines of key a *split* tile has room for under its bar.
    ///
    /// One more than `rankedRows` at each height, because a legend row is a
    /// single line where a ranked row is a name, a figure and a bar. Zero at
    /// one row tall: the bar fills that tile on its own, and in a row layout
    /// it shares the line with the title already.
    private var legendRows: Int {
        widget.size.rows <= 1 ? 0 : 3 + (widget.size.rows - 2) * 4
    }
    private var listRowSpacing: CGFloat { isTiny ? 2 : 4 }
    private var listFontSize: CGFloat { isTiny ? 9 : 11 }

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
        case .gauge, .none, .split, .ranked, .pie: EmptyView()
        }
    }

    /// Whether this tile draws its rows as a distribution rather than text.
    ///
    /// Needs both: a chart that draws categories, and a list to draw. A
    /// distribution chosen on a metric that turned out to have no rows falls
    /// back to the text list rather than an empty tile.
    private func drawsDistribution(_ series: MetricSeries) -> Bool {
        widget.chart.isDistribution && !(series.items ?? []).isEmpty
    }

    /// The rows of a list as shares of their total.
    ///
    /// `amount` first, then the number inside `detail` — a connector may put
    /// the figure in either, and a distribution needs a magnitude per row. A
    /// list with no magnitudes anywhere is drawn as equal slices, which is
    /// honest: it says "these are the categories" without inventing weights.
    private func shares(_ items: [MetricListItem]) -> [Double] {
        let values = items.map { item -> Double in
            if let amount = item.amount { return abs(Double(amount)) }
            let digits = (item.detail ?? "").filter { $0.isNumber || $0 == "." }
            return Double(digits) ?? 0
        }
        return values.allSatisfy { $0 == 0 } ? items.map { _ in 1 } : values
    }

    @ViewBuilder
    private func distribution(_ series: MetricSeries, compact: Bool) -> some View {
        let items = series.items ?? []
        let weights = shares(items)
        switch widget.chart {
        case .split:
            // The bar, then its key. A split bar is the one distribution that
            // says nothing about *what* its slices are: the ranked bars and
            // the ring both carry their labels, where this was four coloured
            // segments and no way to tell which was which.
            VStack(alignment: .leading, spacing: 7) {
                SplitBar(shares: weights, height: compact ? 8 : 10)
                SliceLegend(
                    rows: items.indices.map { index in
                        SliceLegend.Row(
                            id: items[index].id, label: items[index].label,
                            detail: items[index].detail, colourIndex: index)
                    },
                    fontSize: listFontSize,
                    maxRows: compact ? 0 : legendRows)
            }
        case .pie:
            // The total in the hole. A list tile normally drops the headline
            // figure, because the rows *are* the figure itemised — a ring has
            // the one place where showing it again costs nothing.
            PieChart(shares: weights) {
                Text(MetricFormatter.display(series, override: widget.format))
                    .font(
                        .system(
                            size: valueFontSize * (compact ? 0.6 : 0.72), weight: .semibold,
                            design: .rounded)
                    )
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        default:
            RankedBars(
                rows: Array(zip(items, weights.indices)).map { item, index in
                    RankedBars.Row(
                        id: item.id, label: item.label, detail: item.detail,
                        share: weights[index] / max(weights.reduce(0, +), 1))
                },
                fontSize: listFontSize,
                maxRows: rankedRows)
        }
    }

    /// Whether this tile draws its figure as a gauge.
    ///
    /// Needs a ceiling to be a share *of* something, and `ratio` is the only
    /// unit that carries one — 1.0, by definition. A gauge on a count would be
    /// an arc filled to an arbitrary fraction of nothing.
    private func drawsGauge(_ series: MetricSeries) -> Bool {
        widget.chart == .gauge && series.unit == .ratio && series.items == nil
    }

    /// The figure inside its arc.
    @ViewBuilder
    private func gauge(for series: MetricSeries) -> some View {
        GaugeArc(
            fraction: series.value,
            tint: chartTint,
            lineWidth: isTiny ? 5 : 8
        ) {
            Text(MetricFormatter.display(series, override: widget.format))
                .font(.system(size: valueFontSize * 0.78, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(NotchTheme.primaryText)
        }
    }

    private var title: String { widget.displayTitle(showingRange: showsRange) }

    /// The name at full strength and the window a step quieter.
    ///
    /// Both in the label's colour, but the range at 70% of it: the name is
    /// what the eye looks for and the window is a qualifier on it. At equal
    /// weight "Revenue · 30d" read as one three-word title and the range
    /// competed with the name on every tile.
    private var titleText: Text {
        guard showsRange else { return Text(widget.baseTitle) }
        return Text(widget.baseTitle)
            + Text(" · \(widget.range.rawValue)")
            .foregroundStyle(NotchTheme.secondaryText.opacity(0.7))
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

    /// The chart block's height for a tile with no data yet.
    ///
    /// Gated on the same conditions the real chart is, minus the point count
    /// — which is the one thing a loading tile cannot know. A widget set to
    /// draw no chart gets no chart-shaped hole.
    private var skeletonChartHeight: CGFloat {
        guard widget.chart != .none, widget.size != .small else { return 0 }
        return chartHeight
    }

    private var chartHeight: CGFloat {
        guard widget.size.rows > 1 || widget.size.cols > 1 else { return 0 }
        if widget.size.rows == 1 { return 12 }
        return min(CGFloat(widget.size.rows) * 24 - 6, 60)
    }
}

/// A list row's outcome, as a glyph.
///
/// Symbol *and* colour, not colour alone: a green dot and a red dot are the
/// same dot to a good number of people, and this is a control whose whole job
/// is to be read at a glance from the corner of an eye.
///
/// Sized from the row's own font so it lines up with the label on a tiny tile
/// as well as a tall one, and rendered as a `Label`-less image because the
/// text beside it is the label.
struct StateDot: View {
    let state: MetricListItemState
    let size: CGFloat

    var body: some View {
        Image(systemName: state.symbolName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(state.tint)
            .frame(width: size + 2)
            // Spins while something is actually running, and only then: a
            // notch is in the corner of the eye all day, and a thing that
            // moves for no reason is the one thing nobody can ignore.
            .symbolEffect(.pulse, isActive: state == .running)
            .accessibilityHidden(true)
    }
}

extension MetricListItemState {
    var symbolName: String {
        switch self {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .running: "circle.dotted"
        case .neutral: "minus.circle.fill"
        // A state this build has never heard of is drawn as an empty circle
        // rather than guessed at. Nothing claimed is better than green for a
        // run that failed in a way we do not know about yet.
        case .unknown: "circle"
        }
    }

    var tint: Color {
        switch self {
        case .succeeded: NotchTheme.positive
        case .failed: NotchTheme.negative
        case .running: NotchTheme.warning
        case .neutral, .unknown: NotchTheme.tertiaryText
        }
    }

    /// What VoiceOver reads before the row's label.
    var spokenOutcome: String? {
        switch self {
        case .succeeded: "Passed"
        case .failed: "Failed"
        case .running: "Running"
        case .neutral: "Skipped"
        case .unknown: nil
        }
    }
}

/// The "this number is being checked" indicator, in a tile's trailing corner.
///
/// Drawn rather than an `NSProgressIndicator`: the AppKit spinner brings its
/// own sizing and a system tint that reads as a sheet loading rather than as a
/// figure being refreshed, and at this size its hub is a grey smudge.
///
/// Only ever on screen while a fetch is in flight *and* the notch is open, so
/// the `repeatForever` animation cannot idle in the background — the grid is
/// not rendered at all when the notch is collapsed.
struct TileSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        Circle()
            // Not a full ring: a gap is what makes the rotation legible. A
            // complete circle spinning looks static.
            .trim(from: 0, to: 0.7)
            .stroke(
                NotchTheme.secondaryText,
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 11, height: 11)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(
                reduceMotion
                    ? nil
                    : .linear(duration: 0.85).repeatForever(autoreverses: false),
                value: turning)
            // Reduce Motion gets the same arc, held still. Swapping it for a
            // pulse would be a second thing to look at; the arc's presence is
            // already the message, and the spin is only the polish.
            .opacity(reduceMotion ? 0.75 : 1)
            .onAppear { turning = true }
            .accessibilityLabel("Refreshing")
    }
}
