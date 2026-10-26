import AppKit
import MetricsAPI
import MetricsCore
import NotchUI
import PluginRuntime
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

    /// Whether this widget is answered by a custom app on this machine.
    ///
    /// Read off the widget's own kind rather than from the catalogue: the
    /// catalogue loads asynchronously, and a pane that showed a connection
    /// row until the entry arrived would flash a Connect button for something
    /// that can never be connected.
    private var isCustom: Bool { draft?.kind == .customMetric }

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
    private var usesChart: Bool {
        descriptor?.supportsSeries != false || offersGauge || offersDistribution
    }

    /// Whether a gauge means anything for this metric.
    ///
    /// Only where the value has a ceiling to be a share *of*, which today
    /// means a ratio — 1.0 by definition. Offering it on a count would let
    /// somebody pick an arc that can never fill, and the picker is the only
    /// place that can stop them.
    private var offersGauge: Bool { descriptor?.unit == .ratio && descriptor?.isList != true }

    /// Whether the distributions mean anything for this metric.
    ///
    /// They draw a list's categories against each other, so they need a list.
    /// Offered on a series metric they would have nothing to slice.
    private var offersDistribution: Bool { descriptor?.isList == true }

    /// The ranges this metric can actually answer for.
    ///
    /// A range is a granularity in disguise: the widget sends only a range
    /// and the server derives the bucket from it, so a metric that cannot
    /// bucket by month cannot serve "12m". Every manifest has declared
    /// `granularities` since the first connector and nothing has ever read
    /// them — the picker offered all five regardless, and the two the AI
    /// connectors cannot serve came back as errors on the tile: "12m" on any
    /// of them, and "24h" on spend, which both report once a day.
    ///
    /// The widget's own range is still offered when unsupported, so the
    /// picker has a row matching its selection and does not render blank in
    /// the moment before `clampRange` moves it.
    private func offeredRanges(_ widget: NotchWidget) -> [TimeRange] {
        guard let descriptor else { return TimeRange.allCases }
        let offered = TimeRange.allCases.filter {
            descriptor.granularities.contains($0.defaultGranularity)
        }
        if offered.isEmpty { return TimeRange.allCases }
        return offered.contains(widget.range) ? offered : offered + [widget.range]
    }

    /// Moves a widget off a range its metric cannot serve.
    ///
    /// Only ever runs on a widget that is already broken: its tile answers
    /// every refresh with an error for a combination the picker should never
    /// have offered. That is a bad state rather than a preference, so it is
    /// corrected rather than preserved — and visibly, in the picker the user
    /// is looking at.
    ///
    /// The nearest supported range is the longest one no longer than what
    /// they had, so "12m" lands on "90d" rather than on "24h".
    private func clampRange() {
        guard var widget = draft, let descriptor else { return }
        guard !descriptor.granularities.contains(widget.range.defaultGranularity) else { return }
        let supported = TimeRange.allCases.filter {
            descriptor.granularities.contains($0.defaultGranularity)
        }
        guard !supported.isEmpty else { return }

        let current = TimeRange.allCases.firstIndex(of: widget.range) ?? 0
        widget.range =
            supported.last { (TimeRange.allCases.firstIndex(of: $0) ?? 0) <= current }
            ?? supported[0]
        draft = widget
        env.layoutModel.update(widget)
        env.widgetConfigurationChanged(widgetId)
    }

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

    /// One entry of the widget's `params`, as a text field's binding.
    ///
    /// Blank clears the key rather than storing an empty string, so "unset"
    /// has one representation and the server's "pick a repository" fires on
    /// it rather than on a request for a repository named "".
    private func paramField(_ binding: Binding<NotchWidget>, _ key: String) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue.params[key] ?? "" },
            set: { typed in
                var next = binding.wrappedValue
                let trimmed = typed.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    next.params.removeValue(forKey: key)
                } else {
                    next.params[key] = trimmed
                }
                binding.wrappedValue = next
                env.widgetConfigurationChanged(widgetId)
            })
    }

    /// The widget's own link, as a text field's binding.
    ///
    /// Blank clears it rather than storing an empty string, so "unset" has one
    /// representation and the catalogue's own link is what fills the gap —
    /// the same rule the metric's parameters follow.
    private func linkField(_ binding: Binding<NotchWidget>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue.link ?? "" },
            set: { typed in
                var next = binding.wrappedValue
                let trimmed = typed.trimmingCharacters(in: .whitespaces)
                next.link = trimmed.isEmpty ? nil : trimmed
                binding.wrappedValue = next
                env.widgetConfigurationChanged(widgetId)
            })
    }

    private var noLinkPlaceholder: String { "Nothing to open" }

    /// What the tile opens with no link of its own, shown as the placeholder
    /// so the field says what leaving it empty means.
    private var defaultLinkPlaceholder: String {
        guard let draft,
            let url = WidgetLink.resolve(
                NotchWidget(
                    id: draft.id, kind: draft.kind, appId: draft.appId, metric: draft.metric,
                    customMetricId: draft.customMetricId, params: draft.params, link: nil),
                in: env.notch.widgetLinks)
        else { return noLinkPlaceholder }
        return url.absoluteString
    }

    private var descriptor: MetricDescriptor? {
        guard let draft else { return nil }
        // A custom widget names its metric in `customMetricId`, not `metric`.
        // Looking only at `metric` meant `descriptor` was always nil for one,
        // so `metricParams` was always empty and the Data section rendered no
        // parameters however many the app declared.
        if draft.kind == .customMetric, let id = draft.customMetricId {
            return model.localMetric(id)
        }
        guard let metric = draft.metric else { return nil }
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
        .task(id: env.catalogueRevision) {
            // The widget first, the catalogue second. They were the other way
            // round, so until the network came back the pane showed its
            // "no longer in the notch" state for a widget that was plainly
            // sitting in the preview beside it.
            //
            // Keyed on the revision so the Account picker fills in the moment
            // a sign-in or a connect flow lands, rather than offering nothing
            // to pick for a provider that is now connected. Re-reading the
            // draft is safe: every edit is written straight through to the
            // layout, so there is nothing buffered here to lose.
            draft = env.layoutModel.layout.widgets.first { $0.id == widgetId }
            await model.load(env: env)
            // After the catalogue, because there is no descriptor to ask
            // before it lands and every range looks supported without one.
            clampRange()
        }
    }

    private func form(_ widget: NotchWidget) -> some View {
        let binding = Binding<NotchWidget>(
            // The widget as it is *now*, not as it was when the pane opened.
            //
            // Every setter below reads this, changes one field and writes the
            // whole widget back, so reading a snapshot meant each edit also
            // restored every field that had changed elsewhere since — and
            // `size` is the one that shows. Resize a tile with the pane open,
            // then touch any picker, and the tile sprang back to the size it
            // had when the pane was opened.
            get: { env.layoutModel.layout.widgets.first { $0.id == widgetId } ?? draft ?? widget },
            set: { next in
                draft = next
                // Written straight through rather than on a Done button: the
                // tile is visible in the notch behind this window, so every
                // change is already being previewed in the place that counts.
                env.layoutModel.update(next)
            })
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // The name is a property of the widget, so it is asked for
                // unconditionally — above the connection rather than inside
                // it. It used to live in the connection section's "has an
                // account" branch, which meant a widget with no connection
                // yet, and every custom widget, got a Connect button and no
                // way to name the tile at all.
                nameSection(binding)

                // A custom app has nothing to connect *to*: no integration row
                // on the server for an account picker, and no redirect URI for
                // the browser flow — which is why pointing it at one produced
                // "Could not start that connection". Its credentials are asked
                // for once per app in Settings, not once per tile.
                if !isCustom { connectionSection(binding) }
                appearanceSection(binding)
                dataSection(binding)
                // Not while the widget is being added: Cancel in the header
                // already takes it back out, and two ways to undo one
                // addition — one of them labelled as a destructive removal —
                // only makes the pane read as riskier than it is.
                if !env.notch.configuringIsNew { removeButton }
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

    /// The widget's own name, always.
    ///
    /// Shown whether or not an account is attached and whether or not the
    /// catalogue has loaded: naming a tile needs nothing from the server, and
    /// a field that appears only once a connection exists is a field nobody
    /// finds.
    private func nameSection(_ binding: Binding<NotchWidget>) -> some View {
        section("Widget") {
            row("Name") {
                // Names this tile only. A served connection keeps its own
                // name and the other tiles reading it keep showing that.
                TextField(placeholderName, text: nameField(binding))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 13))
                    .frame(width: 200)
            }

            if needsCredentials {
                Divider().opacity(0.4)
                row("Credentials") {
                    Button("Open Settings") {
                        env.openSettings(pane: .customApps)
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    /// What the empty field suggests it will be called.
    ///
    /// `nameField` already falls back to the connection's label when the user
    /// has typed nothing, so the placeholder has to say what *will* be used
    /// rather than sit blank — otherwise an unnamed tile looks unnamed while
    /// the notch shows a name.
    private var placeholderName: String {
        draft?.title ?? entry?.name ?? "Name"
    }

    /// Whether this app is waiting on a credential the user has not given.
    ///
    /// Shown as a pointer rather than a second form: one key answers every
    /// metric behind an app, so asking per tile would ask the same question
    /// five times and let five answers disagree.
    private var needsCredentials: Bool {
        guard let draft, draft.kind == .customMetric else { return false }
        let ref = CustomMetricRef(packed: draft.customMetricId ?? "")
        guard let appId = ref.appId,
            let app = env.connectors.connectors.first(where: { $0.id == appId }),
            let manifest = app.manifest, manifest.requiresCredentials
        else { return false }
        return manifest.auth.contains { field in
            field.required && env.connectorCredential(appId, field.key).isEmpty
        }
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
                            env.widgetConfigurationChanged(widgetId)
                        }
                    }
                } else {
                    row("Account") {
                        Picker("", selection: Binding(
                            get: { binding.wrappedValue.integrationId ?? "" },
                            set: { id in
                                var next = binding.wrappedValue
                                next.integrationId = id.isEmpty ? nil : id
                                binding.wrappedValue = next
                                env.widgetConfigurationChanged(widgetId)
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
                        //
                        // Trailing, because a pop-up button does not fill the
                        // width it is given: it hugs its title and centres
                        // inside the slot, which left a gap of half the spare
                        // width to the right of it and put its edge somewhere
                        // different from every text field in the pane.
                        .frame(width: 200, alignment: .trailing)
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
                            env.widgetConfigurationChanged(widgetId)
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
                        // "None" means the plain rendering: a figure, or for
                        // a list the text rows it has always drawn.
                        Text(offersDistribution ? "Rows" : "None").tag(ChartKind.none)
                        if offersGauge { Text("Gauge").tag(ChartKind.gauge) }
                        if offersDistribution {
                            Text("Ranked").tag(ChartKind.ranked)
                            Text("Split").tag(ChartKind.split)
                            Text("Donut").tag(ChartKind.pie)
                        }
                        if descriptor?.supportsSeries != false, !offersDistribution {
                            Text("Sparkline").tag(ChartKind.sparkline)
                            Text("Bars").tag(ChartKind.bars)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    /// What this metric asks the widget for — GitHub's repository, say.
    ///
    /// Read from the server's catalogue rather than hard-coded, so a
    /// connector that grows a parameter needs no Mac release.
    private var metricParams: [AuthField] {
        descriptor?.params ?? []
    }

    @ViewBuilder
    private func dataSection(_ binding: Binding<NotchWidget>) -> some View {
        section("Data") {
            ForEach(metricParams, id: \.key) { field in
                row(field.label) {
                    TextField(field.placeholder ?? "", text: paramField(binding, field.key))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 13))
                        .autocorrectionDisabled()
                        .frame(width: 200)
                }
                if let help = field.help {
                    // Under the field rather than beside it: "owner/name" is
                    // the whole instruction, and a row this narrow has no
                    // room for it on the same line.
                    HStack {
                        Spacer(minLength: 0)
                        Text(help)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                Divider().opacity(0.4)
            }
            // Where the tile goes when it is clicked. Last in Data because it
            // is the one field here that changes nothing about the number.
            row("Opens") {
                TextField(defaultLinkPlaceholder, text: linkField(binding))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 13))
                    .autocorrectionDisabled()
                    .frame(width: 200)
            }
            HStack {
                Spacer(minLength: 0)
                Text(
                    defaultLinkPlaceholder == noLinkPlaceholder
                        ? "This app has no page to open."
                        : "Leave empty to open the app's own page.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            Divider().opacity(0.4)
            if usesTimeWindow {
                row("Range") {
                    Picker("", selection: Binding(
                        get: { binding.wrappedValue.range },
                        set: { range in
                            var next = binding.wrappedValue
                            next.range = range
                            binding.wrappedValue = next
                            env.widgetConfigurationChanged(widgetId)
                        }
                    )) {
                        ForEach(offeredRanges(binding.wrappedValue), id: \.self) { range in
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
