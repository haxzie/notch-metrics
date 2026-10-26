import SwiftUI

/// The handle's band *is* the fade.
///
/// Not a strip drawn on top of it. An overlay above the band leaves the band
/// itself opaque, so a tile still ends at a hard line and the gradient reads
/// as a smudge floating over the panel. Here the grid runs behind the band
/// and the ramp spans the band's whole height, so the last row thins out
/// across exactly the distance the handle occupies and is gone by the time it
/// reaches the bottom edge.
///
/// That is why this takes the band's height rather than a ramp length of its
/// own: the two are the same number by definition, and passing them
/// separately is how they drift apart.
///
/// Top edge deliberately untouched. The header is a solid band of controls at
/// a fixed height, and fading content into it buys nothing its own opacity
/// does not already give.
public struct GridEdgeSoftening: ViewModifier {
    /// How far the grid runs underneath the handle's band.
    public let bandHeight: CGFloat

    public init(bandHeight: CGFloat) {
        self.bandHeight = bandHeight
    }

    /// Solid until the band begins, clear by the time it ends.
    ///
    /// Clamped to half the viewport: a one-row grid under a tall band would
    /// otherwise fade the only row on screen from its middle down.
    func stops(in height: CGFloat) -> [Gradient.Stop] {
        let total = max(height, 1)
        let band = min(max(bandHeight, 0), total / 2)
        let start = min(max((total - band) / total, 0), 1)

        return [
            .init(color: .black, location: 0),
            .init(color: .black, location: start),
            .init(color: .clear, location: 1),
        ]
    }

    public func body(content: Content) -> some View {
        content.mask {
            GeometryReader { proxy in
                LinearGradient(
                    stops: stops(in: proxy.size.height),
                    startPoint: .top,
                    endPoint: .bottom)
            }
            // The mask has to cover the scroll view's whole box, including the
            // part behind the band. Without this it measures only the inset
            // content and the ramp lands above the band rather than across it.
            .ignoresSafeArea()
        }
    }
}

extension View {
    /// Applied to the grid, and nowhere else: every other body is a panel
    /// that fills the notch and ends where it means to.
    public func softGridEdges(bandHeight: CGFloat) -> some View {
        modifier(GridEdgeSoftening(bandHeight: bandHeight))
    }
}
