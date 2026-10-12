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
