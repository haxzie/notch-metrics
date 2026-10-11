import AppKit
import SwiftUI
import Testing

@testable import NotchUI

/// The sparkline draws two things the plotting rect does not account for on
/// its own: a stroke centred on the line, and a dot centred on the last
/// point. An inset smaller than either silently crops the chart at the edge
/// of the tile, which reads as a rendering fault rather than as a margin
/// being one point short.
/// Every tile height a widget can ask for, from a one-row tile's 12pt band
/// to the 60pt cap.
private let tileSizes: [CGSize] = [
    CGSize(width: 56, height: 12), CGSize(width: 120, height: 18),
    CGSize(width: 187, height: 24), CGSize(width: 187, height: 42),
    CGSize(width: 420, height: 60),
]

@MainActor
@Suite("Sparkline geometry")
struct SparklineGeometryTests {

    @Test("the end dot fits whichever point it lands on", arguments: tileSizes)
    func dotFits(size: CGSize) {
        let rect = Sparkline.drawingRect(in: size)
        // The dot is centred anywhere on the rect's boundary — the last
        // point can be the maximum or the minimum.
        let envelope = rect.insetBy(dx: -Sparkline.dotRadius, dy: -Sparkline.dotRadius)
        #expect(envelope.minX >= 0)
        #expect(envelope.minY >= 0)
        #expect(envelope.maxX <= size.width)
        #expect(envelope.maxY <= size.height)
    }

    @Test("the stroke fits around the highest and lowest points", arguments: tileSizes)
    func strokeFits(size: CGSize) {
        let rect = Sparkline.drawingRect(in: size)
        let half = Sparkline.lineWidth / 2
        #expect(rect.minY - half >= 0)
        #expect(rect.maxY + half <= size.height)
    }

    /// The symptom, as seen: peaks and troughs sliced flat against the edge
    /// of the tile. Two separate causes — an inset narrower than the dot,
    /// and a spline that overshot the data — so this asserts the outcome
    /// rather than either mechanism.
    @Test("nothing is cut off at the top or the bottom", arguments: [
        // Peak in the middle.
        [2.0, 18, 3, 2, 30, 6, 22, 4, 3, 3],
        // Highest value is also the most recent, so the end dot is at the top.
        [2.0, 18, 3, 2, 12, 6, 22, 4, 3, 30],
        // Lowest value is the most recent: the dot is at the bottom.
        [30.0, 18, 3, 12, 22, 6, 22, 4, 3, 2],
        // Repeated lows, which is what made the spline dip below the floor.
        [2.0, 2, 2, 24, 3, 2, 2, 19, 2, 2],
        // A single spike, the sharpest turn the smoothing has to survive.
        [1.0, 1, 1, 1, 60, 1, 1, 1, 1, 1],
    ])
    func nothingIsClipped(values: [Double]) throws {
        let size = CGSize(width: 187, height: 42)
        let view = Sparkline(values: values, tint: .red)
            .frame(width: size.width, height: size.height)
            .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let bitmap = try #require(
            renderer.nsImage?.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))

        // Alpha-weighted: the renderer hands back a bitmap with an alpha
        // channel, and a fully transparent pixel still carries whatever RGB
        // it was last filled with. Reading `redComponent` alone finds ink
        // that is not on screen.
        func isInked(_ x: Int, _ y: Int) -> Bool {
            guard let colour = bitmap.colorAt(x: x, y: y) else { return false }
            return colour.redComponent * colour.alphaComponent > 0.30
        }

        // The dot may sit flush with the left and right edges — it is inset
        // by exactly its own radius there. Never the top or the bottom,
        // where flush means a peak with its head cut off.
        for row in [0, bitmap.pixelsHigh - 1] {
            let inked = (0..<bitmap.pixelsWide).contains { isInked($0, row) }
            #expect(!inked, "ink on row \(row) of \(bitmap.pixelsHigh) — the chart is clipped")
        }
    }
}
