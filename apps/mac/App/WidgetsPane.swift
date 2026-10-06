import AppKit
import MetricsAPI
import MetricsCore
import NotchUI
import SwiftUI

/// Browse by app → pick a widget → point it at a connection → add it.
///
/// The old pane listed what was already in the notch, which answered the one
/// question nobody had. Adding a widget meant knowing the metric existed and
/// which account it should read from, and nothing on screen said either.
struct WidgetsPane: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model = WidgetCatalogueModel()
    @State private var query = ""

    var body: some View {
        NavigationStack {
            root
                .navigationDestination(for: WidgetRoute.self) { route in
                    switch route {
                    case .app(let app):
                        AppDetailView(app: app, model: model)
                    case .widget(let app, let metric):
                        WidgetBuilderView(app: app, metric: metric, model: model)
                    }
                }
        }
        .task { await model.load(env: env) }
    }

    @ViewBuilder
    private var root: some View {
        VStack(spacing: 0) {
            SearchField(text: $query)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 4)

            Form {
                switch model.state {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                case .loaded(let apps):
                    let results = WidgetSearch.run(query, over: apps)
                    if results.isEmpty {
                        Section {
                            Text("Nothing matches “\(query)”.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(results) { result in
                            Section {
                                NavigationLink(value: WidgetRoute.app(result.app)) {
                                    AppRow(
                                        app: result.app,
                                        inNotch: model.widgetCount(for: result.app.id, env: env))
                                }
                                // Only the widgets that matched, so a search
                                // for "churn" does not reopen the whole app.
                                ForEach(result.metrics) { metric in
                                    NavigationLink(
                                        value: WidgetRoute.widget(result.app, metric)
                                    ) {
                                        MetricRow(metric: metric)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("Widgets")
    }
}

/// Pushed views, as values so `NavigationStack` owns the history.
enum WidgetRoute: Hashable {
    case app(ConnectorEntry)
    case widget(ConnectorEntry, MetricDescriptor)
}

private struct AppRow: View {
    let app: ConnectorEntry
    let inNotch: Int

    var body: some View {
        HStack(spacing: 11) {
            ConnectorIcon(app: AppCatalog.resolve(app.id), size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 1)
    }

    private var subtitle: String {
        let widgets = "\(app.metrics.count) widget" + (app.metrics.count == 1 ? "" : "s")
        if inNotch > 0 { return "\(widgets) · \(inNotch) in the notch" }
        if app.connections.isEmpty { return "\(widgets) · not connected" }
        let count = app.connections.count
        return "\(widgets) · \(count) connection" + (count == 1 ? "" : "s")
    }
}

// MARK: - One app

private struct AppDetailView: View {
    let app: ConnectorEntry
    @Bindable var model: WidgetCatalogueModel
    @Environment(AppEnvironment.self) private var env

    enum Tab: String, CaseIterable { case widgets, connections }

    @State private var tab: Tab = .widgets
    @State private var renaming: ConnectorConnection?
    @State private var draftName = ""
    @State private var confirmingRemoval: ConnectorConnection?
    @State private var problem: String?

    var body: some View {
        Group {
            switch tab {
            case .widgets: widgets
            case .connections: connections
            }
        }
        .navigationTitle(app.name)
        .toolbar {
            // In the header rather than a segmented control floating above the
            // content: the window already has a title bar doing nothing, and a
            // second horizontal band under it wastes the height a 2x2 preview
            // needs.
            ToolbarItem(placement: .primaryAction) {
                Picker("", selection: $tab) {
                    Text("Widgets").tag(Tab.widgets)
                    Text("Connections").tag(Tab.connections)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
        .sheet(item: $renaming) { connection in
            RenameSheet(
                name: $draftName,
                onCancel: { renaming = nil },
                onSave: {
                    let newName = draftName
                    renaming = nil
                    Task { await rename(connection, to: newName) }
                })
        }
        .alert(
            "Disconnect \(confirmingRemoval?.label ?? "")?",
            isPresented: Binding(
                get: { confirmingRemoval != nil },
                set: { if !$0 { confirmingRemoval = nil } }),
            presenting: confirmingRemoval
        ) { connection in
            Button("Disconnect", role: .destructive) {
                confirmingRemoval = nil
                Task { await disconnect(connection) }
            }
            Button("Cancel", role: .cancel) { confirmingRemoval = nil }
        } message: { _ in
            Text(
                "Its stored credentials are deleted. Widgets using it stay where they are and "
                    + "show a reconnect prompt.")
        }
    }

    private func rename(_ connection: ConnectorConnection, to label: String) async {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await env.api.rename(connection: connection.id, to: trimmed)
            await model.load(env: env)
        } catch {
            problem = "Could not rename that connection."
        }
    }

    private func disconnect(_ connection: ConnectorConnection) async {
        do {
            _ = try await env.api.disconnect(connection.id)
            await model.load(env: env)
        } catch {
            problem = "Could not disconnect that account."
        }
    }

    /// Current, because connecting an account on the other tab has to change
    /// what this one shows without leaving and coming back.
    private var live: ConnectorEntry { model.entry(app.id) ?? app }

    private var widgets: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 170), spacing: 12)],
                spacing: 12
            ) {
                ForEach(live.metrics) { metric in
                    NavigationLink(value: WidgetRoute.widget(live, metric)) {
                        MetricCard(metric: metric, app: AppCatalog.resolve(live.id))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private var connections: some View {
        Form {
            Section {
                if live.connections.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No \(live.name) account connected").font(.headline)
                        Text("Connect one and these widgets can start showing real numbers.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(live.connections) { connection in
                        HStack(spacing: 10) {
                            ConnectorIcon(app: AppCatalog.resolve(live.id), size: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(connection.label)
                                if connection.needsAttention {
                                    Text("Stopped working — reconnect it")
                                        .font(.callout)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer(minLength: 8)
                            // Managed here as well as in the Connections pane:
                            // somebody looking at an account in the context of
                            // the app it belongs to should not have to go
                            // somewhere else to rename or remove it.
                            Menu {
                                Button("Rename…") {
                                    draftName = connection.label
                                    renaming = connection
                                }
                                Divider()
                                Button("Disconnect", role: .destructive) {
                                    confirmingRemoval = connection
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                    }
                }

                ConnectButton(app: live, model: model)

                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Connections")
            } footer: {
                Text("Manage and remove connections under Connections in the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct MetricCard: View {
    let metric: MetricDescriptor
    let app: MetricApp

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ConnectorIcon(app: app, size: 22)
                Text(metric.shortLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(metric.label)
                .font(.headline)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Text(metric.methodology)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .contentShape(Rectangle())
    }
}

// MARK: - Building one widget

private struct WidgetBuilderView: View {
    let app: ConnectorEntry
    let metric: MetricDescriptor
    @Bindable var model: WidgetCatalogueModel

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var connectionId: String?
    @State private var size: WidgetSize = .wide
    @State private var compact = true
    @State private var preview: TileState = .loading
    @State private var added = false

    private var live: ConnectorEntry { model.entry(app.id) ?? app }
    private var metricApp: MetricApp { AppCatalog.resolve(app.id) }

    private var selected: ConnectorConnection? {
        live.connections.first { $0.id == connectionId } ?? live.connections.first
    }

    var body: some View {
        Form {
            Section("Preview") {
                HStack {
                    Spacer()
                    WidgetTile(widget: draft, app: metricApp, state: preview)
                        .frame(width: previewSize.width, height: previewSize.height)
                        .padding(.vertical, 10)
                    Spacer()
                }
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))

                Picker("Size", selection: $size) {
                    ForEach(WidgetSize.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                // The adapter knows it fetched money; only the tile knows
                // whether 1,243,901 fits. Shown as the rendered result rather
                // than as "compact", because the choice is between two things
                // you can see.
                Picker("Numbers", selection: $compact) {
                    Text("Short — 1.2M").tag(true)
                    Text("Full — 1,243,901").tag(false)
                }
                .pickerStyle(.inline)
            }

            Section("Connection") {
                if live.connections.isEmpty {
                    Text("Connect a \(live.name) account to see real numbers here.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Account", selection: Binding(
                        get: { selected?.id ?? "" },
                        set: { connectionId = $0 }
                    )) {
                        ForEach(live.connections) { connection in
                            Text(connection.label).tag(connection.id)
                        }
                    }
                }

                ConnectButton(app: live, model: model) { newConnectionId in
                    // Select whatever was just connected, so the flow carries
                    // straight on into a live preview instead of dropping the
                    // user back onto an unchanged screen.
                    connectionId = newConnectionId
                }
            }

            Section {
                Text(metric.methodology)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    add()
                } label: {
                    Text(added ? "Added to the notch" : "Add to notch")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(added)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(metric.label)
        .task(id: selected?.id) { await refreshPreview() }
        .onChange(of: size) { _, _ in Task { await refreshPreview() } }
    }

    /// Roughly the notch's own cell size, so the preview is the tile people
    /// will actually get rather than a stretched approximation of it.
    private var previewSize: CGSize {
        let unit: CGFloat = 58
        let gap: CGFloat = 8
        let cols = CGFloat(size.cols)
        let rows = CGFloat(size.rows)
        let width: CGFloat = cols * unit + (cols - 1) * gap
        let height: CGFloat = rows * unit + (rows - 1) * gap
        return CGSize(width: width, height: height)
    }

    private var draft: NotchWidget {
        NotchWidget(
            id: "preview-\(app.id)-\(metric.id)",
            kind: .providerMetric,
            appId: app.id,
            integrationId: selected?.id,
            metric: metric.id,
            title: metric.shortLabel,
            size: size,
            col: 0,
            row: 0,
            position: 0,
            granularity: metric.granularities.first ?? .day,
            range: .month,
            chart: metric.supportsSeries ? .sparkline : .none,
            format: WidgetFormat(compact: compact))
    }

    private func refreshPreview() async {
        guard let connection = selected else {
            preview = .needsSetup("Pick a connection")
            return
        }
        preview = .loading
        do {
            let result = try await env.api.metric(
                integrationId: connection.id,
                metric: metric.id,
                granularity: (metric.granularities.first ?? .day).rawValue,
                range: TimeRange.month.rawValue)
            switch result {
            case .success(let series): preview = .value(series)
            case .failure(let failure): preview = .failed(reason: failure.message)
            }
        } catch {
            preview = .failed(reason: "Could not load a preview")
        }
    }

    private func add() {
        var widget = draft
        widget.id = "w_\(UUID().uuidString.prefix(8))"
        guard env.layoutModel.add(widget) else {
            preview = .failed(reason: "No room in the notch — make it taller or use list view")
            return
        }
        added = true
        // Otherwise the new tile sits on "Loading" until the five-minute
        // timer comes round.
        Task { await env.refresh() }
    }
}

// MARK: - Connecting, without leaving

/// Opens the browser flow and waits for the account to appear.
///
/// The same button in both tabs: somebody who gets as far as picking a widget
/// and finds nothing to point it at should not have to go and find the Apps
/// pane.
private struct ConnectButton: View {
    let app: ConnectorEntry
    @Bindable var model: WidgetCatalogueModel
    var onConnected: ((String) -> Void)?

    @Environment(AppEnvironment.self) private var env
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if app.isConnectable {
                Button {
                    connect()
                } label: {
                    if busy {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for the browser…")
                        }
                    } else {
                        Label(
                            app.connections.isEmpty ? "Connect \(app.name)" : "Add another account",
                            systemImage: "plus")
                    }
                }
                .disabled(busy)
            } else {
                Text("\(app.name) is not ready to connect yet.")
                    .foregroundStyle(.secondary)
            }

            if let problem {
                Text(problem).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func connect() {
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do {
                let before = Set(model.entry(app.id)?.connections.map(\.id) ?? [])
                let link = try await env.api.connectLink(for: app.id)
                NSWorkspace.shared.open(link.url)
                if let added = await model.waitForNewConnection(to: app.id, notIn: before, env: env)
                {
                    onConnected?(added)
                } else {
                    problem = "No new account appeared. You can close the browser tab."
                }
            } catch {
                problem = "Could not start that connection."
            }
        }
    }
}

// MARK: - Model

@MainActor
@Observable
final class WidgetCatalogueModel {
    enum State {
        case loading
        case loaded([ConnectorEntry])
        case failed(String)
    }

    private(set) var state: State = .loading

    private var apps: [ConnectorEntry] {
        if case .loaded(let apps) = state { return apps }
        return []
    }

    func entry(_ id: String) -> ConnectorEntry? { apps.first { $0.id == id } }

    func widgetCount(for appId: String, env: AppEnvironment) -> Int {
        env.layoutModel.layout.widgets.count { $0.appId == appId }
    }

    func load(env: AppEnvironment) async {
        do {
            let catalogue = try await env.api.catalogue()
            // Only apps that actually offer a widget. A row you can open to
            // find an empty grid is a dead end.
            state = .loaded(
                catalogue.categories.flatMap(\.connectors).filter { !$0.metrics.isEmpty })
        } catch {
            state = .failed("Could not load the app catalogue.")
        }
    }

    /// Polls until the browser flow adds an account, or gives up.
    ///
    /// Returns the new connection's id so the caller can select it. Polling
    /// rather than waiting on the `notchmetrics://connected` callback,
    /// because the user may finish in a browser that never hands focus back.
    func waitForNewConnection(
        to appId: String, notIn existing: Set<String>, env: AppEnvironment
    ) async -> String? {
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return nil }
            await load(env: env)
            if let added = entry(appId)?.connections.first(where: { !existing.contains($0.id) }) {
                return added.id
            }
        }
        return nil
    }
}

/// A plain search field, sized to lead the pane.
private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search apps and widgets", text: $text)
                .textFieldStyle(.plain)
                .font(.title3)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
}

private struct MetricRow: View {
    let metric: MetricDescriptor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.on.square")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(metric.label)
                Text(metric.methodology)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}
