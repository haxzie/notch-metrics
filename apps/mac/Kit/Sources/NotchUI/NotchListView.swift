import MetricsCore
import SwiftUI

/// The notch's other layout: rows grouped by the app they came from.
///
/// The grid tops out at six tiles on a two-row notch and starts hiding things.
/// Somebody running Stripe, Google Analytics and two custom metrics has more
/// numbers than that, and a list fits them without making each one unreadably
/// small. It is also the view where "which app is this from?" is answered by
/// position rather than by a glyph.
public struct NotchListView: View {
    @Bindable public var model: NotchLayoutModel
    public let states: [String: TileState]
    public let appOverrides: [String: MetricApp]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        model: NotchLayoutModel,
        states: [String: TileState],
        appOverrides: [String: MetricApp] = [:]
    ) {
        self.model = model
        self.states = states
        self.appOverrides = appOverrides
    }

    private var groups: [(app: MetricApp, widgets: [NotchWidget])] {
        model.displayed.groupedByApp(overrides: appOverrides)
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groups, id: \.app.id) { group in
                    Section {
                        ForEach(group.widgets) { widget in
                            MetricRow(
                                widget: widget,
                                app: group.app,
                                state: states[widget.id] ?? .loading,
                                isEditing: model.isEditing,
                                onRemove: { model.remove(widget.id) }
                            )
                        }
                    } header: {
                        AppHeader(app: group.app, count: group.widgets.count)
                    }
                }

                if groups.isEmpty { empty }
            }
            .padding(.bottom, 4)
        }
        // The scroll view is what makes the list the view that scales: the
        // handle sets the ceiling, and anything past it is a flick away
        // rather than hidden.
        //
        // Capped, not fixed. Six rows in a four-row-tall notch would otherwise
        // leave a hand's width of empty glass below the last one.
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: Self.height(for: model.displayed, overrides: appOverrides))
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: model.displayed)
    }

    private var empty: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 11))
            Text("Connect an app to see numbers here")
                .font(.system(size: 11))
        }
        .foregroundStyle(NotchTheme.tertiaryText)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
    }
}

/// The app's name over its metrics.
///
/// Pinned while scrolling, so the number you are looking at always has its
/// source visible — which is the point of grouping at all.
private struct AppHeader: View {
    let app: MetricApp
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ConnectorIcon(app: app, size: 14)

            Text(app.name)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(NotchTheme.secondaryText)

            Text("\(count)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(NotchTheme.tertiaryText)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.white.opacity(0.07)))

            Spacer(minLength: 0)
        }
        .padding(.top, 7)
        .padding(.bottom, 3)
        // The header is pinned, so it has to occlude the rows scrolling under
        // it — but a pure-black bar against a glass panel reads as a second,
        // different surface. Just opaque enough to hide text, with a hairline
        // to separate it rather than a block of colour.
        .background(Color.black.opacity(0.86))
        .overlay(alignment: .bottom) {
            Rectangle().fill(NotchTheme.tileStroke).frame(height: 1)
        }
    }
}

/// One metric, as a row.
private struct MetricRow: View {
    let widget: NotchWidget
    let app: MetricApp
    let state: TileState
    let isEditing: Bool
    let onRemove: () -> Void

    @State private var isHovered = false

    private var highlighted: Bool { isEditing && isHovered }

    var body: some View {
        HStack(spacing: 10) {
            if isEditing {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundStyle(NotchTheme.tertiaryText)
                    .frame(width: 12)
                    .transition(.opacity)
            }

            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(NotchTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(height: NotchListView.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(highlighted ? Color.white.opacity(0.05) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    highlighted ? NotchTheme.editHighlight : .clear,
                    lineWidth: highlighted ? 1.5 : 0)
        )
        .overlay(alignment: .trailing) {
            if highlighted {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(NotchTheme.negative)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
                .help("Remove")
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: highlighted)
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .loading:
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.07))
                .frame(width: 54, height: 11)

        case .value(let series):
            HStack(spacing: 8) {
                // A sparkline earns its place here only when it has something
                // to say; at row height it is 14 points tall and a flat line
                // is just noise beside the number.
                if widget.chart != .none, series.points.count > 2 {
                    Sparkline(
                        values: series.points.map(\.v),
                        tint: NotchTheme.accent(for: app),
                        fill: false
                    )
                    .frame(width: 46, height: 14)
                }

                if let delta = MetricFormatter.delta(series.delta) {
                    Text(delta)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(
                            (series.delta?.percent ?? 0) >= 0
                                ? NotchTheme.positive : NotchTheme.negative)
                }

                Text(MetricFormatter.display(series))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        series.stale ? NotchTheme.secondaryText : NotchTheme.primaryText
                    )
                    .monospacedDigit()
                    .contentTransition(.numericText(value: series.value))
                    // Right-aligned to a fixed width so the column of figures
                    // lines up. A ragged right edge is what makes a list of
                    // numbers hard to scan.
                    .frame(minWidth: 62, alignment: .trailing)
            }

        case .failed(let reason):
            hint(reason, symbol: "exclamationmark.triangle.fill")

        case .needsSetup(let text):
            hint(text, symbol: "link")
        }
    }

    private func hint(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10.5))
            .foregroundStyle(NotchTheme.tertiaryText)
            .lineLimit(1)
            .help(text)
    }

    private var title: String {
        widget.title ?? widget.metric ?? widget.customMetricId ?? "Metric"
    }
}

extension NotchListView {
    /// Tuned so a row is comfortably clickable without the list becoming a
    /// table — at 30pt a notch four rows tall shows eleven numbers.
    public static let rowHeight: CGFloat = 30
    static let headerHeight: CGFloat = 27

    /// What the list would be if nothing constrained it.
    static func contentHeight(
        for layout: NotchLayout, overrides: [String: MetricApp]
    ) -> CGFloat {
        let groups = layout.groupedByApp(overrides: overrides)
        guard !groups.isEmpty else { return 64 }
        let rows = groups.reduce(0) { $0 + $1.widgets.count }
        return CGFloat(groups.count) * headerHeight + CGFloat(rows) * rowHeight + 6
    }

    /// The height the list actually gets: what it needs, capped by what the
    /// handle allows.
    ///
    /// Used by the panel as well as by the scroll view, so the two cannot
    /// disagree — they did, and the panel kept a grid's worth of empty glass
    /// below the last row.
    public static func height(
        for layout: NotchLayout, overrides: [String: MetricApp]
    ) -> CGFloat {
        min(
            contentHeight(for: layout, overrides: overrides),
            NotchWidgetCanvas.canvasHeight(rows: layout.rows))
    }
}
