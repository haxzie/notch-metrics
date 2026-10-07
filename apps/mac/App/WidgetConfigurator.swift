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

        return Form {
            Section("Preview") {
                HStack {
                    Spacer()
                    WidgetTile(
                        widget: binding.wrappedValue,
                        app: AppCatalog.resolve(binding.wrappedValue.appId),
                        state: preview)
                        .frame(width: previewSize(binding.wrappedValue).width,
                               height: previewSize(binding.wrappedValue).height)
                        .padding(.vertical, 10)
                    Spacer()
                }
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }

            Section("Connection") {
                if let entry, !entry.connections.isEmpty {
                    Picker("Account", selection: Binding(
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
                } else {
                    Text("No account connected yet.")
                        .foregroundStyle(.secondary)
                }

                if let entry {
                    ConnectButton(app: entry, model: model) { newId in
                        var next = binding.wrappedValue
                        next.integrationId = newId
                        binding.wrappedValue = next
                        Task { await refreshPreview() }
                    }
                }
            }

            Section("Appearance") {
                Picker("Size", selection: Binding(
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

                Picker("Numbers", selection: Binding(
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

                Picker("Chart", selection: Binding(
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
                .disabled(descriptor?.supportsSeries == false)
            }

            Section("Data") {
                Picker("Range", selection: Binding(
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

                if let descriptor {
                    Text(descriptor.methodology)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    env.layoutModel.remove(widgetId)
                    draft = nil
                } label: {
                    Text("Remove from notch").frame(maxWidth: .infinity)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func previewSize(_ widget: NotchWidget) -> CGSize {
        let unit: CGFloat = 58
        let gap: CGFloat = 8
        let cols = CGFloat(widget.size.cols)
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
            contentRect: CGRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "Configure Widget"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.delegate = self
        window.isReleasedWhenClosed = false

        let root = ZStack {
            VisualEffectBackground(material: .hudWindow)
            WidgetConfiguratorView(widgetId: widgetId)
        }
        .environment(env)
        .ignoresSafeArea()

        window.contentView = NSHostingView(rootView: root)
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
