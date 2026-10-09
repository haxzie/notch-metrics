import Foundation

/// NotchWidget sizes on the notch's 8x2 grid.
///
/// A closed set rather than free integers, so resize snaps to something the
/// packer can reason about and a drag cannot produce a 3x1 nothing else knows
/// how to lay out.
/// Widget sizes on the notch's six-column grid.
///
/// A closed set rather than free integers, so a resize snaps to something the
/// packer can reason about and a drag cannot produce a shape nothing else
/// knows how to lay out.
/// How many cells a widget spans.
///
/// A span, not a closed set. It used to be an enum of four presets, which is
/// why resizing was a button that cycled through them — there was nothing
/// else it could do. Handles on the corners and edges need every size between
/// 1x1 and the full grid to exist.
///
/// The wire encoding is unchanged: still `"<cols>x<rows>"`, so a `layout.json`
/// or a `PUT /v1/widgets` written by any previous build decodes as it did.
/// Only the set of accepted values is wider.
public struct WidgetSize: Codable, Sendable, Hashable, RawRepresentable, CustomStringConvertible {
    public let cols: Int
    public let rows: Int

    public static let maxCols = NotchLayout.columns
    public static let maxRows = 4

    public init(cols: Int, rows: Int) {
        self.cols = min(max(1, cols), Self.maxCols)
        self.rows = min(max(1, rows), Self.maxRows)
    }

    // MARK: Presets, kept so existing call sites and tests still read well.

    /// A sixth of the width. A number, no chart.
    public static let small = WidgetSize(cols: 1, rows: 1)
    /// A third of the width — three across, which is the default arrangement.
    public static let wide = WidgetSize(cols: 2, rows: 1)
    /// A third of the width, full height. Logo, label, headline figure.
    public static let square = WidgetSize(cols: 2, rows: 2)
    /// The full width of the grid, both rows. One large chart.
    public static let hero = WidgetSize(cols: 6, rows: 2)

    /// What the size picker offers. Every span is reachable by dragging a
    /// handle; these are the ones worth one click.
    public static let presets: [WidgetSize] = [.small, .wide, .square, .hero]

    // MARK: Wire format

    public var rawValue: String { "\(cols)x\(rows)" }
    public var description: String { rawValue }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "x")
        guard parts.count == 2,
              let cols = Int(parts[0]), let rows = Int(parts[1]),
              cols >= 1, rows >= 1
        else { return nil }
        self.init(cols: cols, rows: rows)
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Falls back rather than throwing, for the same reason every enum on
        // this wire has an unknown case: one unfamiliar value must not fail
        // the decode of a whole layout.
        self = WidgetSize(rawValue: raw) ?? .wide
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum WidgetKind: String, Codable, Sendable, Hashable {
    case providerMetric = "provider_metric"
    case customMetric = "custom_metric"
    case divider
}

public enum ChartKind: String, Codable, Sendable, Hashable {
    case none, sparkline, bars
}

/// Tiles on a grid, or rows grouped by app.
///
/// The list is not a lesser view. The grid tops out at six tiles and starts
/// hiding things; the list fits a dozen numbers from four apps into the same
/// space, which is what somebody with Stripe, Google Analytics and two custom
/// metrics actually has.

