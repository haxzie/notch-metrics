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
public enum WidgetSize: String, Codable, Sendable, CaseIterable, Hashable {
    /// A sixth of the width. A number, no chart.
    case small = "1x1"
    /// A third of the width — three across, which is the default arrangement.
    case wide = "2x1"
    /// A third of the width, full height. Logo, label, headline figure.
    case square = "2x2"
    /// The full width of the grid, both rows. One large chart.
    case hero = "6x2"

    public var cols: Int {
        switch self {
        case .small: 1
        case .wide, .square: 2
        case .hero: 6
        }
    }

    public var rows: Int {
        switch self {
        case .small, .wide: 1
        case .square, .hero: 2
        }
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
public enum DisplayMode: String, Codable, Sendable, Hashable, CaseIterable {
    case grid, list

    /// Unknown values fall back to the grid.
    ///
    /// Same rule as every other wire enum here: a server that starts sending a
    /// mode this build predates must not make the whole layout fail to decode
    /// and blank the notch.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DisplayMode(rawValue: raw) ?? .grid
    }

    public var label: String {
        switch self {
        case .grid: "Grid"
        case .list: "List"
        }
    }

    public var symbol: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }

    public var toggled: DisplayMode { self == .grid ? .list : .grid }
}

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
    public var size: WidgetSize
    public var col: Int
    public var row: Int
    public var position: Int
    public var granularity: Granularity
    public var range: TimeRange
    public var chart: ChartKind
    /// How the number reads. Nil means "whatever the series says".
    public var format: WidgetFormat?
    public var visible: Bool

    public init(
        id: String = UUID().uuidString, kind: WidgetKind = .providerMetric,
        appId: String = AppCatalog.unknownId,
        integrationId: String? = nil, metric: String? = nil, customMetricId: String? = nil,
        title: String? = nil, size: WidgetSize = .wide, col: Int = 0, row: Int = 0,
        position: Int = 0, granularity: Granularity = .day, range: TimeRange = .month,
        chart: ChartKind = .sparkline, format: WidgetFormat? = nil,
        visible: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.appId = appId
        self.integrationId = integrationId
        self.metric = metric
        self.customMetricId = customMetricId
        self.title = title
        self.size = size
        self.col = col
        self.row = row
        self.position = position
        self.granularity = granularity
        self.range = range
        self.chart = chart
        self.format = format
        self.visible = visible
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, appId, integrationId, metric, customMetricId, title, size
        case col, row, position, granularity, range, chart, format, visible
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(WidgetKind.self, forKey: .kind)
        integrationId = try c.decodeIfPresent(String.self, forKey: .integrationId)
        metric = try c.decodeIfPresent(String.self, forKey: .metric)
        customMetricId = try c.decodeIfPresent(String.self, forKey: .customMetricId)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        size = try c.decodeIfPresent(WidgetSize.self, forKey: .size) ?? .wide
        col = try c.decodeIfPresent(Int.self, forKey: .col) ?? 0
        row = try c.decodeIfPresent(Int.self, forKey: .row) ?? 0
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        granularity = try c.decodeIfPresent(Granularity.self, forKey: .granularity) ?? .day
        range = try c.decodeIfPresent(TimeRange.self, forKey: .range) ?? .month
        chart = try c.decodeIfPresent(ChartKind.self, forKey: .chart) ?? .sparkline
        // Absent in every layout.json written before formats existed, and nil
        // means "use the series", so those widgets render exactly as they did.
        format = try c.decodeIfPresent(WidgetFormat.self, forKey: .format)
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

    /// Bumped whenever the on-disk shape changes, read by `migrate(_:)`.
    public var schemaVersion: Int
    /// The server's copy of this layout. The Mac is authoritative; this is the
    /// token that stops a second Mac silently clobbering the backup.
    public var revision: Int
    public var rows: Int
    public var display: DisplayMode
    public var widgets: [NotchWidget]

    public init(
        schemaVersion: Int = 1, revision: Int = 0,
        rows: Int = NotchLayout.defaultRows, display: DisplayMode = .grid,
        widgets: [NotchWidget] = []
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.rows = rows.clamped(to: NotchLayout.minRows...NotchLayout.maxRows)
        self.display = display
        self.widgets = widgets
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, revision, rows, display, widgets
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        // Defaulted, so a layout.json written before the handle existed still
        // decodes rather than stranding the user with an empty notch.
        rows = (try c.decodeIfPresent(Int.self, forKey: .rows) ?? NotchLayout.defaultRows)
            .clamped(to: NotchLayout.minRows...NotchLayout.maxRows)
        display = try c.decodeIfPresent(DisplayMode.self, forKey: .display) ?? .grid
        widgets = try c.decodeIfPresent([NotchWidget].self, forKey: .widgets) ?? []
    }

    /// The visible widgets, grouped by app, in the order the list draws them.
    ///
    /// Apps keep the order of their first widget rather than being sorted
    /// alphabetically: the user arranged these, and re-sorting under them on
    /// every render is the sort of tidiness nobody asked for.
    public func groupedByApp(overrides: [String: MetricApp] = [:]) -> [(app: MetricApp, widgets: [NotchWidget])] {
        var order: [String] = []
        var byApp: [String: [NotchWidget]] = [:]

        for widget in widgets.sorted(by: { $0.position < $1.position }) where widget.visible {
            let app = widget.app(overrides: overrides)
            if byApp[app.id] == nil { order.append(app.id) }
            byApp[app.id, default: []].append(widget)
        }

        return order.map { id in
            (AppCatalog.resolve(id, overrides: overrides), byApp[id] ?? [])
        }
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
            taken.formUnion(cells(for: widget, at: (widget.col, widget.row), rows: layout.rows) ?? [])
        }
        return taken
    }

    public static func fits(_ widget: NotchWidget, at origin: (col: Int, row: Int), in layout: NotchLayout) -> Bool {
        guard let wanted = cells(for: widget, at: origin, rows: layout.rows) else { return false }
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

    public static func firstFit(
        for widget: NotchWidget,
        in layout: NotchLayout
    ) -> (col: Int, row: Int)? {
        var scratch = layout
        scratch.widgets.removeAll { $0.id == widget.id }
        // Scanned row-major so a displaced widget slides along the row it was
        // already in before dropping to the next one, which is what the eye
        // expects when something is pushed aside.
        for row in 0..<layout.rows {
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
                rows: layout.rows, display: layout.display, widgets: settled)

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
