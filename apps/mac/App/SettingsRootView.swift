import MetricsCore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general, connections, apps, widgets, account, updates, about

    /// `notchmetrics://settings/integrations` is in the wild — in the website,
    /// in the connect flow's return URL — and kept working when the pane was
    /// renamed to Apps.
    ///
    /// `custom-metrics` is parked rather than removed: the plugin runtime and
    /// the MCP server still exist, so a link to a pane that is not in the
    /// sidebar should land somewhere sensible instead of nowhere.
    static let aliases: [String: SettingsPane] = [
        "integrations": .apps,
        "customMetrics": .widgets,
        "custom-metrics": .widgets,
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .connections: "Connections"
        case .apps: "Apps"
        case .widgets: "Widgets"
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
        // A box, not another grid: Apps is `square.grid.2x2` and the two
        // sat next to each other in the sidebar looking near-identical.
        case .widgets: "square.on.square"
        case .account: "person.crop.circle"
        case .updates: "arrow.triangle.2.circlepath"
        case .about: "info.circle"
        }
    }

    /// Grouped the way System Settings groups things: the thing you came to
    /// change, then your data, then the app itself.
    static let sections: [(String?, [SettingsPane])] = [
        // Widgets first and ungrouped: it is what people open this window to
        // change. General is down in App with the other
        // set-it-once-and-forget-it panes.
        (nil, [.widgets]),
        ("Data", [.connections, .apps]),
        ("App", [.account, .general, .updates, .about]),
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
        case .account: AccountPane()
        case .updates: UpdatesPane()
        case .about: AboutPane()
        }
    }
}