public struct NotchWidget: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var kind: WidgetKind

    /// Which app this number comes from. See `AppCatalog`.
    ///
    /// Held on the widget rather than looked up through `integrationId`,
    /// because a widget whose integration was disconnected still has to
    /// render — it becomes a "reconnect Stripe" tile, and it cannot name the
    /// app to reconnect if the only link was the row that was deleted.
    public var appId: String

    public var integrationId: String?
    public var metric: String?
    public var customMetricId: String?
    public var title: String?
    /// What the tile calls its source, in place of the connection's name.
    ///
    /// The widget's own, not the connection's: the field is prefilled from
    /// the account so two Stripe tiles can be told apart, but typing over it
    /// must not rename the account under every other tile reading it. Nil
    /// means "say what the connection is called".
    public var name: String?
    public var size: WidgetSize
    public var col: Int
    public var row: Int
    public var position: Int
    public var granularity: Granularity
    public var range: TimeRange
    public var chart: ChartKind

    /// What this widget asks its metric for, beyond the window.
    ///
    /// A GitHub tile's repository lives here. On the widget rather than on
    /// the connection, so one GitHub account serves a tile per repository
    /// instead of a connection each. Which keys a metric takes is declared by
    /// the server in `MetricDescriptor.params`; nothing here interprets them.
    public var params: [String: String]

    /// How the number reads. Nil means "whatever the series says".
    public var format: WidgetFormat?
    /// How the chart draws. Nil means "whatever the app's colours say".
    public var chartStyle: WidgetChartStyle?
    public var visible: Bool

    public init(
        id: String = UUID().uuidString, kind: WidgetKind = .providerMetric,
        appId: String = AppCatalog.unknownId,
        integrationId: String? = nil, metric: String? = nil, customMetricId: String? = nil,
        title: String? = nil, name: String? = nil, size: WidgetSize = .wide, col: Int = 0,
        row: Int = 0,
        position: Int = 0, granularity: Granularity = .day, range: TimeRange = .month,
        chart: ChartKind = .sparkline, params: [String: String] = [:],
        format: WidgetFormat? = nil,
        chartStyle: WidgetChartStyle? = nil, visible: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.appId = appId
        self.integrationId = integrationId
        self.metric = metric
        self.customMetricId = customMetricId
        self.title = title
        self.name = name
        self.size = size
        self.col = col
        self.row = row
        self.position = position
        self.granularity = granularity
        self.range = range
        self.chart = chart
        self.params = params
        self.format = format
        self.chartStyle = chartStyle
        self.visible = visible
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, appId, integrationId, metric, customMetricId, title, name, size
        case col, row, position, granularity, range, chart, params, format, chartStyle, visible
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(WidgetKind.self, forKey: .kind)
        integrationId = try c.decodeIfPresent(String.self, forKey: .integrationId)
        metric = try c.decodeIfPresent(String.self, forKey: .metric)
        customMetricId = try c.decodeIfPresent(String.self, forKey: .customMetricId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        size = try c.decodeIfPresent(WidgetSize.self, forKey: .size) ?? .wide
        col = try c.decodeIfPresent(Int.self, forKey: .col) ?? 0
        row = try c.decodeIfPresent(Int.self, forKey: .row) ?? 0
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        granularity = try c.decodeIfPresent(Granularity.self, forKey: .granularity) ?? .day
        range = try c.decodeIfPresent(TimeRange.self, forKey: .range) ?? .month
        chart = try c.decodeIfPresent(ChartKind.self, forKey: .chart) ?? .sparkline
        // Absent in every layout.json written before per-widget parameters
        // existed. Empty is the honest reading: those widgets belong to
        // connections that still carry their own repository, and the server
        // falls back to it.
        params = try c.decodeIfPresent([String: String].self, forKey: .params) ?? [:]
        // Absent in every layout.json written before formats existed, and nil
        // means "use the series", so those widgets render exactly as they did.
        format = try c.decodeIfPresent(WidgetFormat.self, forKey: .format)
        chartStyle = try c.decodeIfPresent(WidgetChartStyle.self, forKey: .chartStyle)
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true

        // Users have a layout.json from before apps existed. Rather than
        // stranding those widgets under "Unknown", infer what we can: a
        // custom metric is at least "custom", and anything else keeps its
        // place until the next sync from the server fills it in properly.
        if let declared = try c.decodeIfPresent(String.self, forKey: .appId), !declared.isEmpty {
            appId = declared
        } else {
            appId = kind == .customMetric ? AppCatalog.customId : AppCatalog.unknownId
        }
    }
}

extension NotchWidget {
    /// The name on the tile before any time window is appended.
    public var baseTitle: String {
        title ?? metric ?? customMetricId ?? "Metric"
    }

    /// The label the tile shows.
    ///
    /// A widget whose number depends on a time window carries that window in
    /// its title — `Revenue · 30d` — because "Revenue" alone does not say
    /// whether it is today's, this month's or this year's, and the range is
    /// otherwise only visible with the configure pane open. The middle dot
    /// is the separator used everywhere else a qualifier follows a name,
    /// such as "Connected · Acme Inc".
    ///
    /// Whether the window means anything is the caller's to say — it comes
    /// from the metric's descriptor, which this package does not hold. A
    /// snapshot such as MRR or stargazers has no window and gets no suffix;
    /// a metric with a window fixed by its provider says so in its own label.
    public func displayTitle(showingRange: Bool) -> String {
        showingRange ? "\(baseTitle) · \(range.rawValue)" : baseTitle
    }

