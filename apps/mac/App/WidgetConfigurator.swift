import AppKit
import MetricsAPI
import MetricsCore
import NotchUI
import SwiftUI

/// Configures a widget that is already in the notch.
///
/// Opened the moment one is dropped in, because a freshly dragged widget has
/// no account behind it and renders as "Pick a connection" — a tile that
/// appears already broken. This is the screen that finishes the job, and it
/// is reachable again later from the tile's own sliders button.
struct WidgetConfiguratorView: View {
    let widgetId: String

    @Environment(AppEnvironment.self) private var env
    @State private var model = WidgetCatalogueModel()
    @State private var preview: TileState = .loading
    @State private var draft: NotchWidget?

    private var entry: ConnectorEntry? {
        guard let draft else { return nil }
        return model.entry(draft.appId)
    }

    private var descriptor: MetricDescriptor? {
        guard let draft, let metric = draft.metric else { return nil }
        return entry?.metrics.first { $0.id == metric }
    }

    var body: some View {
        Group {
            if let draft {
                form(draft)
            } else {
                // The widget was removed from the notch while this was open.
                VStack(spacing: 8) {
                    Text("That widget is no longer in the notch.")
                        .font(.headline)
                    Text("Close this window and add it again.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await model.load(env: env)
            draft = env.layoutModel.layout.widgets.first { $0.id == widgetId }
            await refreshPreview()
        }
    }

    private func form(_ widget: NotchWidget) -> some View {
        let binding = Binding<NotchWidget>(
            get: { draft ?? widget },
            set: { next in
                draft = next
                // Written straight through rather than on a Done button: the
                // tile is visible in the notch behind this window, so every
                // change is already being previewed in the place that counts.
                env.layoutModel.update(next)
            })
        let live = binding.wrappedValue
        let app = AppCatalog.resolve(live.appId)

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(live, app: app)
                previewCard(live, app: app)
                connectionSection(binding)
                appearanceSection(binding)
                dataSection(binding)
                removeButton
            }
            .padding(20)
        }
        .overlay(alignment: .top) { topFade }
        // Reserves the title bar's height rather than guessing at a top
        // padding: the content now runs underneath it, and scrolling up under
        // a transparent title bar is the look — colliding with it is not.
        .safeAreaInset(edge: .top) { Color.clear.frame(height: 24) }
        // Without this the scroll view paints an opaque backing and the
        // window's glass is invisible behind it — which is most of what made
        // the first version of this look like a dialog box from another app.
        .scrollContentBackground(.hidden)
    }

    private func header(_ widget: NotchWidget, app: MetricApp) -> some View {
        HStack(spacing: 10) {
            ConnectorIcon(app: app, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(descriptor?.label ?? widget.title ?? "Widget")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(app.name)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func previewCard(_ widget: NotchWidget, app: MetricApp) -> some View {
        HStack {
            Spacer()
            WidgetTile(widget: widget, app: app, state: preview)
                .frame(
                    width: previewSize(widget).width,
                    height: previewSize(widget).height)
            Spacer()
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.25)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }

    @ViewBuilder
    private func connectionSection(_ binding: Binding<NotchWidget>) -> some View {
        section("Connection") {
            if let entry, !entry.connections.isEmpty {
                row("Account") {
                    Picker("", selection: Binding(
                        get: { binding.wrappedValue.integrationId ?? "" },
                        set: { id in
                            var next = binding.wrappedValue
                            next.integrationId = id.isEmpty ? nil : id
                            binding.wrappedValue = next
                            Task { await refreshPreview() }
                        }
                    )) {
                        Text("None").tag("")
                        ForEach(entry.connections) { connection in
                            Text(connection.label).tag(connection.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            } else {
                note("No account connected yet. The tile shows a placeholder until there is one.")
            }

            if let entry {
                Divider().opacity(0.4)
                HStack {
                    // Right, with the pickers. Every other control in this
                    // window is on the trailing edge, and a button alone on
                    // the left reads as belonging to a different group.
                    Spacer(minLength: 0)
                    ConnectButton(app: entry, model: model) { newId in
                        var next = binding.wrappedValue
                        next.integrationId = newId
                        binding.wrappedValue = next
                        Task { await refreshPreview() }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private func appearanceSection(_ binding: Binding<NotchWidget>) -> some View {
        section("Appearance") {
            row("Size") {
                Picker("", selection: Binding(
                    get: { binding.wrappedValue.size },
                    set: { size in
                        var next = binding.wrappedValue
                        next.size = size
                        binding.wrappedValue = next
                    }
                )) {
                    ForEach(WidgetSize.presets, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }
            Divider().opacity(0.4)
            row("Numbers") {
                Picker("", selection: Binding(
                    get: { binding.wrappedValue.format?.compact ?? true },
                    set: { compact in
                        var next = binding.wrappedValue
                        var format = next.format ?? WidgetFormat()
                        format.compact = compact
                        next.format = format
                        binding.wrappedValue = next
                    }
                )) {
                    Text("Short — 1.2M").tag(true)
                    Text("Full — 1,243,901").tag(false)
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider().opacity(0.4)
            row("Chart") {
                Picker("", selection: Binding(
                    get: { binding.wrappedValue.chart },
                    set: { chart in
                        var next = binding.wrappedValue
                        next.chart = chart
                        binding.wrappedValue = next
                    }
                )) {
                    Text("None").tag(ChartKind.none)
                    Text("Sparkline").tag(ChartKind.sparkline)
                    Text("Bars").tag(ChartKind.bars)
                }
                .labelsHidden()
                .fixedSize()
                .disabled(descriptor?.supportsSeries == false)
            }
        }
    }

    @ViewBuilder
    private func dataSection(_ binding: Binding<NotchWidget>) -> some View {
        section("Data") {
            row("Range") {
                Picker("", selection: Binding(
                    get: { binding.wrappedValue.range },
                    set: { range in
                        var next = binding.wrappedValue
                        next.range = range
                        binding.wrappedValue = next
                        Task { await refreshPreview() }
                    }
                )) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if let descriptor {
                Divider().opacity(0.4)
                note(descriptor.methodology)
            }
        }
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            env.layoutModel.remove(widgetId)
            draft = nil
        } label: {
            Text("Remove from notch")
                .font(.system(size: 13))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.red.opacity(0.9))
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    /// A progressive blur over the top edge.
    ///
    /// Content runs under the title bar, and a plain scroll cut it off against
    /// a hard line. `.ultraThinMaterial` blurs what is behind it *within the
    /// window*, which here is the scrolling content — so a masked band of it
    /// is a real blur of the rows passing underneath, not a tint laid on top.
    ///
    /// Three bands rather than one. A single masked blur still ends on a
    /// visible edge where its mask runs out; stacking shorter bands ramps the
    /// *strength* of the blur rather than only its opacity, which is what
    /// makes the falloff read as gradual.
    private var topFade: some View {
        ZStack(alignment: .top) {
            fadeBand(height: 54)
            fadeBand(height: 38)
            fadeBand(height: 22)
        }
        .frame(height: 54)
        .allowsHitTesting(false)
    }

    private func fadeBand(height: CGFloat) -> some View {
        Rectangle()
            .fill(.clear)
            .background(.ultraThinMaterial)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.65), location: 0.45),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            )
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Pieces

    /// A titled group of rows on one translucent card.
    ///
    /// Hand-built rather than `Form(.grouped)`, which paints its own opaque
    /// background and ignores the window's material entirely.
    private func section<V: View>(
        _ title: String, @ViewBuilder content: () -> V
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func row<V: View>(_ label: String, @ViewBuilder control: () -> V) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 13))
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }

    private func previewSize(_ widget: NotchWidget) -> CGSize {
        // Bigger than the notch's own cell. At the real size a 1x1 preview is
        // a thumbnail with three truncated words in it, and the point of the
        // preview is to be readable.
        let unit: CGFloat = 64
        let gap: CGFloat = 10
        let cols = min(CGFloat(widget.size.cols), 3)
        let rows = CGFloat(widget.size.rows)
        return CGSize(
            width: cols * unit + (cols - 1) * gap,
            height: rows * unit + (rows - 1) * gap)
    }

    private func refreshPreview() async {
        guard let draft, let metric = draft.metric else { return }
        guard let connection = draft.integrationId else {
            preview = .needsSetup("Pick a connection")
            return
        }
        preview = .loading
        do {
            let result = try await env.api.metric(
                integrationId: connection,
                metric: metric,
                granularity: draft.granularity.rawValue,
                range: draft.range.rawValue)
            switch result {
            case .success(let series): preview = .value(series)
            case .failure(let failure): preview = .failed(reason: failure.message)
            }
        } catch {
            preview = .failed(reason: "Could not load a preview")
        }
    }
}

/// Owns the configurator window.
@MainActor
final class WidgetConfiguratorWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    func show(widgetId: String) {
        window?.close()

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 700),
            // `.fullSizeContentView` so the material runs the full height of
            // the window. Without it the effect view stops below the title
            // bar, and since the window itself is clear that strip showed
            // straight through — a transparent band above a frosted body.
            // Clearing the title bar is the content's job, below.
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "Configure Widget"
        window.titlebarAppearsTransparent = true
        window.minSize = CGSize(width: 380, height: 480)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.delegate = self
        window.isReleasedWhenClosed = false

        window.contentView = glassContentView {
            WidgetConfiguratorView(widgetId: widgetId)
                .environment(env)
                .ignoresSafeArea()
        }
        // Beside the notch rather than centred: the tile it configures is at
        // the top of the screen and a window in the middle makes you look away
        // from the thing you are changing.
        window.center()
        if let screen = NSScreen.main {
            let frame = window.frame
            window.setFrameOrigin(
                CGPoint(
                    x: screen.visibleFrame.maxX - frame.width - 40,
                    y: screen.visibleFrame.maxY - frame.height - 20))
        }
        self.window = window

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            let remaining = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }
            if remaining.isEmpty { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
