import MetricsCore
import SwiftUI

/// What a tile shows while its first number is in flight.
///
/// Shaped like the tile it is about to become rather than like a generic
/// spinner: a figure-sized bar where the figure goes, and a chart-shaped
/// block at the bottom edge when the widget draws one. A single centred
/// spinner makes every tile in the notch look identical while loading, so the
/// grid appears to collapse and then rebuild itself — the layout visibly
/// settles twice. Matching the real geometry means the only thing that
/// changes on arrival is the content.
///
/// Used in place of a verdict, never alongside one. A tile that does not yet
/// know whether it has an account has nothing true to say, and "Connect
/// Stripe" on a tile whose Stripe account is connected and merely unfetched
/// is worse than saying nothing.
struct TileSkeleton: View {
    /// The figure's height on the real tile. Passed in rather than
    /// recomputed, so the bar cannot drift from the number it stands in for.
    let valueHeight: CGFloat
    /// Zero when the widget draws no chart, which is also how a tile too
    /// small for one asks for no chart block.
    let chartHeight: CGFloat
    let chart: ChartKind

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            bar(width: valueHeight * 3.2, height: valueHeight * 0.8)
            Spacer(minLength: 0)

            if chartHeight > 0, chart != .none {
                chartBlock
                    .frame(height: chartHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shimmer()
        .accessibilityLabel("Loading")
    }

    /// Bars get bars and a line gets a wave: the silhouette is the only cue
    /// that distinguishes two loading tiles from each other, and it costs
    /// nothing to make it the right one.
    @ViewBuilder
    private var chartBlock: some View {
        switch chart {
        case .bars:
            // A fixed, uneven set of heights rather than random ones. Random
            // would re-roll on every SwiftUI re-evaluation, so the skeleton
            // would twitch while it waited.
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(Self.barHeights.enumerated()), id: \.offset) { _, fraction in
                    bar(width: nil, height: max(3, chartHeight * fraction))
                }
            }
        case .sparkline, .none:
            // Not a flat bar: a flat line is what the real chart draws for a
            // series that never moved, so a flat placeholder reads as a
            // loaded, boring metric rather than as one still loading.
            SkeletonWave()
                .fill(Color.white.opacity(0.07))
        }
    }

    private static let barHeights: [CGFloat] = [0.45, 0.7, 0.35, 0.85, 0.55, 0.95, 0.6, 0.8]

    private func bar(width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// A soft, fixed wave filling its rect — the silhouette of a sparkline with
/// no data behind it.
private struct SkeletonWave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 5
        // Deliberately not a sine: an evenly periodic placeholder reads as a
        // decoration. These are the same proportions the bar skeleton uses.
        let heights: [CGFloat] = [0.62, 0.3, 0.72, 0.42, 0.9, 0.55]
        let dx = rect.width / CGFloat(steps)

        func point(_ index: Int) -> CGPoint {
            CGPoint(
                x: rect.minX + dx * CGFloat(index),
                y: rect.maxY - rect.height * heights[min(index, heights.count - 1)])
        }

        path.move(to: point(0))
        for index in 1...steps {
            let previous = point(index - 1)
            let next = point(index)
            // Horizontal control points, which is what gives the line the
            // eased shoulders the real sparkline has.
            path.addCurve(
                to: next,
                control1: CGPoint(x: previous.x + dx / 2, y: previous.y),
                control2: CGPoint(x: next.x - dx / 2, y: next.y))
        }

        // Closed down to the baseline so it fills like the real chart does.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A highlight that travels across whatever it is applied to.
///
/// Masked by the content, so the sweep lights up the placeholder bars rather
/// than washing across the whole tile — at this size a full-tile sweep reads
/// as a rendering glitch on the glass.
private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.4

    func body(content: Content) -> some View {
        // Reduce Motion matters more here than in most apps: the notch opens
        // under the pointer several times an hour, unprompted, and a looping
        // animation inside it is exactly the kind of thing the setting is
        // for. The bars are legible as placeholders without it.
        if reduceMotion {
            content
        } else {
            content
                .overlay(sweep.mask(content))
                .onAppear {
                    withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                        phase = 1.4
                    }
                }
        }
    }

    private var sweep: some View {
        GeometryReader { proxy in
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.white.opacity(0.13), location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: proxy.size.width * 0.6)
            .offset(x: phase * proxy.size.width)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}