    /// Identifies the metric this widget reads, for looking up its descriptor.
    ///
    /// Provider metrics are keyed by app and metric id; custom metrics by
    /// plugin id. Nil for a widget that reads nothing, such as a divider.
    public var metricKey: String? {
        switch kind {
        case .customMetric:
            return customMetricId.map { "custom/\($0)" }
        default:
            return metric.map { "\(appId)/\($0)" }
        }
    }
}

public struct NotchLayout: Codable, Sendable, Hashable {
    public static let columns = 6

    /// How tall the notch opens, in grid rows.
    ///
    /// An instance property rather than a constant: the handle on the bottom
    /// edge drags to add and remove rows, which is how a user makes room for
    /// more widgets. Bounded because a notch taller than this stops being a
    /// glanceable overlay and becomes a window.
    public static let defaultRows = 2
    public static let minRows = 1
    public static let maxRows = 4

    /// How far the flow may run, independent of how much of it is on screen.
    ///
    /// `rows` is the *viewport* — how tall the notch opens. The widgets
    /// themselves lay out into this much taller space and the viewport
    /// scrolls over it. Conflating the two is what made adding a widget to a
    /// full grid fail: there was nowhere to put it, so it was marked hidden
    /// and silently vanished instead of pushing the content down.
    public static let maxContentRows = 24

    /// Bumped whenever the on-disk shape changes, read by `migrate(_:)`.
    public var schemaVersion: Int
    /// The server's copy of this layout. The Mac is authoritative; this is the
    /// token that stops a second Mac silently clobbering the backup.
    public var revision: Int
    public var rows: Int
    public var widgets: [NotchWidget]

    public init(
        schemaVersion: Int = 1, revision: Int = 0,
        rows: Int = NotchLayout.defaultRows,
        widgets: [NotchWidget] = []
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.rows = rows.clamped(to: NotchLayout.minRows...NotchLayout.maxRows)
        self.widgets = widgets
    }

    /// How many rows the widgets actually occupy, which may exceed `rows`.
    ///
    /// Drives the scrollable height; `rows` drives the window.
    public var contentRows: Int {
        widgets.filter(\.visible).map { $0.row + $0.size.rows }.max() ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, revision, rows, widgets
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        // Defaulted, so a layout.json written before the handle existed still
        // decodes rather than stranding the user with an empty notch.
        rows = (try c.decodeIfPresent(Int.self, forKey: .rows) ?? NotchLayout.defaultRows)
            .clamped(to: NotchLayout.minRows...NotchLayout.maxRows)
        widgets = try c.decodeIfPresent([NotchWidget].self, forKey: .widgets) ?? []
    }


}

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Places, displaces and validates widgets on the grid.
///
/// Pure and value-typed on purpose: every drag runs it against a *copy* of the
/// layout to produce the live displacement preview, and committing is then
/// just keeping the copy.
public enum GridPacker {
    /// The cells a widget occupies, or nil if it would hang off the grid.
    public static func cells(
        for widget: NotchWidget,
        at origin: (col: Int, row: Int),
        rows: Int = NotchLayout.defaultRows
    ) -> [GridCell]? {
        guard origin.col >= 0, origin.row >= 0,
              origin.col + widget.size.cols <= NotchLayout.columns,
              origin.row + widget.size.rows <= rows
        else { return nil }

        return (0..<widget.size.cols).flatMap { dc in
            (0..<widget.size.rows).map { dr in
                GridCell(col: origin.col + dc, row: origin.row + dr)
            }
        }
    }

    public static func occupied(_ layout: NotchLayout, excluding id: String? = nil) -> Set<GridCell> {
        var taken: Set<GridCell> = []
        for widget in layout.widgets where widget.visible && widget.id != id {
            taken.formUnion(
                cells(for: widget, at: (widget.col, widget.row), rows: NotchLayout.maxContentRows)
                    ?? [])
        }
        return taken
    }

