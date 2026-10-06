import MetricsAPI
import MetricsCore
import NotchUI
import SwiftUI

/// Everything the app can connect to, grouped by category, with one button
/// per row.
///
/// Rendered entirely from `GET /v1/connectors` rather than from anything
/// compiled in — which is the property that lets a connector ship without a
/// Mac release.
struct AppsPane: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model = ConnectorsModel()

    var body: some View {
        Form {
            switch model.state {
            case .loading:
                Section { loading }

            case .failed(let reason):
                Section { failure(reason) }

            case .loaded(let catalogue):
                if let problem = model.lastError {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(catalogue.categories) { group in
                    Section(group.label) {
                        ForEach(group.connectors) { connector in
                            ConnectorRow(
                                connector: connector,
                                busy: model.connecting == connector.id,
                                onConnect: { model.connect(connector, env: env) }
                            )
                        }
                    }
                }

                Section {
                    Text(
                        "Connecting opens your browser. Keys are encrypted on our servers and "
                            + "never stored on this Mac."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.load(env: env) }
        .refreshable { await model.load(env: env) }
    }

    private var loading: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Loading integrations…").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }

    private func failure(_ reason: String) -> some View {
        ContentUnavailableView {
            Label("Could not load integrations", systemImage: "wifi.exclamationmark")
        } description: {
            Text(reason)
        } actions: {
            Button("Try again") { Task { await model.load(env: env) } }
        }
        .padding(.vertical, 12)
    }
}

/// One connector: mark, name, what it gives you, and a button.
private struct ConnectorRow: View {
    let connector: ConnectorEntry
    let busy: Bool
    let onConnect: () -> Void

    private var app: MetricApp {
        // The server's name and colour win over the built-in entry, so a
        // connector added after this build still renders correctly.
        AppCatalog.resolve(
            connector.id,
            overrides: [
                connector.id: MetricApp(
                    id: connector.id,
                    name: connector.name,
                    symbol: AppCatalog.resolve(connector.id).symbol,
                    accentHex: connector.accentColor.replacingOccurrences(of: "#", with: "")
                )
            ])
    }

    var body: some View {
        HStack(spacing: 12) {
            ConnectorIcon(app: app, size: 30, isEnabled: connector.isConnectable)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(connector.name)
                        .foregroundStyle(connector.isConnectable ? .primary : .secondary)
                    if connector.needsOAuthBadge {
                        Badge(text: "OAuth")
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)
            action
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        if let problem = connector.connections.first(where: \.needsAttention) {
            return "\(problem.label) — needs reconnecting"
        }
        if let first = connector.connections.first {
            return connector.connections.count > 1
                ? "\(connector.connections.count) accounts connected"
                : first.label
        }
        return connector.tagline
    }

    @ViewBuilder
    private var action: some View {
        if !connector.isConnectable {
            // Listed but not connectable. Showing it greyed out answers "is
            // this coming?" without anybody having to ask.
            Text("Soon")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
        } else if busy {
            ProgressView().controlSize(.small)
        } else if connector.isConnected {
            Button("Add another", action: onConnect)
                .buttonStyle(.bordered)
                .controlSize(.small)
        } else {
            Button("Connect", action: onConnect)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}

private struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(.quaternary))
            .foregroundStyle(.secondary)
    }
}

extension ConnectorEntry {
    /// Worth flagging: an OAuth connector sends you to the provider's own
    /// sign-in rather than asking for a key, and people want to know which
    /// before they click.
    var needsOAuthBadge: Bool { authMode == "oauth2" && isConnectable }
}

@MainActor
@Observable
final class ConnectorsModel {
    enum State {
        case loading
        case loaded(ConnectorCatalogue)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var connecting: String?
    /// A failed *connect* is reported beside the list, not instead of it.
    /// Replacing the catalogue with an error because one button failed loses
    /// the thing the user was looking at.
    private(set) var lastError: String?

    func load(env: AppEnvironment) async {
        do {
            state = .loaded(try await env.api.catalogue())
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    /// Mints a link and hands it to the browser.
    ///
    /// The app does not collect credentials itself. An OAuth flow needs a
    /// real address bar, and a native window asking for a Stripe key is
    /// indistinguishable from one a phishing app would show.
    func connect(_ connector: ConnectorEntry, env: AppEnvironment) {
        guard connecting == nil else { return }
        connecting = connector.id

        Task {
            defer { connecting = nil }
            do {
                lastError = nil
                let link = try await env.api.connectLink(for: connector.id)
                NSWorkspace.shared.open(link.url)
                // The browser finishes the flow and deep-links back to
                // `notchmetrics://connected`, which refreshes this list. The
                // poll below is the fallback for a browser that was closed,
                // or a redirect an extension ate.
                await pollUntilConnected(connector.id, env: env)
            } catch {
                lastError = Self.describe(error)
            }
        }
    }

    private func pollUntilConnected(_ connectorId: String, env: AppEnvironment) async {
        // Two minutes at two-second intervals. Past that the user has
        // abandoned it, and polling a dead flow forever is how a menu-bar app
        // ends up with a background task nobody remembers starting.
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            guard let status = try? await env.api.connectStatus(for: connectorId) else { continue }
            if status.isConnected {
                await load(env: env)
                return
            }
            if !status.isPending { return }
        }
    }

    private static func describe(_ error: any Error) -> String {
        guard let apiError = error as? APIError else { return error.localizedDescription }
        switch apiError {
        case .offline: return "You appear to be offline."
        case .unauthorized: return "Sign in to manage integrations."
        case .subscriptionRequired: return "Your trial has ended."
        case .rateLimited: return "Too many attempts just now — try again shortly."
        case .server(_, _, let message): return message ?? "The server could not be reached."
        case .transport(let detail): return detail
        case .decoding: return "The server sent something this version cannot read."
        }
    }
}
