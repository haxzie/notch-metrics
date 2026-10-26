import SwiftUI

/// Drops a long series to at most `limit` points while keeping its shape.
///
/// Largest-Triangle-Three-Buckets: it picks, from each bucket, the point that
/// forms the largest triangle with its neighbours, which preserves peaks and
/// troughs. Naive every-nth sampling routinely lands between two spikes and
/// draws a flat line through a month that had two outages in it.
public enum SeriesDownsampler {
    public static func lttb(_ points: [CGPoint], to limit: Int) -> [CGPoint] {
        guard limit > 2, points.count > limit else { return points }

        var sampled: [CGPoint] = [points[0]]
        let bucketSize = Double(points.count - 2) / Double(limit - 2)

        for i in 0..<(limit - 2) {
            let rangeStart = Int(Double(i) * bucketSize) + 1
            let rangeEnd = min(Int(Double(i + 1) * bucketSize) + 1, points.count - 1)
            let nextStart = rangeEnd
            let nextEnd = min(Int(Double(i + 2) * bucketSize) + 1, points.count)

            let nextSlice = points[nextStart..<max(nextStart, nextEnd)]
            let avgX = nextSlice.isEmpty ? 0 : nextSlice.map(\.x).reduce(0, +) / Double(nextSlice.count)
            let avgY = nextSlice.isEmpty ? 0 : nextSlice.map(\.y).reduce(0, +) / Double(nextSlice.count)

            let previous = sampled[sampled.count - 1]
            var best = points[rangeStart]
            var bestArea = -1.0

            for point in points[rangeStart..<max(rangeStart, rangeEnd)] {
                // Split, and annotated, because the one-expression form took
                // Swift 6.2 past its type-checking budget — six CGFloat
                // operands and a literal divisor is enough for the solver to
                // give up. It compiles on 6.3, which is why it only ever
                // failed on CI.
                let left: CGFloat = (previous.x - avgX) * (point.y - previous.y)
                let right: CGFloat = (previous.x - point.x) * (avgY - previous.y)
                let area = abs(left - right) / 2
                if area > bestArea {
                    bestArea = area
                    best = point
                }
            }
            sampled.append(best)
        }

        sampled.append(points[points.count - 1])
        return sampled
    }
}

enum SeriesPath {
    /// Normalises values into the drawing rect. A flat series is centred rather
    /// than pinned to the floor, because a line along the bottom edge reads as
    /// "no data" when it actually means "steady".
    static func normalise(_ values: [Double], in rect: CGRect) -> [CGPoint] {
        guard values.count > 1 else {
            return values.map { _ in CGPoint(x: rect.midX, y: rect.midY) }
        }
        let lowest = values.min() ?? 0
        let highest = values.max() ?? 1
        let span = highest - lowest

        return values.enumerated().map { index, value in
            let x = rect.minX + rect.width * Double(index) / Double(values.count - 1)
            let y = span == 0
                ? rect.midY
                : rect.maxY - rect.height * ((value - lowest) / span)
            return CGPoint(x: x, y: y)
        }
    }

    /// Catmull-Rom, converted to cubic Béziers. Straight segments between
    /// daily points look like a seismograph at tile size.
    ///
    /// The vertical control points are clamped to the segment they belong
    /// to. Unclamped, Catmull-Rom overshoots either side of a sharp turn —
    /// by over 4pt on a 40pt chart for a series that dips and recovers —
    /// and the curve is then drawn outside the rect the data was normalised
    /// into. Visibly that is a peak with its top shaved flat against the
    /// edge of the tile; it also means the chart draws a value higher than
    /// any the metric ever reported. A cubic Bézier is contained by the
    /// convex hull of its control points, so clamping those to the
    /// segment's own y-range is what guarantees the path stays inside.
    ///
    /// Only y. The x controls are what give the curve its horizontal ease,
    /// they are monotonic by construction, and the drawing rect is inset
    /// horizontally anyway.
    static func smoothed(_ points: [CGPoint], tension: CGFloat = 0.2) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            for point in points.dropFirst() { path.addLine(to: point) }
            return path
        }

        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]

            let lowest = min(p1.y, p2.y)
            let highest = max(p1.y, p2.y)
            let clamp = { (y: CGFloat) in min(max(y, lowest), highest) }

            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) * tension, y: clamp(p1.y + (p2.y - p0.y) * tension))
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) * tension, y: clamp(p2.y - (p3.y - p1.y) * tension))
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }
}