    public static func fits(_ widget: NotchWidget, at origin: (col: Int, row: Int), in layout: NotchLayout) -> Bool {
        guard let wanted = cells(for: widget, at: origin, rows: NotchLayout.maxContentRows)
        else { return false }
        return occupied(layout, excluding: widget.id).isDisjoint(with: Set(wanted))
    }

    /// Moves `id` to `origin`, displacing whatever is in the way.
    ///
    /// Displaced widgets are re-placed by a first-fit scan against a layout
    /// that already contains the moved widget — so a displaced tile cannot be
    /// put back on top of the thing that displaced it. Returns nil when
    /// something genuinely has nowhere to go, so the caller snaps the drag back
    /// rather than committing a layout with a widget silently dropped.
    public static func place(
        _ id: String,
        at origin: (col: Int, row: Int),
        in layout: NotchLayout
    ) -> NotchLayout? {
        guard let moving = layout.widgets.first(where: { $0.id == id }),
              let wanted = cells(for: moving, at: origin, rows: layout.rows)
        else { return nil }

        var placed = moving
        placed.col = origin.col
        placed.row = origin.row

        let wantedSet = Set(wanted)
        var settled: [NotchWidget] = [placed]
        var displaced: [NotchWidget] = []

        for widget in layout.widgets where widget.id != id {
            guard widget.visible else {
                settled.append(widget)
                continue
            }
            let occupying = Set(cells(for: widget, at: (widget.col, widget.row), rows: layout.rows) ?? [])
            if occupying.isDisjoint(with: wantedSet) {
                settled.append(widget)
            } else {
                displaced.append(widget)
            }
        }

        // Re-placed one at a time against the accumulating layout, so two
        // displaced widgets cannot both be assigned the same free slot.
        for var widget in displaced {
            let accumulated = NotchLayout(
                schemaVersion: layout.schemaVersion, revision: layout.revision,
                rows: layout.rows, widgets: settled)
            guard let slot = firstFit(for: widget, in: accumulated) else { return nil }
            widget.col = slot.col
            widget.row = slot.row
            settled.append(widget)
        }

        return normalised(
            NotchLayout(
                schemaVersion: layout.schemaVersion, revision: layout.revision,
                rows: layout.rows, widgets: settled))
    }

    /// Lays every widget out in order, left to right and top to bottom.
    ///
    /// The grid is a flow, not a pinboard. Widgets hold an *order*; where they
    /// sit is derived from it. That is what stops a tile being stranded in the
    /// middle of an empty row after the one beside it shrinks, and it is why a
    /// resize can make room — everything after the resized widget simply flows
    /// around its new shape.
    ///
    /// Anything that will not fit at all is marked not visible rather than
    /// dropped, so it survives a trip through a smaller grid and comes back
    /// when there is room.
    public static func reflow(_ layout: NotchLayout) -> NotchLayout {
        var settled: [NotchWidget] = []

        for var widget in layout.widgets.sorted(by: { $0.position < $1.position }) {
            let scratch = NotchLayout(
                schemaVersion: layout.schemaVersion, revision: layout.revision,
                rows: layout.rows, widgets: settled)

            if let slot = firstFit(for: widget, in: scratch) {
                widget.col = slot.col
                widget.row = slot.row
                widget.visible = true
            } else {
                widget.visible = false
            }
            settled.append(widget)
        }

        var next = layout
        next.widgets = settled
        return normalised(next)
    }

    /// Moves `id` so that it lands at `index` in reading order, then reflows.
    ///
    /// Dragging reorders rather than assigning coordinates. Dropping a tile
    /// "between" two others is a position in a sequence, and treating it as a
    /// pair of coordinates is what let widgets end up with gaps around them.
    public static func move(_ id: String, toIndex index: Int, in layout: NotchLayout) -> NotchLayout {
        var ordered = layout.widgets.sorted { $0.position < $1.position }
        guard let from = ordered.firstIndex(where: { $0.id == id }) else { return layout }

        let widget = ordered.remove(at: from)
        ordered.insert(widget, at: min(max(0, index), ordered.count))
        for (position, _) in ordered.enumerated() { ordered[position].position = position }

        var next = layout
        next.widgets = ordered
        return reflow(next)
    }

