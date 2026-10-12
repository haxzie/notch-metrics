import MetricsCore
import NotchUI
import SwiftUI

/// One notification in the centre's list.
struct AlertRow: View {
    let alert: NotchAlert
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onOpen: () -> Void
    let onToggleRead: () -> Void
    let onMute: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 9) {
                Circle()
                    .fill(alert.read ? .clear : NotchTheme.editHighlight)
                    .frame(width: 5, height: 5)
                    .padding(.top, 5)

                ConnectorIcon(app: AppCatalog.resolve(alert.provider), size: 18)
                    .overlay(alignment: .bottomTrailing) {
                        if alert.severity == .warning {
                            Circle()
                                .fill(NotchTheme.warning)
                                .frame(width: 6, height: 6)
                                .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 1))
                                .offset(x: 2, y: 2)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        // Semibold while unread, so triage is possible at a
                        // glance rather than by reading the dots.
                        .font(.system(size: 12, weight: alert.read ? .regular : .semibold))
                        .foregroundStyle(NotchTheme.primaryText)
                        .lineLimit(1)

                    if let line = secondLine {
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundStyle(NotchTheme.secondaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 8)

                if isHovered {
                    HStack(spacing: 2) {
                        rowButton(
                            alert.read ? "envelope.badge" : "envelope.open",
                            help: alert.read ? "Mark as unread" : "Mark as read",
                            action: onToggleRead)
                        // The durable action. "Mark as read" is the ephemeral
                        // one; there is deliberately no delete, because the
                        // server would re-sync anything cleared here.
                        rowButton("bell.slash", help: "Stop telling me this", action: onMute)
                        if alert.link != nil {
                            rowButton(
                                "arrow.up.forward.square", help: "Open in your browser",
                                action: onOpen)
                        }
                    }
                    .transition(.opacity)
                } else {
                    Text(relativeTime)
                        .font(.system(size: 10.5))
                        .foregroundStyle(NotchTheme.tertiaryText)
                        .padding(.top, 1)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .contextMenu {
            Button(alert.read ? "Mark as Unread" : "Mark as Read", action: onToggleRead)
            Button("Stop Telling Me This", action: onMute)
            if alert.link != nil { Button("Open in Browser", action: onOpen) }
        }
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(NotchTheme.secondaryText)
        .help(help)
    }

    /// The body, or the amount when there is no body — so a row always says
    /// something beyond its title.
    private var secondLine: String? {
        if let body = alert.body, !body.isEmpty { return body }
        guard let amount = alert.amount, let currency = alert.currency else { return nil }
        return MetricFormatter.currency(Double(amount) / 100, code: currency, compact: false)
    }

    private var relativeTime: String {
        guard let occurred = alert.occurred else { return "" }
        return occurred.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
    }
}

/// One connection's notification types, reached by the gear in the toolbar.
///
/// Deliberately short and scoped to a single connection. The full matrix is in
/// Settings — see the comment on the sidebar's settings row.
struct AlertTypeList: View {
    @Environment(AppEnvironment.self) private var env
    let integrationId: String
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                    Text(name).font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(NotchTheme.secondaryText)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if definitions.isEmpty {
                        Text("This app doesn't send notifications yet.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(NotchTheme.secondaryText)
                    }
                    ForEach(definitions) { definition in
                        toggle(for: definition)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func toggle(for definition: AlertDefinition) -> some View {
        let subscription = env.alertSubscription(for: integrationId, typeId: definition.id)
        return VStack(alignment: .leading, spacing: 2) {
            Toggle(
                definition.label,
                isOn: Binding(
                    get: { subscription?.enabled ?? definition.defaultEnabled },
                    set: { value in
                        Task { await env.setAlertEnabled(value, for: integrationId, typeId: definition.id) }
                    })
            )
            .font(.system(size: 12))
            .toggleStyle(.switch)
            .controlSize(.mini)
            // A locked row rather than a hidden one, so the user can still see
            // what they will be told.
            .disabled(!definition.userConfigurable)

            Text(definition.methodology)
                .font(.system(size: 10.5))
                .foregroundStyle(NotchTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            // A threshold with no bound set never fires, and nothing else on
            // this row would say so.
            if definition.isThreshold, subscription?.threshold == nil {
                Text("Set a figure in Notification Settings to use this.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(NotchTheme.warning)
            }
        }
    }

    private var name: String {
        env.alertSnapshot.connections.first { $0.integrationId == integrationId }?.label
            ?? "Connection"
    }

    private var definitions: [AlertDefinition] {
        env.alertDefinitions(forIntegration: integrationId)
    }
}
