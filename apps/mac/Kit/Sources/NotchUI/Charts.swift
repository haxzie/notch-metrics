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
                let area = abs(
                    (previous.x - avgX) * (point.y - previous.y)
                        - (previous.x - point.x) * (avgY - previous.y)
                ) / 2
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

            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) * tension, y: p1.y + (p2.y - p0.y) * tension)
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) * tension, y: p2.y - (p3.y - p1.y) * tension)
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

    public init(values: [Double], tint: Color = .accentColor, fill: Bool = true) {
        self.values = values
        self.tint = tint
        self.fill = fill
    }

    public var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 2)
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
                context.fill(
                    area,
                    with: .linearGradient(
                        Gradient(colors: [tint.opacity(0.28), tint.opacity(0.0)]),
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            }

            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            if let last = points.last {
                context.fill(
                    Path(ellipseIn: CGRect(x: last.x - 2, y: last.y - 2, width: 4, height: 4)),
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
                context.fill(
                    Path(roundedRect: bar, cornerRadius: min(1.5, barWidth / 2)),
                    with: .color(tint.opacity(0.85)))
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