    /// The reading-order index a drop at `origin` corresponds to.
    ///
    /// Counts the widgets whose own cell comes before that point, so dropping
    /// into the gap after a tile puts the dragged one directly after it.
    public static func index(at origin: (col: Int, row: Int), in layout: NotchLayout, excluding id: String) -> Int {
        let target = origin.row * NotchLayout.columns + origin.col
        return layout.widgets
            .filter { $0.id != id && $0.visible }
            .filter { $0.row * NotchLayout.columns + $0.col < target }
            .count
    }

    public static func firstFit(
        for widget: NotchWidget,
        in layout: NotchLayout
    ) -> (col: Int, row: Int)? {
        var scratch = layout
        scratch.widgets.removeAll { $0.id == widget.id }
        // Scanned row-major so a displaced widget slides along the row it was
        // already in before dropping to the next one, which is what the eye
        // expects when something is pushed aside.
        // Scanned over the flow space rather than the visible rows: a widget
        // that does not fit on screen belongs below the fold, not in the
        // hidden pile.
        for row in 0..<NotchLayout.maxContentRows {
            for col in 0..<NotchLayout.columns where fits(widget, at: (col, row), in: scratch) {
                return (col, row)
            }
        }
        return nil
    }

    /// Can this widget become `size` where it stands?
    public static func canResize(_ id: String, to size: WidgetSize, in layout: NotchLayout) -> Bool {
        guard let widget = layout.widgets.first(where: { $0.id == id }) else { return false }
        var resized = widget
        resized.size = size
        return fits(resized, at: (widget.col, widget.row), in: layout)
    }

    /// Appends a widget wherever it will go, or returns nil when the grid is full.
    public static func append(_ widget: NotchWidget, to layout: NotchLayout) -> NotchLayout? {
        guard let slot = firstFit(for: widget, in: layout) else { return nil }
        var next = layout
        var placed = widget
        placed.col = slot.col
        placed.row = slot.row
        next.widgets.append(placed)
        return normalised(next)
    }

    /// Resolves a layout that may not be valid into one that is.
    ///
    /// Positions arrive from three places that cannot all be trusted to agree:
    /// a `layout.json` written by an older build with a different grid, a
    /// `PUT /v1/widgets` from another Mac, and the packer. Rendering them
    /// as-is draws overlapping tiles on top of each other, which looks like a
    /// rendering fault rather than a layout one.
    ///
    /// Anything that still cannot be placed is marked not visible rather than
    /// dropped — the widget survives a trip through a smaller grid and comes
    /// back when there is room.
    public static func repack(_ layout: NotchLayout) -> NotchLayout {
        var next = layout
        var settled: [NotchWidget] = []

        for var widget in layout.widgets.sorted(by: { $0.position < $1.position }) {
            guard widget.visible else {
                settled.append(widget)
                continue
            }

            let scratch = NotchLayout(
                schemaVersion: layout.schemaVersion, revision: layout.revision,
                rows: layout.rows, widgets: settled)

            if fits(widget, at: (widget.col, widget.row), in: scratch) {
                settled.append(widget)
            } else if let slot = firstFit(for: widget, in: scratch) {
                widget.col = slot.col
                widget.row = slot.row
                settled.append(widget)
            } else {
                widget.visible = false
                settled.append(widget)
            }
        }

        next.widgets = settled
        return normalised(next)
    }

    /// Re-derives `position` from the grid so the order the server stores is
    /// the order the eye reads: left to right, top to bottom.
    public static func normalised(_ layout: NotchLayout) -> NotchLayout {
        var next = layout
        let order = next.widgets
            .sorted { ($0.row, $0.col) < ($1.row, $1.col) }
            .map(\.id)
        for (position, id) in order.enumerated() {
            if let index = next.widgets.firstIndex(where: { $0.id == id }) {
                next.widgets[index].position = position
            }
        }
        next.widgets.sort { $0.position < $1.position }
        return next
    }
}

public struct GridCell: Hashable, Sendable {
    public let col: Int
    public let row: Int

    public init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }
}