/// A line chart for a tile that is sometimes 56×24 points.
///
/// `Canvas`, not Swift Charts. Swift Charts reserves space for axes and a
/// legend that have to be fought off one modifier at a time, and it builds a
/// full plot model per render — which is real cost with eight tiles
/// re-rendering inside a spring animation. Swift Charts is the right tool in
/// the Settings window's history view, where the axes are wanted.
public struct Sparkline: View {
    public let values: [Double]
    public var tint: Color
    public var fill: Bool
    /// Opacity at the top of the area gradient; it always falls to zero.
    public var fillOpacity: Double

    public init(
        values: [Double], tint: Color = .accentColor, fill: Bool = true,
        fillOpacity: Double = 0.45
    ) {
        self.values = values
        self.tint = tint
        self.fill = fill
        self.fillOpacity = fillOpacity
    }

    /// The line, and the marker on its last point.
    ///
    /// Named because the drawing rect is derived from them. They are what
    /// sticks out past the path, and the inset that ignored them is what cut
    /// the chart off.
    static let lineWidth: CGFloat = 1.5
    static let dotRadius: CGFloat = 2

    /// Where the series is actually plotted inside the canvas.
    ///
    /// Inset by what is drawn *around* the path, not by a flat couple of
    /// points. The stroke is centred on the line, so half of it sits above
    /// the highest sample; the end dot is a circle centred on the last one,
    /// so it needs its whole radius to the right and — when the most recent
    /// value is also the maximum, which is what a metric having a good week
    /// looks like — above.
    ///
    /// At the old `dx: 1, dy: 2` the dot was clipped by the right edge of
    /// every chart in the notch, and a series peaking on its last point had
    /// the top of that dot sliced off as well.
    ///
    /// Separate from `body` so the containment can be asserted directly
    /// rather than inferred from pixels.
    static func drawingRect(in size: CGSize) -> CGRect {
        CGRect(origin: .zero, size: size)
            .insetBy(dx: dotRadius, dy: dotRadius + lineWidth / 2)
    }

    public var body: some View {
        Canvas { context, size in
            let rect = Self.drawingRect(in: size)
            guard values.count > 1, rect.width > 0, rect.height > 0 else { return }

            let maxPoints = max(2, Int(rect.width / 2))
            let raw = SeriesPath.normalise(values, in: rect)
            let points = SeriesDownsampler.lttb(raw, to: min(maxPoints, raw.count))
            let line = SeriesPath.smoothed(points)

            if fill {
                var area = line
                area.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.maxY))
                area.addLine(to: CGPoint(x: points[0].x, y: rect.maxY))
                area.closeSubpath()
                // Three stops, not two. A straight ramp from 0.45 to 0 is
                // linear in alpha but reads as a hard band against a dark
                // tile, because perceived brightness is not; the middle stop
                // pulls the falloff earlier so the bottom genuinely vanishes.
                //
                // Anchored to the drawing rect rather than the path's own
                // bounds, so a flat series fades over the same distance as a
                // spiky one instead of being a solid block.
                context.fill(
                    area,
                    with: .linearGradient(
                        Gradient(stops: [
                            .init(color: tint.opacity(fillOpacity), location: 0),
                            .init(color: tint.opacity(fillOpacity * 0.36), location: 0.45),
                            .init(color: tint.opacity(0.0), location: 1),
                        ]),
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            }

            context.stroke(
                line, with: .color(tint),
                style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round))

            if let last = points.last {
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: last.x - Self.dotRadius, y: last.y - Self.dotRadius,
                        width: Self.dotRadius * 2, height: Self.dotRadius * 2)),
                    with: .color(tint))
            }
        }
        .drawingGroup(opaque: false)
    }
}

/// A bar chart for the same tile sizes.
public struct MiniBars: View {
    public let values: [Double]
    public var tint: Color

    public init(values: [Double], tint: Color = .accentColor) {
        self.values = values
        self.tint = tint
    }

