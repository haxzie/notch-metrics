import AppKit
import MetricsAPI
import MetricsCore
import NotchUI
import SwiftUI

/// The controls for one widget, shown in the notch's configure pane.
///
/// Only the form. The split, the preview and the chrome belong to
/// `WidgetConfigurePane` in NotchUI — this is the half that needs the server's
/// catalogue and the user's connections, which is why it lives here.
///
/// Opened the moment a widget is dropped in, because a freshly dragged one has
/// no account behind it and renders as "Pick a connection" — a tile that
/// appears already broken.
struct WidgetConfigPanel: View {
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
                        .font(.system(size: 13, weight: .semibold))
                    Text("Press Done and add it again.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            // The widget first, the catalogue second. They were the other way
            // round, so until the network came back the pane showed its
            // "no longer in the notch" state for a widget that was plainly
            // sitting in the preview beside it.
            draft = env.layoutModel.layout.widgets.first { $0.id == widgetId }
            await refreshPreview()
            await model.load(env: env)
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
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                connectionSection(binding)
                appearanceSection(binding)
                dataSection(binding)
                removeButton
            }
            .padding(.trailing, 14)
            // Clear of the fade, so the last control is reachable rather than
            // sitting permanently under the blur.
            .padding(.bottom, Self.bottomFadeHeight)
        }
        // Without this the scroll view paints an opaque backing and the
        // notch's own fill shows through nothing — the panel ends up looking
        // like a dialog from another app pasted into it.
        .scrollContentBackground(.hidden)
        .overlay(alignment: .bottom) { bottomFade }
    }

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

    /// A progressive blur along the bottom edge.
    ///
    /// The pane is a fixed height and the form is taller than it, so there is
    /// almost always something below the fold — and a column that simply
    /// stopped at the edge gave no sign of it.
    ///
    /// `.ultraThinMaterial` blurs what is behind it *within the window*, which
    /// here is the scrolling form, so this is a real blur of the rows passing
    /// under it rather than a tint laid over them. Three stacked bands rather
    /// than one: a single masked blur still ends on a line you can see, and
    /// stacking shorter bands ramps the strength instead of only the opacity.
    private var bottomFade: some View {
        ZStack(alignment: .bottom) {
            fadeBand(height: Self.bottomFadeHeight)
            fadeBand(height: Self.bottomFadeHeight * 0.66)
            fadeBand(height: Self.bottomFadeHeight * 0.38)
        }
        .frame(height: Self.bottomFadeHeight)
        .allowsHitTesting(false)
    }

    private func fadeBand(height: CGFloat) -> some View {
        Rectangle()
            .fill(.clear)
            .background(.ultraThinMaterial)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.18), location: 0.3),
                        .init(color: .black.opacity(0.55), location: 0.6),
                        .init(color: .black.opacity(0.85), location: 0.82),
                        .init(color: .black, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom)
            )
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private static let bottomFadeHeight: CGFloat = 34

    // MARK: - Pieces

    /// A titled group of rows on one translucent card.
    ///
    /// Hand-built rather than `Form(.grouped)`, which paints its own opaque
    /// background and ignores the notch's material entirely.
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
