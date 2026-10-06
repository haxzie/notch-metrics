import MetricsAPI
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

struct AccountPane: View {
    @Environment(AppEnvironment.self) private var env
    @State private var signInError: String?

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
                    LabeledContent("Sign in") {
                        HStack(spacing: 8) {
                            if case .waiting = env.signIn {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Waiting for browser approval…")
                                    .foregroundStyle(.secondary)
                                Button("Cancel") { env.signInFinished(error: nil) }
                                    .buttonStyle(.link)
                            } else {
                                Button("Sign in…") { beginSignIn() }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }

                    if let message = failureMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Mints the PKCE challenge *before* opening the browser.
    ///
    /// Opening `/desktop/auth` bare is what this used to do, and the page can
    /// only answer "this link is missing information" — the challenge and
    /// state are the whole request. Nothing about the button looked wrong,
    /// which is why it survived.
    /// The local failure from building the link, or the one the callback
    /// reported. Both land in the same place so there is one thing to read.
    private var failureMessage: String? {
        if let signInError { return signInError }
        if case let .failed(message) = env.signIn { return message }
        return nil
    }

    private func beginSignIn() {
        do {
            let url = try AuthCoordinator().signInURL(appBase: AppEnvironment.appURL)
            signInError = nil
            env.signInStarted()
            NSWorkspace.shared.open(url)
        } catch {
            // Writing the pending challenge is what fails here, and silently
            // opening the browser anyway would strand the user on the same
            // unhelpful page.
            signInError = "Could not start sign-in. Check that Notch Metrics can write to Application Support."
        }
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
