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
    @State private var draft: NotchWidget?

    private var entry: ConnectorEntry? {
        guard let draft else { return nil }
        return model.entry(draft.appId)
    }

    /// Whether a time window means anything for this metric.
    ///
    /// A snapshot — GitHub's stargazers, forks, open issues — is whatever it
    /// is right now. There is no series to draw over 30 days and no previous
    /// window to compare against, so a range picker on one of those is a
    /// control that changes nothing.
    ///
    /// Defaults to showing it: before the catalogue has loaded there is no
    /// descriptor to ask, and a control that appears a moment late is better
    /// than one that disappears a moment late.
    private var usesTimeWindow: Bool {
        guard let descriptor else { return true }
        return descriptor.supportsSeries || descriptor.supportsCompare
    }

    /// Whether this metric can be drawn as a chart at all.
    private var usesChart: Bool { descriptor?.supportsSeries != false }

    /// The connection this widget reads, if the catalogue knows it.
    private var selectedConnection: ConnectorConnection? {
        guard let id = draft?.integrationId else { return nil }
        return entry?.connections.first { $0.id == id }
    }

    /// The widget's own name, prefilled with the connection's.
    ///
    /// Prefilled by reading through to the connection rather than by copying
    /// its label onto the widget: a copy taken on appear raced the catalogue
    /// load and left the field blank for a connection that plainly had a
    /// name. Clearing the field goes back to following the connection.
    private func nameField(_ binding: Binding<NotchWidget>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue.name ?? selectedConnection?.label ?? "" },
            set: { typed in
                var next = binding.wrappedValue
                let trimmed = typed.trimmingCharacters(in: .whitespaces)
                next.name = trimmed.isEmpty ? nil : typed
                binding.wrappedValue = next
            })
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
            .padding(.bottom, 6)
            // Reports its natural height so the notch can open tall enough to
            // show all of it. Safe from a layout loop: inside a scroll view
            // the form's height does not depend on the viewport it is given.
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ConfigurePanelHeightKey.self, value: proxy.size.height)
                })
        }
        // Without this the scroll view paints an opaque backing and the
        // notch's own fill shows through nothing — the panel ends up looking
        // like a dialog from another app pasted into it.
        .scrollContentBackground(.hidden)
    }

    private func connectionSection(_ binding: Binding<NotchWidget>) -> some View {
        section("Connection") {
            if let entry {
                if entry.connections.isEmpty {
                    // The same row as the picker, with the connect button
                    // standing in for it. A note saying there is no account
                    // explained the state but offered no way out of it, and
                    // the way out was a second row underneath saying much the
                    // same thing again.
                    row("Account") {
                        ConnectButton(app: entry, model: model) { newId in
                            var next = binding.wrappedValue
                            next.integrationId = newId
                            binding.wrappedValue = next
                            Task { await env.refresh() }
                        }
                    }
                } else {
                    row("Name") {
                        // Names this widget only. The connection keeps its
                        // own name, and the other tiles reading it keep
                        // showing that.
                        TextField("", text: nameField(binding))
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .font(.system(size: 13))
                            .frame(width: 200)
                    }
                    Divider().opacity(0.4)
                    row("Account") {
                        Picker("", selection: Binding(
                            get: { binding.wrappedValue.integrationId ?? "" },
                            set: { id in
                                var next = binding.wrappedValue
                                next.integrationId = id.isEmpty ? nil : id
                                binding.wrappedValue = next
                                Task { await env.refresh() }
                            }
                        )) {
                            Text("None").tag("")
                            ForEach(entry.connections) { connection in
                                Text(connection.label).tag(connection.id)
                            }
                        }
                        .labelsHidden()
                        // Not `.fixedSize()` like the other pickers in this
                        // file. Their options are words written here; these
                        // are whatever the provider calls the account, and
                        // "Google Search Console — prequel.sh" sized the popup
                        // wider than the pane — which pushed the row's own
                        // label down to one letter a line. 200 to line up with
                        // the Name field above it.
                        .frame(width: 200)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }
                    Divider().opacity(0.4)
                    HStack {
                        // Right, with the pickers. Every other control here is
                        // on the trailing edge, and a button alone on the left
                        // reads as belonging to a different group.
                        Spacer(minLength: 0)
                        ConnectButton(app: entry, model: model) { newId in
                            var next = binding.wrappedValue
                            next.integrationId = newId
                            binding.wrappedValue = next
                            Task { await env.refresh() }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            } else {
                // Before the catalogue has loaded there is nothing to connect
                // to yet, so there is nothing useful to offer either.
                note("Loading accounts…")
            }
        }
    }

    @ViewBuilder
    private func appearanceSection(_ binding: Binding<NotchWidget>) -> some View {
        section("Appearance") {
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
            if usesChart {
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
                }
            }
        }
    }

    @ViewBuilder
    private func dataSection(_ binding: Binding<NotchWidget>) -> some View {
        section("Data") {
            if usesTimeWindow {
                row("Range") {
                    Picker("", selection: Binding(
                        get: { binding.wrappedValue.range },
                        set: { range in
                            var next = binding.wrappedValue
                            next.range = range
                            binding.wrappedValue = next
                            Task { await env.refresh() }
                        }
                    )) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if descriptor != nil { Divider().opacity(0.4) }
            }
            if let descriptor {
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
            // Never compressed. These labels are one short word, so a control
            // too wide for the row should overflow or truncate on its own
            // side rather than wrap this to a column of single letters.
            Text(label)
                .font(.system(size: 13))
                .fixedSize(horizontal: true, vertical: false)
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
}