    public var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 2)
            guard !values.isEmpty, rect.width > 0 else { return }

            // Below two points per bar the gaps vanish and it reads as a solid
            // block, so the series is collapsed rather than drawn illegibly.
            let maxBars = max(1, Int(rect.width / 3))
            let shown = values.count > maxBars ? collapse(values, to: maxBars) : values

            let highest = shown.max() ?? 1
            let slot = rect.width / CGFloat(shown.count)
            let barWidth = max(1, slot * 0.7)

            for (index, value) in shown.enumerated() {
                let height = highest == 0 ? 1 : max(1, rect.height * (value / highest))
                let bar = CGRect(
                    x: rect.minX + CGFloat(index) * slot + (slot - barWidth) / 2,
                    y: rect.maxY - height, width: barWidth, height: height)
                // Solid. The gradient matched the sparkline's area fill, but
                // a bar is a discrete quantity rather than a region under a
                // line — fading it towards the baseline made short bars read
                // as faint ones, which is a second meaning the chart does not
                // have.
                context.fill(
                    Path(roundedRect: bar, cornerRadius: min(1.5, barWidth / 2)),
                    with: .color(tint.opacity(0.9)))
            }
        }
        .drawingGroup(opaque: false)
    }

    private func collapse(_ values: [Double], to count: Int) -> [Double] {
        let bucket = Double(values.count) / Double(count)
        return (0..<count).map { index in
            let start = Int(Double(index) * bucket)
            let end = min(values.count, Int(Double(index + 1) * bucket))
            let slice = values[start..<max(start + 1, end)]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }
}

/// An arc filled to a fraction, with the figure inside it.
///
/// For a value that has a ceiling — a percentage of a limit, a share, a score
/// out of a known maximum. The arc says at a glance what a number cannot:
/// whether 18% is nearly nothing or nearly everything depends on the bound,
/// and the bound is the thing a bare figure leaves out.
///
/// A semicircle rather than a full ring. A ring's two ends meet, so "empty"
/// and "full" look alike at a glance; an arc has a start and an end the eye
/// can find, and it leaves the middle free for the figure at tile sizes where
/// a ring would not.
///
/// `Canvas` for the same reason `Sparkline` uses it: this draws inside tiles
/// that re-render together inside a spring animation, and a Shape per tile
/// costs layout the canvas does not.
public struct GaugeArc<Label: View>: View {
    /// The filled share, 0...1. Values outside are clamped rather than
    /// refused: a limit can legitimately be exceeded, and an arc that wrapped
    /// past its own start would read as a smaller number than the truth.
    public let fraction: Double
    public let tint: Color
    public var lineWidth: CGFloat
    private let label: Label

    public init(
        fraction: Double, tint: Color, lineWidth: CGFloat = 8,
        @ViewBuilder label: () -> Label
    ) {
        self.fraction = fraction
        self.tint = tint
        self.lineWidth = lineWidth
        self.label = label()
    }

    /// The share actually drawn, clamped to the arc.
    ///
    /// Internal rather than private so the clamp can be asserted: a limit can
    /// legitimately be exceeded, and this is the line that stops 105% drawing
    /// as a sliver.
    var displayFraction: Double { min(max(fraction, 0), 1) }

    /// Where the arc sits, shared by the canvas and the label.
    ///
    /// Computed from one function so the two cannot disagree — they were two
    /// separate expressions, and the label's idea of the centre drifted from
    /// the arc's on any tile that was not square.
    static func geometry(in size: CGSize, lineWidth: CGFloat) -> (centre: CGPoint, radius: CGFloat) {
        let inset = lineWidth / 2
        // Bounded by half the width *and* the full height: a semicircle is
        // twice as wide as it is tall, so a short tile is limited by height
        // and a narrow one by width.
        let radius = max(0, min((size.width - lineWidth) / 2, size.height - lineWidth))
        return (CGPoint(x: size.width / 2, y: size.height - inset), radius)
    }

