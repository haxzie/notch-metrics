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

    /// Whether there is an account behind the numbers.
    ///
    /// Defaults to true so a signed-in user never sees the sign-in panel
    /// flash on the way past: the app only knows the answer after reading the
    /// Keychain, which is async, and the honest "not yet known" state looks
    /// exactly like "signed out" if it is drawn.
    public var isSignedIn = true

    /// True while the browser handshake is out. The panel says so rather than
    /// leaving a button that has visibly done nothing for ten seconds.
    public var isSigningIn = false

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

    /// True when the widget being configured was *just* added from the
    /// browser, so the pane commits with Add and Cancel takes it back out.
    ///
    /// The widget is already on the grid by then — it has to be, or the
    /// preview behind the pane would be of a tile that does not exist — so
    /// what Add confirms is the configuration, and what Cancel undoes is the
    /// whole addition.
    public var configuringIsNew = false

    /// The configure pane closed itself — Done, Add or Cancel. The controller
    /// may be holding the notch open on the pane's behalf and needs to let go.
    public var onEndConfiguring: @MainActor () -> Void = {}

    /// True while the notch is showing the widget browser instead of the grid.
    ///
    /// Browsing used to be a window of its own, flush with the bottom of the
    /// screen, which put the widgets being chosen and the notch they were
    /// going into at opposite edges of the display — and made adding one a
    /// drag across the whole screen. Same move as the configure pane: the
    /// notch is the thing being changed, so it hosts this too.
    public var isBrowsing = false

    /// The browser's sidebar, search field and widget list.
    ///
    /// Supplied by the app target for the same reason `configuratorPanel` is:
    /// it needs the server's catalogue and the user's connections. NotchUI
    /// owns the panel it sits in and nothing inside it.
    public var browserPanel: @MainActor () -> AnyView = { AnyView(EmptyView()) }

    /// Browsing ended — Done, or a widget was picked. As with the configure
    /// pane, the controller may be holding the notch open for it.
    public var onEndBrowsing: @MainActor () -> Void = {}

    /// True while the notch is showing the notification centre.
    ///
    /// Mutually exclusive with `isBrowsing` and `configuringID`; the controller
    /// enforces that, and `NotchContentView.bodyKind` is ordered as a backstop.
    public var isShowingAlerts = false

    /// The notification centre's sidebar and list.
    ///
    /// From the app target, for exactly the reason `browserPanel` is: it needs
    /// the user's connections.
    public var alertCentrePanel: @MainActor () -> AnyView = { AnyView(EmptyView()) }

    /// Which connection the pane should open on, when the way in named one —
    /// a banner click, a deep link. Cleared by the pane once honoured.
    public var alertsFocus: AlertFocus?

    /// Drives the bell's badge and the dot on the collapsed notch. Forwarded
    /// immediately rather than on the next refresh, like `isSignedIn`.
    public var unreadAlertCount = 0

    /// The notification currently out of the notch, if any.
    public var bannerAlert: NotchAlert?

    /// How far through the drop the banner is.
    ///
    /// Two steps rather than one, because the shape is doing two different
    /// things: a circle falls clear of the notch first, and only then opens
    /// into a card. Driven by the controller's timer, not by the view — the
    /// view just renders whichever step it is on.
    public var bannerIsOpen = false

    /// The banner was clicked: open its link, or the centre if it has none.
    public var onBannerTapped: @MainActor () -> Void = {}

    public var onEndAlerts: @MainActor () -> Void = {}
    /// The bell was pressed.
    public var onOpenAlerts: @MainActor () -> Void = {}

    public var onOpenSettings: @MainActor () -> Void = {}
    /// Fetch every tile again, now.
    public var onRefresh: @MainActor () -> Void = {}
    /// Opens the app on this widget's configuration.
    public var onConfigureWidget: @MainActor (NotchWidget) -> Void = { _ in }
    /// Opens the share editor on a tile, with the number it is showing right
    /// now. The request carries the resolved app and state rather than an id,
    /// because the notch is the only place that has both — see `ShareRequest`.
    public var onShareWidget: @MainActor (ShareRequest) -> Void = { _ in }
    /// Opens the browser of widgets that can be added.
    public var onAddWidget: @MainActor () -> Void = {}
    /// Starts the browser sign-in handshake.
    public var onSignIn: @MainActor () -> Void = {}
    public var onTogglePin: @MainActor () -> Void = {}
    public var onClose: @MainActor () -> Void = {}

    public init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}
