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

public struct NotchWidget: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var kind: WidgetKind
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
    public var visible: Bool

    public init(
        id: String = UUID().uuidString, kind: WidgetKind = .providerMetric,
        integrationId: String? = nil, metric: String? = nil, customMetricId: String? = nil,
        title: String? = nil, size: WidgetSize = .wide, col: Int = 0, row: Int = 0,
        position: Int = 0, granularity: Granularity = .day, range: TimeRange = .month,
        chart: ChartKind = .sparkline, visible: Bool = true
    ) {
        self.id = id
        self.kind = kind
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
        self.visible = visible
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
    public var widgets: [NotchWidget]

    public init(
        schemaVersion: Int = 1, revision: Int = 0,
        rows: Int = NotchLayout.defaultRows, widgets: [NotchWidget] = []
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.rows = rows.clamped(to: NotchLayout.minRows...NotchLayout.maxRows)
        self.widgets = widgets
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