    public var body: some View {
        Canvas { context, size in
            let geometry = Self.geometry(in: size, lineWidth: lineWidth)
            guard geometry.radius > 0 else { return }

            func arc(to end: Double) -> Path {
                var path = Path()
                path.addArc(
                    center: geometry.centre, radius: geometry.radius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(180 + 180 * end),
                    clockwise: false)
                return path
            }

            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            // The track is drawn whole and the fill over it, so a value of
            // zero still shows the shape it would fill.
            context.stroke(arc(to: 1), with: .color(.white.opacity(0.14)), style: stroke)
            if displayFraction > 0 {
                context.stroke(arc(to: displayFraction), with: .color(tint), style: stroke)
            }
        }
        .overlay {
            GeometryReader { proxy in
                let geometry = Self.geometry(in: proxy.size, lineWidth: lineWidth)
                label
                    // Sized off the *arc*, not the frame. A 2x1 tile is far
                    // wider than it is tall, so a label measured against the
                    // frame width overflowed the semicircle it is supposed to
                    // sit inside — the figure ran out past both ends of the
                    // arc and collided with the stroke.
                    .frame(width: geometry.radius * 1.5)
                    .position(
                        x: geometry.centre.x,
                        // Above the baseline by a third of the radius: the
                        // optical centre of a semicircle is not its chord.
                        y: geometry.centre.y - geometry.radius * 0.34)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Colours for the slices of a distribution.
///
/// Fixed hues rather than shades of the app's accent. A distribution's whole
/// job is telling categories apart, and five tints of one colour on a 90pt
/// tile are five greys — the separation has to come from hue, not lightness.
///
/// Ordered so the first few are furthest apart: most distributions here have
/// two or three categories that matter and a tail of near-zero ones, and the
/// pairs that must never be confused are the ones drawn first.
public enum SliceColours {
    public static let all: [Color] = [
        Color(hex: "5E9EFF") ?? .blue,  // blue
        Color(hex: "F2B34B") ?? .orange,  // amber
        Color(hex: "4FD1A5") ?? .green,  // teal
        Color(hex: "E86A8C") ?? .pink,  // rose
        Color(hex: "A98BFF") ?? .purple,  // violet
        Color(hex: "8C96A8") ?? .gray,  // slate, for the tail
    ]

    /// The colour for one position, wrapping rather than running out.
    ///
    /// A list can be longer than the palette. Repeating is honest — two
    /// categories sharing a colour is survivable where a transparent slice or
    /// a crash is not — and the labels disambiguate in every layout that has
    /// room for them.
    public static func at(_ index: Int) -> Color {
        all[((index % all.count) + all.count) % all.count]
    }
}

/// One bar divided into coloured segments.
///
/// The distribution that fits a row: it needs one line, where a pie needs a
/// square and ranked bars need one line *each*.
public struct SplitBar: View {
    public let shares: [Double]
    public var height: CGFloat

    public init(shares: [Double], height: CGFloat = 10) {
        self.shares = shares
        self.height = height
    }

    /// Normalised, so the bar always fills its width.
    ///
    /// The caller's values may be percentages, token counts or anything else;
    /// what a split bar shows is proportion, and a bar that stopped short
    /// would read as "the rest is missing" rather than "this is the whole".
    var normalised: [Double] {
        let total = shares.reduce(0) { $0 + max(0, $1) }
        guard total > 0 else { return [] }
        return shares.map { max(0, $0) / total }
    }

    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1.5) {
                ForEach(Array(normalised.enumerated()), id: \.offset) { index, share in
                    SliceColours.at(index)
                        .frame(width: max(0, proxy.size.width * share - 1.5))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}

/// The key to a split bar: a dot in each slice's colour, and its name.
///
/// A split bar is the one distribution that says nothing about *what* its
/// slices are — the ranked bars and the ring both carry their labels, and the
/// bar on its own is four coloured segments and no way to tell which is which.
///
/// Rows are dropped from the tail rather than squeezed, for the same reason
/// `RankedBars` truncates: a 2x2 has room for two or three lines, and six
/// crushed into that height is six unreadable ones. The tail of a
/// distribution is usually the part nobody needs, and it is still in the bar.
public struct SliceLegend: View {
    public struct Row: Identifiable {
        public let id: String
        public let label: String
        public let detail: String?
        /// Which slice this names. Carried rather than derived from position,
        /// because the visible rows are a prefix and a dot that drifted out of
        /// step with the bar would be worse than no legend at all.
        public let colourIndex: Int

        public init(id: String, label: String, detail: String?, colourIndex: Int) {
            self.id = id
            self.label = label
            self.detail = detail
            self.colourIndex = colourIndex
        }
    }

    public let rows: [Row]
    public var fontSize: CGFloat
    /// How many lines the tile has room for. Zero is honest: a one-row tile
    /// has none, and the bar stands alone there as it always did.
    public var maxRows: Int

    public init(rows: [Row], fontSize: CGFloat = 10, maxRows: Int = 3) {
        self.rows = rows
        self.fontSize = fontSize
        self.maxRows = maxRows
    }

    var visibleRows: [Row] { maxRows <= 0 ? [] : Array(rows.prefix(maxRows)) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(visibleRows) { row in
                HStack(spacing: 5) {
                    Circle()
                        .fill(SliceColours.at(row.colourIndex))
                        .frame(width: fontSize * 0.6, height: fontSize * 0.6)
                    Text(row.label)
                        .lineLimit(1)
                        .foregroundStyle(NotchTheme.secondaryText)
                    Spacer(minLength: 2)
                    if let detail = row.detail {
                        Text(detail)
                            .foregroundStyle(NotchTheme.primaryText)
                            .monospacedDigit()
                    }
                }
                .font(.system(size: fontSize))
            }
        }
    }
}

/// One labelled bar per category, largest first.
public struct RankedBars: View {
    public struct Row: Identifiable {
        public let id: String
        public let label: String
        public let detail: String?
        public let share: Double

        public init(id: String, label: String, detail: String?, share: Double) {
            self.id = id
            self.label = label
            self.detail = detail
            self.share = share
        }
    }

    public let rows: [Row]
    public var fontSize: CGFloat
    /// How many rows the tile has room for.
    ///
    /// Unbounded, five categories laid out at natural height overflowed a 2x2
    /// and pushed the tile's own frame taller than its neighbours — and made
    /// the gallery's preview card spill past its padding. The text list has
    /// always budgeted rows against the tile height; so does this.
    public var maxRows: Int

    public init(rows: [Row], fontSize: CGFloat = 10, maxRows: Int = 4) {
        self.rows = rows
        self.fontSize = fontSize
        self.maxRows = maxRows
    }

    /// The rows that fit, largest first.
    ///
    /// Truncated rather than scaled: five bars squeezed into the height of
    /// three are three unreadable bars and two slivers. The tail of a
    /// distribution is usually the part nobody needs.
    var visibleRows: [Row] { Array(rows.prefix(max(1, maxRows))) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 2) {
                    // The name above its bar, so a long one has the full width
                    // rather than squeezing the bar into nothing.
                    HStack(spacing: 4) {
                        Text(row.label)
                            .lineLimit(1)
                            .foregroundStyle(NotchTheme.secondaryText)
                        Spacer(minLength: 2)
                        if let detail = row.detail {
                            Text(detail)
                                .foregroundStyle(NotchTheme.primaryText)
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: fontSize))

                    GeometryReader { proxy in
                        Capsule()
                            .fill(SliceColours.at(index))
                            // A floor, so a category that rounds to zero is
                            // still visibly present rather than absent.
                            .frame(width: max(2, proxy.size.width * row.share))
                    }
                    .frame(height: 4)
                }
            }
        }
    }
}

/// The whole as a ring.
///
/// A ring rather than a filled pie, for two reasons. Slices meeting at a point
/// are hardest to compare exactly where they are thinnest, and the hole is
/// somewhere to put the total — so the tile says both "how much" and "made up
/// of what" in one shape, instead of stacking a figure above a circle and
/// spending half the tile on the stacking.
///
/// The name stays `PieChart` because `ChartKind.pie` is on the wire and a
/// rename there is a contract change for a cosmetic gain.
public struct PieChart<Label: View>: View {
    public let shares: [Double]
    /// The ring's thickness as a fraction of its radius.
    ///
    /// Thin on purpose, and not only for looks. The stroke sets the cap, the
    /// cap sets the floor a slice cannot be drawn below, and at a third of the
    /// radius that floor was over twenty degrees — so the small slices came
    /// out as fat dots crowding the top of the circle. Halving the stroke
    /// roughly halves the floor, and gives the figure in the middle more room
    /// at the same time.
    public let thickness: CGFloat
    private let label: Label

