import MetricsCore
import SwiftUI

/// Configuring one widget, inside the notch.
///
/// A split rather than a stack: the preview is the whole point of configuring
/// something, and a form that pushes its own result off the top of the panel
/// as you scroll is a form you have to keep scrolling back up in. The notch is
/// much wider than it is tall, so side by side is also the only arrangement
/// that fits.
///
/// The controls themselves come from the app target — they need the server's
/// catalogue and the user's connections, neither of which this package knows
/// about. What lives here is the split, the preview and the chrome around it.
public struct WidgetConfigurePane: View {
    let widget: NotchWidget
    let app: MetricApp
    let state: TileState
    let panel: @MainActor (NotchWidget) -> AnyView

    public init(
        widget: NotchWidget,
        app: MetricApp,
        state: TileState,
        panel: @escaping @MainActor (NotchWidget) -> AnyView
    ) {
        self.widget = widget
        self.app = app
        self.state = state
        self.panel = panel
    }

    public var body: some View {
        HStack(spacing: 0) {
            preview
                .frame(width: 236)
            Divider()
                .opacity(0.35)
                .padding(.vertical, 4)
            panel(widget)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.leading, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The tile as it will actually look, on the same recessed surface the
    /// grid uses in edit mode — so moving between the two does not change what
    /// the tile is sitting on.
    private var preview: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            WidgetTile(widget: widget, app: app, state: state)
                .frame(width: tileSize.width, height: tileSize.height)
                .animation(.snappy(duration: 0.22), value: widget.size)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(NotchTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .padding(.trailing, 14)
    }

    private var label: String {
        "\(app.name) · \(widget.size.rawValue)"
    }

    /// Close to the notch's own cell, capped so a 6x2 does not push the panel
    /// wider than the column.
    ///
    /// At 46 the preview was a little over half scale, and since the text
    /// inside does not scale with it the headline figure truncated — a
    /// preview showing "$2…" for a tile that renders "$20.69" is worse than
    /// no preview.
    private var tileSize: CGSize {
        let unit: CGFloat = 64
        let gap: CGFloat = 9
        let cols = min(CGFloat(widget.size.cols), 3)
        let rows = CGFloat(widget.size.rows)
        return CGSize(
            width: cols * unit + (cols - 1) * gap,
            height: min(rows * unit + (rows - 1) * gap, 168))
    }
}
