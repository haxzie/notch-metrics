import MetricsCore
import SwiftUI

/// Everything the notch's SwiftUI tree reads, in one observable object.
///
/// This exists because the alternative does not work. Passing these as plain
/// values meant the controller had to rebuild the `NSHostingView` whenever any
/// of them changed — and a brand-new view tree has nothing to animate *from*,
/// so the expand transition never ran at all. It also meant a metric landing
/// mid-drag tore down the view holding the gesture.
///
/// With the tree built once and driven from here, SwiftUI diffs in place: the
/// spring runs, and a refresh during a drag is just a number changing.
@MainActor
@Observable
public final class NotchViewModel {
    public var presentation: NotchPresentation = .collapsed
    public var geometry: NotchGeometry
    public var isPinned = false
    public var states: [String: TileState] = [:]
    /// App identity from the server's provider manifests, once they load.
    public var appOverrides: [String: MetricApp] = [:]

    /// The size of the panel as actually rendered, reported back by the view.
    ///
    /// The window is much larger than what is drawn — it is sized once to the
    /// maximum so expansion never resizes it — so "has the pointer left the
    /// notch?" cannot be answered from the window frame. Recomputing the
    /// expected size in the controller would mean two copies of a calculation
    /// that depends on the display mode, the row count and, in list view, the
    /// content; they would drift within a week.
    public var visiblePanelSize: CGSize = .zero

    public var onOpenSettings: @MainActor () -> Void = {}
    public var onTogglePin: @MainActor () -> Void = {}
    public var onClose: @MainActor () -> Void = {}

    public init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}
