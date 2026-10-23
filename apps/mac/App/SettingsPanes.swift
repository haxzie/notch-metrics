import MetricsAPI
import MetricsCore
import NotchUI
import PluginRuntime
import SwiftUI
import Updater

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
    @State private var isConfirmingSignOut = false
    @State private var isSigningOut = false

    var body: some View {
        Form {
            Section("Account") {
                if env.isSignedIn {
                    // The email rather than "Signed in", when it is known.
                    // Which account this Mac is signed in as is the question
                    // the pane is open to answer — on a second account, or
                    // after somebody else used the machine, "Signed in" says
                    // nothing that the presence of numbers in the notch did
                    // not already say.
                    //
                    // `/v1/me` has not answered yet on a cold launch, and
                    // never answers offline — so the row changes label rather
                    // than value. "Signed in as: Signed in" is what pairing
                    // the new label with the old fallback reads as.
                    if let email = env.account?.email {
                        LabeledContent("Signed in as", value: email)
                    } else {
                        LabeledContent("Status", value: "Signed in")
                    }
                    Button("Open billing") {
                        NSWorkspace.shared.open(
                            AppEnvironment.appURL.appendingPathComponent("app/settings/billing"))
                    }
                    signOutButton
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

    /// Signs this Mac out, after asking.
    ///
    /// Confirmed rather than immediate: signing back in is a browser round
    /// trip through the website, which is a long way back from a misclick on a
    /// pane whose other button opens billing. The dialog names what it does
    /// and what it leaves alone — the widgets stay arranged.
    private var signOutButton: some View {
        Button("Sign out…", role: .destructive) { isConfirmingSignOut = true }
            .disabled(isSigningOut)
            .confirmationDialog(
                "Sign out of Notch Metrics?", isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) {
                    isSigningOut = true
                    Task {
                        await env.signOut()
                        isSigningOut = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This Mac stops showing your numbers until you sign in again. "
                        + "Your widgets stay as you arranged them.")
            }
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
        signInError = env.beginSignIn()
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

            Section("Updates") { status }
        }
        .formStyle(.grouped)
    }

    /// One row per state, because they are mutually exclusive.
    ///
    /// Everything that is not a state of the update itself — the installed
    /// version, the automatic toggle — stays in the section above, so this one
    /// can be read top to bottom as "what is happening right now".
    @ViewBuilder
    private var status: some View {
        switch env.updates.state {
        case .idle:
            LabeledContent("Status") {
                Button("Check now") { check() }
            }

        case .checking:
            working("Checking for updates…")

        case let .upToDate(checkedAt):
            LabeledContent("Status") {
                HStack(spacing: 10) {
                    Text("Notch Metrics is up to date.")
                    Spacer(minLength: 0)
                    Button("Check now") { check() }
                }
            }
            LabeledContent("Last checked", value: Self.when.localizedString(for: checkedAt, relativeTo: Date()))

        case let .available(manifest):
            offer(manifest)
            LabeledContent("Download") {
                Button("Download") { Task { await env.updates.download() } }
                    .buttonStyle(.borderedProminent)
            }

        case let .downloading(manifest, fraction):
            offer(manifest)
            LabeledContent("Downloading") {
                // Determinate, because the one thing somebody wants to know
                // about an 18 MB download is whether it is moving.
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 220)
            }

        case let .verifying(manifest):
            offer(manifest)
            working("Checking the download…")

        case let .readyToInstall(manifest, _):
            offer(manifest)
            LabeledContent("Ready") {
                Button("Install and restart") { env.updates.install() }
                    .buttonStyle(.borderedProminent)
            }
            Text("Notch Metrics quits, swaps itself for the new version, and reopens.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case let .installing(manifest):
            offer(manifest)
            working("Installing…")

        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
            LabeledContent("Status") {
                Button("Try again") {
                    env.updates.dismissFailure()
                    check()
                }
            }
        }
    }

    /// The headline for every state that has a manifest behind it, so the
    /// version being downloaded is on screen the whole way through rather than
    /// only on the screen that offered it.
    @ViewBuilder
    private func offer(_ manifest: LatestManifest) -> some View {
        LabeledContent("Available") {
            HStack(spacing: 10) {
                Text("Version \(manifest.version)")
                Text(Self.size.string(fromByteCount: Int64(manifest.size)))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let notes = manifest.notes {
                    Link("Release notes", destination: notes)
                }
            }
        }
    }

    private func working(_ text: String) -> some View {
        LabeledContent("Status") {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(text).foregroundStyle(.secondary)
            }
        }
    }

    private func check() {
        Task { await env.updates.check(userInitiated: true) }
    }

    private static let size: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter
    }()

    private static let when: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        // `.named` so a check that has just finished reads "now". The default
        // rounds the sub-second gap to zero and then picks the future phrasing
        // for it, so the row said the last check happened "in 0 seconds".
        formatter.dateTimeStyle = .named
        return formatter
    }()
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
