import MetricsAPI
import MetricsCore
import NotchUI
import SwiftUI

/// The notification centre: connections down the left, their notifications on
/// the right.
///
/// Lives in the app target rather than in NotchUI for the same reason
/// `WidgetBrowserPane` does — it needs the user's connections. NotchUI owns the
/// frame, the height and the way in and out, and nothing inside this.
///
/// Deliberately the same two-column geometry as the widget browser: a 176pt
/// sidebar in a 440pt body, same card, same divider. The same frame at the same
/// size reads as the same room.
struct AlertCentrePane: View {
    @Environment(AppEnvironment.self) private var env

    @State private var selection: AlertSelection = .all
    @State private var query = ""
    @State private var hoveredID: String?
    /// Non-nil while the gear is showing one connection's toggles instead of
    /// its notifications.
    @State private var managing: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task {
            // Opening the pane is what stops the backfill bannering: anything
            // already on screen has been seen, whether or not it is read.
            await env.alerts.stampSeen()
            await env.refreshAlerts()
        }
        .onChange(of: env.notch.alertsFocus) { _, focus in
            guard let focus else { return }
            if let integrationId = focus.integrationId {
                selection = .connection(integrationId)
            }
            // Honoured once, then cleared, or every re-render would reset the
            // user's own choice of connection.
            env.notch.alertsFocus = nil
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 1) {
                sidebarRow(
                    icon: { AnyView(Image(systemName: "bell").font(.system(size: 12))) },
                    title: "All",
                    count: env.alertSnapshot.unread,
                    value: .all)

                if !connections.isEmpty {
                    Text("Connections")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }

                ForEach(connections) { connection in
                    sidebarRow(
                        icon: {
                            AnyView(
                                ConnectorIcon(
                                    app: AppCatalog.resolve(connection.provider), size: 16))
                        },
                        title: connection.label,
                        // Unread, not total: a connection with forty read
                        // notifications should not read as urgent.
                        count: connection.unread,
                        value: connection.integrationId.map { .connection($0) } ?? .all)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 176)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            // The long per-connection toggle matrix lives in Settings: a four
            // connection by six type grid is a 24-row form, and this body is
            // 440pt with a feed in it.
            Button {
                env.settingsPane = .notifications
                env.openSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 10))
                    Text("Notification Settings…").font(.system(size: 11))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(NotchTheme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(.black.opacity(0.18))
        }
    }

    private func sidebarRow(
        icon: () -> AnyView, title: String, count: Int?, value: AlertSelection
    ) -> some View {
        let isSelected = selection == value
        return Button {
            selection = value
            managing = nil
        } label: {
            HStack(spacing: 8) {
                icon().frame(width: 17)
                Text(title)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(NotchTheme.editHighlight)
                }
            }
            .foregroundStyle(isSelected ? NotchTheme.primaryText : NotchTheme.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 7)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            if let managing {
                AlertTypeList(integrationId: managing, onBack: { self.managing = nil })
            } else {
                body(for: visibleAlerts)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(NotchTheme.tertiaryText)
            TextField("Search notifications…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.tertiaryText)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            Button("Mark all read") {
                Task { await env.markAlertsRead(in: scope) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(
                scopedUnread > 0 ? NotchTheme.secondaryText : NotchTheme.tertiaryText)
            .disabled(scopedUnread == 0)

            if case .connection(let id) = selection {
                Button {
                    managing = id
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Which notifications this connection sends")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    @ViewBuilder
    private func body(for alerts: [NotchAlert]) -> some View {
        if env.alertsLoading && env.alertSnapshot.alerts.isEmpty {
            centred {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Catching up…")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.secondaryText)
                }
            }
        } else if let problem = env.alertsProblem, env.alertSnapshot.alerts.isEmpty {
            centred {
                VStack(spacing: 10) {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(NotchTheme.secondaryText)
                    Button("Retry") { Task { await env.refreshAlerts() } }
                        .controlSize(.small)
                }
            }
        } else if alerts.isEmpty {
            centred {
                Text(emptyMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(dayGroups(of: alerts), id: \.key) { group in
                        Text(group.key)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(NotchTheme.tertiaryText)
                            .padding(.top, 2)

                        ForEach(group.alerts) { alert in
                            AlertRow(
                                alert: alert,
                                isHovered: hoveredID == alert.id,
                                onHover: { hoveredID = $0 ? alert.id : nil },
                                onOpen: { open(alert) },
                                onToggleRead: { Task { await env.markAlertsRead(ids: [alert.id]) } },
                                onMute: { Task { await env.muteAlertType(alert) } })
                        }
                    }

                    // Paging is explicit rather than on-scroll: an automatic
                    // fetch at the bottom of a 440pt pane fires on almost
                    // every flick.
                    if env.alertSnapshot.hasMore && query.isEmpty {
                        Button("Load earlier") { Task { await env.loadEarlierAlerts() } }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .padding(.top, 4)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(14)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func centred<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack { Spacer(minLength: 0); content(); Spacer(minLength: 0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    private var connections: [AlertConnectionSummary] {
        env.alertSnapshot.connections
    }

    private var scope: AlertScope {
        switch selection {
        case .all: return .all
        case .connection(let id): return .connection(id)
        }
    }

    private var scopedUnread: Int {
        switch selection {
        case .all: return env.alertSnapshot.unread
        case .connection(let id):
            return env.alertSnapshot.alerts.filter {
                $0.integrationId == id && !$0.read
            }.count
        }
    }

    private var visibleAlerts: [NotchAlert] {
        var rows = env.alertSnapshot.alerts
        if case .connection(let id) = selection {
            rows = rows.filter { $0.integrationId == id }
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return rows }
        return rows.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || ($0.body ?? "").localizedCaseInsensitiveContains(trimmed)
                || $0.connectionLabel.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var emptyMessage: String {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return "Nothing matches “\(trimmed)”." }
        switch selection {
        case .connection(let id):
            let name = connections.first { $0.integrationId == id }?.label ?? "this connection"
            return "Nothing from \(name) yet."
        case .all:
            return
                "Nothing to report.\nFailed payments, unusual numbers and sync problems show up here."
        }
    }

    private struct DayGroup {
        let key: String
        let alerts: [NotchAlert]
    }

    /// Grouped by day, because within a connection the organising axis is time.
    private func dayGroups(of alerts: [NotchAlert]) -> [DayGroup] {
        let calendar = Calendar.current
        var order: [String] = []
        var buckets: [String: [NotchAlert]] = [:]

        for alert in alerts {
            let key = Self.dayLabel(alert.occurred, calendar: calendar)
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(alert)
        }
        return order.map { DayGroup(key: $0, alerts: buckets[$0] ?? []) }
    }

    private static func dayLabel(_ date: Date?, calendar: Calendar) -> String {
        guard let date else { return "Earlier" }
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private func open(_ alert: NotchAlert) {
        Task { await env.markAlertsRead(ids: [alert.id]) }
        // A row with nowhere to go just marks itself read; the body is already
        // on screen, so there is nothing to expand into.
        if let link = alert.link { NSWorkspace.shared.open(link) }
    }
}

enum AlertSelection: Hashable {
    case all
    case connection(String)
}
