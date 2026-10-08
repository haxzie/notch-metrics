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

    /// What each connection is called, by integration id.
    ///
    /// A tile says which *account* it reads, not which app: somebody with two
    /// Stripe accounts had two tiles both saying "Stripe". Server state rather
    /// than something on the widget, because renaming a connection has to
    /// change every tile using it at once.
    public var connectionNames: [String: String] = [:]

    /// Metrics whose number depends on the widget's time window, by
    /// `NotchWidget.metricKey`.
    ///
    /// Those tiles write the window into their title. From the server's
    /// catalogue and the installed plugins rather than stored on the widget:
    /// the descriptor is the one place that knows, and a copy on every widget
    /// would be wrong for every widget made before the copy existed.
    public var timeWindowedMetrics: Set<String> = []

    /// The size of the panel as actually rendered, reported back by the view.
    ///
    /// The window is much larger than what is drawn — it is sized once to the
    /// maximum so expansion never resizes it — so "has the pointer left the
    /// notch?" cannot be answered from the window frame. Recomputing the
    /// expected size in the controller would mean two copies of a calculation
    /// that depends on the display mode, the row count and, in list view, the
    /// content; they would drift within a week.
    public var visiblePanelSize: CGSize = .zero

    /// True while a manual refresh is in flight, so the button can say so.
    public var isRefreshing = false

    /// True while a gesture owns the pointer — a handle drag, a tile being
    /// moved or resized.
    ///
    /// The collapse watch has to stand down for the duration. A drag towards
    /// the bottom edge takes the pointer out of the panel, and collapsing
    /// there pulls the window out from under the gesture: the notch shuts
    /// mid-drag and the change is lost.
    public var isInteracting = false

    /// The widget being configured, if any.
    ///
    /// Configuration used to be a window of its own, which meant the app threw
    /// a second window on screen every time a tile was dropped or a slider
    /// button pressed — on top of whatever the user was working in, and with
    /// its own activation and focus to manage. The notch is already open and
    /// already the thing being changed, so it hosts this instead.
    public var configuringID: String?

    /// The widget as it was when configuring began.
    ///
    /// The form writes every change straight through to the layout, because
    /// the tile is on screen behind it and a preview that lags the controls is
    /// worse than one that does not. That leaves nothing buffered to throw
    /// away, so Cancel needs a copy taken on the way in.
    public var configuringSnapshot: NotchWidget?

    /// How tall the configure form is, as measured by the form itself.
    ///
    /// Zero until it has laid out once. The pane is sized from this rather
    /// than from a guess, because the form belongs to the app target and will
    /// grow a row the moment somebody adds a setting.
    public var configureContentHeight: CGFloat = 0

    /// The controls for the widget being configured.
    ///
    /// Supplied by the app target, which is the only place that knows about
    /// connections and the server's catalogue. NotchUI owns the split, the
    /// preview and the transition; it does not own the form.
    public var configuratorPanel: @MainActor (NotchWidget) -> AnyView = { _ in
        AnyView(EmptyView())
    }

    public var onOpenSettings: @MainActor () -> Void = {}
    /// Fetch every tile again, now.
    public var onRefresh: @MainActor () -> Void = {}
    /// Opens the app on this widget's configuration.
    public var onConfigureWidget: @MainActor (NotchWidget) -> Void = { _ in }
    /// Opens the gallery of widgets that can be added.
    public var onAddWidget: @MainActor () -> Void = {}
    /// A widget dragged out of the gallery and dropped on the grid.
    ///
    /// The payload is opaque here on purpose: turning "stripe/mrr" into a
    /// `NotchWidget` needs the server's catalogue, which belongs to the app
    /// target. NotchUI only knows where it landed.
    public var onDropWidget: @MainActor (String, Int) -> Bool = { _, _ in false }
    public var onTogglePin: @MainActor () -> Void = {}
    public var onClose: @MainActor () -> Void = {}

    public init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}
