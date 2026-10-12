import MetricsAPI
import MetricsCore
import NotchUI
import SwiftUI

/// The authoritative notification settings.
///
/// The notch gets the fast path — mute this type, mute this connection — and
/// this gets the full matrix. A four-connection by six-type grid is a 24-row
/// form, and the notch's body is 440pt with a feed already in it. The same
/// split the Apps pane already makes for connectors.
struct NotificationsPane: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Form {
            deliverySection
            quietHoursSection

            perConnectionPointer
            energySection
        }
        .formStyle(.grouped)
        .task { await env.loadAlertSettings() }
    }

    private var deliverySection: some View {
        Section {
            Toggle(
                "Show notifications in the notch",
                isOn: binding(\.alertBannersEnabled) { $0.alertBannersEnabled = $1 })

            if env.settings.alertBannersEnabled {
                LabeledContent("Hide after") {
                    Stepper(
                        "\(env.settings.alertBannerSeconds)s",
                        value: binding(\.alertBannerSeconds) { $0.alertBannerSeconds = $1 },
                        in: 2...15)
                }

                Picker(
                    "Sound",
                    selection: Binding(
                        get: { env.settings.alertSound },
                        set: { sound in
                            env.updateSettings { $0.alertSound = sound }
                            // Played on selection, not only on the button: the
                            // whole reason to open this picker is to hear them,
                            // and making that a second click is a picker people
                            // set once to the wrong thing.
                            AlertSoundPlayer.play(sound)
                        })
                ) {
                    ForEach(AlertSound.allCases) { sound in
                        Text(sound.label).tag(sound)
                    }
                }

                if env.settings.alertSound != .none {
                    LabeledContent(env.settings.alertSound.summary) {
                        Button("Play") { AlertSoundPlayer.play(env.settings.alertSound) }
                            .controlSize(.small)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let settings = env.alertSettings {
                Toggle(
                    "Send me notifications",
                    isOn: Binding(
                        get: { settings.enabled },
                        set: { value in
                            var next = settings
                            next.enabled = value
                            Task { await env.updateAlertSettings(next) }
                        }))
            }
        } header: {
            Text("Delivery")
        } footer: {
            // Said plainly, because the alternative is a user who thinks this
            // is a pager and finds out otherwise at 3am.
            Text(
                "Notifications slide out of the notch and tuck away again. "
                    + "They arrive within about five minutes, and they are a log you "
                    + "catch up on rather than an alarm — nothing is delivered while "
                    + "your Mac is asleep."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var quietHoursSection: some View {
        if let settings = env.alertSettings {
            Section {
                Toggle(
                    "Quiet hours",
                    isOn: Binding(
                        get: { settings.quietFromMinute != nil },
                        set: { value in
                            var next = settings
                            // 22:00 to 08:00, which is the window most people
                            // would pick anyway.
                            next.quietFromMinute = value ? 22 * 60 : nil
                            next.quietToMinute = value ? 8 * 60 : nil
                            Task { await env.updateAlertSettings(next) }
                        }))

                if let from = settings.quietFromMinute, let to = settings.quietToMinute {
                    LabeledContent("From") {
                        minutePicker(from) { minute in
                            var next = settings
                            next.quietFromMinute = minute
                            Task { await env.updateAlertSettings(next) }
                        }
                    }
                    LabeledContent("Until") {
                        minutePicker(to) { minute in
                            var next = settings
                            next.quietToMinute = minute
                            Task { await env.updateAlertSettings(next) }
                        }
                    }
                }
            } footer: {
                Text(
                    "Notifications raised during quiet hours still arrive — they just "
                        + "wait in the notch instead of sliding out."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func minutePicker(
        _ minute: Int, onChange: @escaping @Sendable (Int) -> Void
    ) -> some View {
        Picker("", selection: Binding(get: { minute }, set: onChange)) {
            ForEach(0..<24, id: \.self) { hour in
                Text(String(format: "%02d:00", hour)).tag(hour * 60)
            }
        }
        .labelsHidden()
        .frame(width: 90)
    }

    /// Where the per-connection toggles went.
    ///
    /// They live in Connections now: what Stripe is allowed to tell you is a
    /// fact about your Stripe connection, not an app-wide preference — and this
    /// pane was growing a second, divergent copy of the connection list to hold
    /// them. A pointer costs a line; two lists that disagree costs a bug.
    private var perConnectionPointer: some View {
        Section {
            Button {
                env.settingsPane = .connections
            } label: {
                HStack {
                    Label("Choose what each connection tells you", systemImage: "link")
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } footer: {
            Text("Each connection has its own list of notifications, in Connections.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Read-only, and deliberately shown.
    ///
    /// This app's whole premise is that it is cheap to leave running. Telling
    /// the user the cadence is both honest and the cheapest possible bug
    /// report — "it says checking every 10 minutes" is a far better message
    /// than "notifications seem slow".
    private var energySection: some View {
        Section("Energy") {
            LabeledContent("Checking") { Text(cadenceDescription) }
        }
    }

    private var cadenceDescription: String {
        let conditions = env.gate.conditions
        if let reason = EnergyPolicy.suspensionReason(conditions) {
            return "Paused — \(reason)"
        }
        switch EnergyPolicy.alertCadence(conditions) {
        case .suspended:
            return conditions.lowPowerMode
                ? "Paused — Low Power Mode" : "Paused to save power"
        case .every(let interval):
            let seconds = Int(interval.components.seconds)
            let unit =
                seconds >= 120 ? "every \(seconds / 60) minutes" : "every \(seconds) seconds"
            return "\(unit) · \(conditions.onBattery ? "on battery" : "plugged in")"
        }
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