    public init(shares: [Double], thickness: CGFloat = 0.18) where Label == EmptyView {
        self.init(shares: shares, thickness: thickness) { EmptyView() }
    }

    public init(
        shares: [Double], thickness: CGFloat = 0.18, @ViewBuilder label: () -> Label
    ) {
        self.shares = shares
        self.thickness = thickness
        self.label = label()
    }

    var normalised: [Double] {
        let total = shares.reduce(0) { $0 + max(0, $1) }
        guard total > 0 else { return [] }
        return shares.map { max(0, $0) / total }
    }

    /// Each slice's angular sweep, with the gaps already taken out.
    ///
    /// Not simply `share * 2π`. A round cap overhangs its arc by half the
    /// stroke at each end, so a slice thinner than two caps cannot be drawn at
    /// its true width — and drawn at the width it *has*, neighbouring small
    /// slices sat on top of each other. Claude's four models did exactly that:
    /// 23.15B drew an arc and the 0.59B beside it drew a blob through it.
    ///
    /// So every non-zero slice is floored at one cap's worth of arc, and the
    /// excess is taken back from the slices that have room, proportionally.
    /// The ring stops being exactly to scale at the bottom end. That is the
    /// right trade: a 2% slice is already too small to measure by eye, and the
    /// honest alternatives are drawing it on top of its neighbour or not
    /// drawing it at all.
    func sweeps(cap: Double, gap: Double) -> [Double] {
        let slices = normalised
        guard !slices.isEmpty else { return [] }

        let available = 2 * .pi - gap * Double(slices.count)
        guard available > 0 else { return slices.map { _ in 0 } }

        let floor = 2 * cap
        var sweeps = slices.map { $0 * available }

        // Which slices are being raised, and which can pay for it. A zero
        // share is not raised: it is not there.
        let raised = zip(slices, sweeps).filter { $0.0 > 0 && $0.1 < floor }
        guard !raised.isEmpty else { return sweeps }

        let owed = raised.reduce(0) { $0 + (floor - $1.1) }
        let spare = sweeps.filter { $0 >= floor }.reduce(0) { $0 + ($1 - floor) }

        guard spare > owed else {
            // Too many slices for the ring to show them all at a readable
            // size. Equal arcs say "these are the categories" without
            // pretending to a precision the shape cannot carry.
            return slices.map { $0 > 0 ? available / Double(slices.count) : 0 }
        }

        return zip(slices, sweeps).map { share, sweep in
            if share <= 0 { return 0 }
            if sweep < floor { return floor }
            return sweep - (sweep - floor) * owed / spare
        }
    }

