import MetricsAPI
import MetricsCore
import NotchUI
import SwiftUI

/// The accounts this user has actually connected.
///
/// Separate from Apps on purpose. Apps answers "what can I connect?" and is
/// the same seventeen rows for everybody; this answers "what *is* connected,
/// and is it still working?" — which is the question somebody has when a
/// widget has gone blank.
struct ConnectionsPane: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model = ConnectionsModel()
    @State private var renaming: Integration?
    @State private var draftName = ""
    @State private var confirmingRemoval: Integration?

    var body: some View {
        Form {
            Section {
                switch model.state {
                case .loading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading…").foregroundStyle(.secondary)
                    }

                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)

                case .loaded(let connections) where connections.isEmpty:
                    // An empty list with no route out of it is a dead end.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nothing connected yet").font(.headline)
                        Text("Connect an account and its numbers become available to every widget.")
                            .foregroundStyle(.secondary)
                        Button("Browse apps") { env.settingsPane = .apps }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 6)

                case .loaded(let connections):
                    ForEach(connections) { connection in
                        ConnectionRow(
                            connection: connection,
                            app: AppCatalog.resolve(connection.provider),
                            onRename: {
                                draftName = connection.label
                                renaming = connection
                            },
                            onRemove: { confirmingRemoval = connection }
                        )
                    }
                }
            } header: {
                HStack {
                    Text("Connections")
                    Spacer()
                    Button {
                        env.settingsPane = .apps
                    } label: {
                        Label("Add connection", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .font(.body)
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.load(env: env) }
        .sheet(item: $renaming) { connection in
            RenameSheet(
                name: $draftName,
                connection: connection,
                onCancel: { renaming = nil },
                onSave: {
                    let newName = draftName
                    renaming = nil
                    Task { await model.rename(connection, to: newName, env: env) }
                }
            )
        }
        .alert(
            "Disconnect \(confirmingRemoval?.label ?? "")?",
            isPresented: Binding(
                get: { confirmingRemoval != nil },
                set: { if !$0 { confirmingRemoval = nil } }
            ),
            presenting: confirmingRemoval
        ) { connection in
            Button("Disconnect", role: .destructive) {
                confirmingRemoval = nil
                Task { await model.remove(connection, env: env) }
            }
            Button("Cancel", role: .cancel) { confirmingRemoval = nil }
        } message: { _ in
            // Says what survives, because "will this delete my widgets?" is
            // the actual question and the answer is no.
            Text(
                "Its stored credentials are deleted. Widgets using it stay where they are and "
                    + "show a reconnect prompt."
            )
        }
    }
}

private struct ConnectionRow: View {
    let connection: Integration
    let app: MetricApp
    let onRename: () -> Void
    let onRemove: () -> Void

    private var isBroken: Bool { connection.status == "auth_failed" }

    var body: some View {
        HStack(spacing: 11) {
            ConnectorIcon(app: app, size: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(connection.label)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(isBroken ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Menu {
                Button("Rename…", action: onRename)
                Divider()
                Button("Disconnect", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 2)
    }

    private var detail: String {
        if isBroken { return "Stopped working — reconnect to start it again" }
        guard let synced = connection.lastSyncedAt.flatMap(Self.relative) else {
            return "\(connection.credentialHint) · not synced yet"
        }
        return "\(connection.credentialHint) · synced \(synced)"
    }

    private static func relative(_ iso: String) -> String? {
        guard let date = try? Date(iso, strategy: .iso8601) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct RenameSheet: View {
    @Binding var name: String
    let connection: Integration
    let onCancel: () -> Void
    let onSave: () -> Void

    private var isEmpty: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        // The sheet is sized here rather than by its contents. Left to grow,
        // it takes its width from the title and the button row, and a
        // fixed-width field then sits short of the trailing edge — which is
        // the gap, not padding.
        VStack(alignment: .leading, spacing: 10) {
            Text("Rename connection").font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                // Return saves. A one-field sheet that makes you reach for
                // the mouse is a one-field sheet nobody enjoys.
                .onSubmit { if !isEmpty { onSave() } }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isEmpty)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}

@MainActor
@Observable
final class ConnectionsModel {
    enum State {
        case loading
        case loaded([Integration])
        case failed(String)
    }

    private(set) var state: State = .loading

    func load(env: AppEnvironment) async {
        do {
            state = .loaded(try await env.api.connections())
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    func rename(_ connection: Integration, to label: String, env: AppEnvironment) async {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await env.api.rename(connection: connection.id, to: trimmed)
            await load(env: env)
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    func remove(_ connection: Integration, env: AppEnvironment) async {
        do {
            _ = try await env.api.disconnect(connection.id)
            await load(env: env)
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let apiError = error as? APIError else { return "Something went wrong." }
        switch apiError {
        case .unauthorized: return "Sign in to manage your connections."
        default: return "Could not reach Notch Metrics."
        }
    }
}
