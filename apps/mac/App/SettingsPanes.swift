import MetricsCore
import NotchUI
import PluginRuntime
import SwiftUI

struct GeneralPane: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Launch at login",
                    isOn: binding(\.launchAtLogin) { $0.launchAtLogin = $1 })
                Toggle(
                    "Show a menu bar icon",
                    isOn: binding(\.showMenuBarIcon) { $0.showMenuBarIcon = $1 })
                Toggle(
                    "Show over full-screen apps",
                    isOn: binding(\.showInFullscreen) { $0.showInFullscreen = $1 })
            } header: {
                Text("Behaviour")
            } footer: {
                Text("On a Mac with a notch, that area is black in full screen anyway.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hover") {
                LabeledContent("Open after") {
                    Stepper(
                        "\(env.settings.hoverDwellMilliseconds) ms",
                        value: binding(\.hoverDwellMilliseconds) { $0.hoverDwellMilliseconds = $1 },
                        in: 0...600, step: 20)
                }
                LabeledContent("Close after") {
                    Stepper(
                        "\(env.settings.collapseDelayMilliseconds) ms",
                        value: binding(\.collapseDelayMilliseconds) {
                            $0.collapseDelayMilliseconds = $1
                        },
                        in: 100...2000, step: 50)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func binding<T: Sendable>(
        _ get: @escaping (AppSettings) -> T,
        set: @escaping @Sendable (inout AppSettings, T) -> Void
    ) -> Binding<T> {
        Binding(
            get: { get(env.settings) },
            set: { value in env.updateSettings { settings in set(&settings, value) } })
    }
}

struct WidgetsPane: View {
    @Environment(AppEnvironment.self) private var env

    private var layout: NotchLayout { env.layoutModel.layout }

    var body: some View {
        Form {
            Section("Layout") {
                Picker(
                    "Show as",
                    selection: Binding(
                        get: { layout.display },
                        set: { env.layoutModel.setDisplay($0) })
                ) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Height") {
                    Stepper(
                        "\(layout.rows) row\(layout.rows == 1 ? "" : "s")",
                        value: Binding(
                            get: { layout.rows },
                            set: { env.layoutModel.setRows($0) }),
                        in: NotchLayout.minRows...NotchLayout.maxRows)
                }
            }

            // Grouped by app, because that is how the list view reads and how
            // somebody with four integrations thinks about their numbers.
            ForEach(layout.groupedByApp(), id: \.app.id) { group in
                Section {
                    ForEach(group.widgets) { widget in
                        LabeledContent {
                            Text(layout.display == .grid ? widget.size.rawValue : "—")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(widget.title ?? widget.metric ?? widget.customMetricId ?? "Widget")
                        }
                    }
                } header: {
                    Label(group.app.name, systemImage: group.app.symbol)
                }
            }

            if hidden > 0 {
                Section {
                    Label(
                        "\(hidden) widget\(hidden == 1 ? " does" : "s do") not fit the grid. "
                            + "Switch to the list view, or make the notch taller.",
                        systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Hover the notch and click the pencil to rearrange or resize.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var hidden: Int {
        layout.display == .grid ? layout.widgets.count(where: { !$0.visible }) : 0
    }
}

struct CustomMetricsPane: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Form {
            Section {
                if env.plugins.plugins.isEmpty {
                    ContentUnavailableView {
                        Label("No custom metrics", systemImage: "curlybraces")
                    } description: {
                        Text(
                            "Ask Claude Code — or any MCP client — to write one:\n\nclaude mcp add notch-metrics -- npx -y notch-metrics-mcp"
                        )
                        .font(.callout)
                    }
                    .padding(.vertical, 16)
                } else {
                    ForEach(env.plugins.plugins) { plugin in
                        PluginRow(plugin: plugin)
                    }
                }
            } header: {
                Text("Metrics on this Mac")
            } footer: {
                Text(
                    "Custom metrics run on your machine with your own API keys. A new one does not run until you enable it here."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Folder") {
                    Button(AppPaths.metrics.lastPathComponent) {
                        NSWorkspace.shared.open(AppPaths.metrics)
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PluginRow: View {
    @Environment(AppEnvironment.self) private var env
    let plugin: LoadedPlugin

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(plugin.displayName).font(.body)
                    if let manifest = plugin.manifest {
                        Text(manifest.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                switch plugin.state {
                case .ready, .pendingApproval:
                    Toggle("Enabled", isOn: enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                case .invalid:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            if case .invalid(let reason) = plugin.state {
                // The reason, in full, rather than a generic "could not load".
                // This text is what the user pastes back into their agent to
                // get the metric fixed, which closes the loop.
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let manifest = plugin.manifest, !manifest.allowedHosts.isEmpty {
                Text("Reaches: \(manifest.allowedHosts.joined(separator: ", "))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { plugin.state == .ready },
            set: { isOn in
                let id = plugin.id
                env.updateSettings { settings in
                    if isOn {
                        settings.approvedPluginIDs.insert(id)
                    } else {
                        settings.approvedPluginIDs.remove(id)
                    }
                }
            })
    }
}

struct AccountPane: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Form {
            Section("Account") {
                if env.isSignedIn {
                    LabeledContent("Status", value: "Signed in")
                    Button("Open billing") {
                        NSWorkspace.shared.open(
                            AppEnvironment.appURL.appendingPathComponent("app/settings/billing"))
                    }
                } else {
                    LabeledContent("Status", value: "Signed out")
                    Button("Sign in…") {
                        NSWorkspace.shared.open(
                            AppEnvironment.appURL.appendingPathComponent("desktop/auth"))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct UpdatesPane: View {
    @Environment(AppEnvironment.self) private var env

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section("Version") {
                LabeledContent("Installed", value: "\(version) (\(build))")
                Toggle(
                    "Check automatically",
                    isOn: Binding(
                        get: { env.settings.checkForUpdatesAutomatically },
                        set: { value in
                            env.updateSettings { $0.checkForUpdatesAutomatically = value }
                        }))
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutPane: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(NotchTheme.brand)

            Text("Notch Metrics").font(.title2.weight(.semibold))
            Text("Version \(version)").font(.callout).foregroundStyle(.secondary)

            Link("notchmetrics.com", destination: AppEnvironment.appURL)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
