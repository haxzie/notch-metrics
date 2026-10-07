import AppKit
import MetricsAPI
import MetricsCore
import NotchUI
import SwiftUI

// The Widgets settings pane used to live here: browse by app, pick a widget,
// point it at a connection, add it. The gallery replaced all of it — widgets
// are dragged into the notch now, and configured in a window of their own —
// so only the two pieces with callers left are kept.

// MARK: - Connecting, without leaving

/// Opens the browser flow and waits for the account to appear.
///
/// The same button in both tabs: somebody who gets as far as picking a widget
/// and finds nothing to point it at should not have to go and find the Apps
/// pane.
struct ConnectButton: View {
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
    /// Kept grouped as well as flat: the gallery's sidebar lists connectors
    /// under the server's own category labels, and flattening them here would
    /// mean inventing those labels again on the other side.
    private(set) var categoryGroups: [ConnectorCategoryGroup] = []

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
            let groups = catalogue.categories.compactMap { group -> ConnectorCategoryGroup? in
                let connectors = group.connectors.filter { !$0.metrics.isEmpty }
                guard !connectors.isEmpty else { return nil }
                return ConnectorCategoryGroup(
                    id: group.id, label: group.label, connectors: connectors)
            }
            categoryGroups = groups
            state = .loaded(groups.flatMap(\.connectors))
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