    public var body: some View {
        ZStack {
            Canvas { context, size in
                let outer = min(size.width, size.height) / 2
                let width = outer * thickness
                let radius = outer - width / 2
                let slices = normalised
                guard radius > 0, !slices.isEmpty else { return }

                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                // How far a round cap reaches past its arc, as an angle.
                let cap = Double(width / 2 / radius)
                // Capped at three degrees, and at a quarter of an equal share
                // so a ring of many slices is not mostly gap. A single slice
                // takes none: a lone ring with a notch in it reads as missing
                // data rather than as the whole.
                let gap =
                    slices.count > 1
                    ? min(.pi / 60, (2 * .pi) / Double(slices.count) / 4)
                    : 0
                let widths = sweeps(cap: cap, gap: gap)

                // From twelve o'clock, clockwise — where a reader starts.
                var start = -Double.pi / 2
                for (index, sweep) in widths.enumerated() {
                    guard sweep > 0 else { continue }
                    let shading = GraphicsContext.Shading.color(SliceColours.at(index))

                    // Inset by one cap at each end so the drawn extent is the
                    // sweep, not the sweep plus two overhangs.
                    if sweep > 2 * cap + 0.001 {
                        var path = Path()
                        path.addArc(
                            center: centre, radius: radius,
                            startAngle: .radians(start + cap),
                            endAngle: .radians(start + sweep - cap),
                            clockwise: false)
                        context.stroke(
                            path, with: shading,
                            style: StrokeStyle(lineWidth: width, lineCap: .round))
                    } else {
                        // At the floor: the two caps *are* the slice, so it is
                        // a dot. Centred in its own sweep, which the gaps have
                        // already kept clear of its neighbours.
                        let middle = start + sweep / 2
                        let point = CGPoint(
                            x: centre.x + radius * cos(middle),
                            y: centre.y + radius * sin(middle))
                        context.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: point.x - width / 2, y: point.y - width / 2,
                                    width: width, height: width)),
                            with: shading)
                    }
                    start += sweep + gap
                }
            }

            // The hole is the point of the shape: it is where the total goes.
            // Inset off the hole's own diameter, so the figure clears the ring
            // rather than touching it at the corners of its frame.
            GeometryReader { proxy in
                let hole = min(proxy.size.width, proxy.size.height) * (1 - thickness)
                label
                    .frame(width: hole * 0.72, height: hole * 0.72)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
