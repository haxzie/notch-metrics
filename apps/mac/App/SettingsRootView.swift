import MetricsCore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general, connections, apps, widgets, customMetrics, account, updates, about

    /// `notchmetrics://settings/integrations` is in the wild — in the website,
    /// in the connect flow's return URL — and kept working when the pane was
    /// renamed to Apps.
    static let aliases: [String: SettingsPane] = ["integrations": .apps]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .connections: "Connections"
        case .apps: "Apps"
        case .widgets: "Widgets"
        case .customMetrics: "Custom Metrics"
        case .account: "Account"
        case .updates: "Updates"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .connections: "link"
        case .apps: "square.grid.2x2"
        case .widgets: "rectangle.grid.2x2"
        case .customMetrics: "curlybraces"
        case .account: "person.crop.circle"
        case .updates: "arrow.triangle.2.circlepath"
        case .about: "info.circle"
        }
    }

    /// Grouped the way System Settings groups things: what you set up, who you
    /// are, and the app itself.
    static let sections: [(String?, [SettingsPane])] = [
        (nil, [.general]),
        ("Data", [.connections, .apps, .widgets, .customMetrics]),
        ("App", [.account, .updates, .about]),
    ]
}

/// The System Settings look: a sidebar, and `Form`s with grouped sections.
///
/// `.formStyle(.grouped)` inside a `NavigationSplitView` detail column *is*
/// that appearance — the inset cards, the trailing controls, the section
/// headers. Hand-rolling it with `GroupBox` gets close and drifts the moment
/// Apple adjusts their metrics.
struct SettingsRootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var env = env
        return NavigationSplitView {
            List(selection: $env.settingsPane) {
                ForEach(Array(SettingsPane.sections.enumerated()), id: \.offset) { _, section in
                    if let title = section.0 {
                        Section(title) { rows(section.1) }
                    } else {
                        rows(section.1)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 260)
        } detail: {
            detail
                .navigationTitle(env.settingsPane.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func rows(_ panes: [SettingsPane]) -> some View {
        ForEach(panes) { pane in
            Label(pane.title, systemImage: pane.symbol).tag(pane)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch env.settingsPane {
        case .general: GeneralPane()
        case .connections: ConnectionsPane()
        case .apps: AppsPane()
        case .widgets: WidgetsPane()
        case .customMetrics: CustomMetricsPane()
        case .account: AccountPane()
        case .updates: UpdatesPane()
        case .about: AboutPane()
        }
    }
}
