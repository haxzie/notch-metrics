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

/// The metrics an agent has written into Application Support.
///
/// Restored, with one change: the toggle records a *digest* rather than an id,
/// because approval is of contents. A metric rewritten after it was enabled
/// comes back as `.modified` and has to be approved again — the row says so
/// rather than silently running code nobody agreed to.
/// Custom apps, and the metrics that came with them.
///
/// App-first, not metric-first. A custom app is one piece of code holding one
/// credential, and its metrics are what it answers; listing the metrics flat
/// invited the reading that each was separately installed and separately
/// trusted, which is the thing the connector format exists to stop being true.
struct CustomAppsPane: View {
    @Environment(AppEnvironment.self) private var env
    @State private var loadFailure: String?

    private var isEmpty: Bool { env.connectors.connectors.isEmpty }

    var body: some View {
        Form {
            Section {
                if isEmpty {
                    ContentUnavailableView {
                        Label("No custom apps", systemImage: "curlybraces")
                    } description: {
                        Text(
                            "Load one you have built, or ask Claude Code — or any MCP client — to write one:\n\nclaude mcp add notch-metrics -- npx -y @notchmetrics/mcp"
                        )
                        .font(.callout)
                    }
                    .padding(.vertical, 16)
                } else {
                    ForEach(env.connectors.connectors) { app in
                        ConnectorRow(app: app)
                    }
                }
            } header: {
                HStack {
                    Text("Apps")
                    Spacer()
                    Button("Load app…") { load() }
                        .buttonStyle(.link)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let loadFailure {
                        Text(loadFailure)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                    Text(
                        "Custom apps run on your machine with your own API keys. A new one does not run until you enable it here."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Picks a directory, because a connector is a folder — a manifest beside
    /// its built entry — not a single file.
    private func load() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Load"
        panel.message = "Pick the folder containing manifest.json and connector.mjs."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFailure = env.loadConnector(from: url)
    }
}

/// One custom app: what it is, which build is installed, and where it came
/// from.
private struct ConnectorRow: View {
    @Environment(AppEnvironment.self) private var env
    let app: LoadedConnector

    @State private var verifying = false
    @State private var verifyResult: (ok: Bool, message: String)?
    @State private var confirmingRemove = false
    @State private var removeFailure: String?

    private var isOn: Bool { app.state == .ready }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                icon

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.displayName).font(.body)
                    if let manifest = app.manifest {
                        Text(manifest.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // Version, metric count and path on one line: three
                        // short facts that answer "which build, how much, from
                        // where" without three more rows of chrome.
                        Text(subtitle(manifest))
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                }

                Spacer()
                control
                actions
            }

            if case .modified = app.state {
                // Naming what is newly asked for is the whole reason this
                // state survived. "This app has changed" was true of an icon
                // edit and of a new credential request alike, so it taught
                // people to click through it.
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let removeFailure {
                Text(removeFailure)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            if case .invalid(let reason) = app.state {
                // Selectable, because this is what the user pastes back into
                // their agent to get it fixed.
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let manifest = app.manifest, !manifest.allowedHosts.isEmpty {
                Text("Reaches: \(manifest.allowedHosts.joined(separator: ", "))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            // Said out loud, beside the hosts. An app that receives a token
            // the user never typed has to show that before they enable it —
            // the alternative is a credential handed over invisibly.
            if let manifest = app.manifest, !manifest.supportedHostCredentials.isEmpty {
                Text("Uses: \(manifest.supportedHostCredentials.map(\.displayName).joined(separator: ", "))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.orange)
            }

            credentials
        }
        .padding(.vertical, 4)
    }

    /// The app's credentials, as a form here rather than a trip to a browser.
    ///
    /// A local app has no redirect URI and nothing to redirect to, so the
    /// OAuth flow the server connectors use cannot apply — pointing it at one
    /// produced "Could not start that connection", which was accurate and
    /// useless. The fields come from the manifest, which declares them in the
    /// same `AuthField` shape a served connector does.
    ///
    /// Credentials belong to the **app**, not to a widget: one key answers
    /// every metric behind it, which is the whole point of the connector
    /// format. So they are asked for once, here, and not in each tile's
    /// configure pane.
    @ViewBuilder
    private var credentials: some View {
        if let manifest = app.manifest {
            if manifest.requiresCredentials {
                VStack(alignment: .leading, spacing: 6) {
                    Divider().opacity(0.4)
                    ForEach(manifest.auth, id: \.key) { field in
                        CredentialField(connectorId: app.id, field: field)
                    }

                    HStack(spacing: 8) {
                        Button(verifying ? "Checking…" : "Verify") { verify(app) }
                            .controlSize(.small)
                            .disabled(verifying)
                        if let verifyResult {
                            Text(verifyResult.message)
                                .font(.caption)
                                .foregroundStyle(verifyResult.ok ? Color.secondary : Color.orange)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 2)
            } else if manifest.authMode == ConnectorAuthMode.none {
                // Said explicitly rather than left blank. An app with no form
                // and no explanation reads as one that has not finished
                // loading.
                Text("No credentials needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func verify(_ app: LoadedConnector) {
        verifying = true
        verifyResult = nil
        Task {
            let outcome = await env.verifyConnector(app)
            verifying = false
            verifyResult = outcome
        }
    }

    private func subtitle(_ manifest: ConnectorManifest) -> String {
        let count = app.metricCount
        let metrics = count == 1 ? "1 metric" : "\(count) metrics"
        return "v\(manifest.displayVersion) · \(metrics) · \(app.displayPath)"
    }

    /// The icon the app declared, drawn by the same view every other surface
    /// uses.
    ///
    /// This was a hand-rolled square that only understood a PNG on disk, so a
    /// manifest declaring a symbol rendered the generic mark here while the
    /// gallery drew it correctly — two renderings of one thing, which is the
    /// drift `ConnectorIcon` exists to prevent.
    private var icon: some View {
        let custom = AppCatalog.resolve(AppCatalog.customId)
        return ConnectorIcon(
            app: MetricApp(
                id: LocalCatalogue.id(for: app.id),
                name: app.displayName,
                symbol: custom.symbol,
                accentHex: custom.accentHex,
                customIcon: app.icon,
                customIconFile: app.iconURL),
            size: 32)
    }

    /// Reload and Remove.
    ///
    /// A menu rather than two buttons: they are rare, and a row that carries
    /// its destructive action in the open invites the click nobody meant to
    /// make. Removal asks first, and says what it will take with it — the
    /// widgets go too, and that is not obvious from the word "Remove".
    private var actions: some View {
        Menu {
            Button("Reload") { env.reloadConnector(app) }
            // Reveals rather than opens. A `.log` has no default handler on a
            // clean Mac, so opening it is a "choose an application" sheet;
            // selecting it in Finder always works and leaves the user next to
            // the file to do what they like with.
            Button("Open logs") { env.revealConnectorLog(app) }
                .disabled(!ConnectorLog.exists(id: app.id))
            Divider()
            Button("Remove…", role: .destructive) { confirmingRemove = true }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22)
        .confirmationDialog(
            "Remove \(app.displayName)?",
            isPresented: $confirmingRemove, titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { removeFailure = env.removeConnector(app) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalWarning)
        }
    }

    /// What removal will actually take, counted rather than described.
    ///
    /// "This cannot be undone" says nothing a person can weigh. The number of
    /// tiles that will disappear does.
    private var removalWarning: String {
        let widgets = env.widgetCount(forConnector: app.id)
        let tiles =
            widgets == 0
            ? "No widgets use it."
            : widgets == 1 ? "1 widget will be removed from the notch."
            : "\(widgets) widgets will be removed from the notch."
        return "\(tiles) The folder Notch Metrics installed is deleted; anything you built it "
            + "from is untouched."
    }

    /// What the app is newly asking for, in one sentence.
    ///
    /// Always non-empty: `.modified` means the app's grants are not covered by
    /// what was approved, and a set that is not a subset has something in it
    /// to name. An app carried over from an older build never reaches here —
    /// `migrateConnectorApprovals` adopts its grants instead of asking.
    private var warning: String {
        let list = ListFormatter.localizedString(byJoining: app.newGrants)
        guard !list.isEmpty else {
            return "This app asks for more access than you enabled it with."
        }
        return "This app now wants to \(list). It will not run until you allow that."
    }

    @ViewBuilder
    private var control: some View {
        switch app.state {
        case .ready, .pendingApproval:
            // Labelled with the app's name rather than `""`. An empty label
            // leaves the switch with no accessibility name *and* no press
            // action, so VoiceOver reads "tick box" and cannot operate it.
            // `labelsHidden` keeps it out of the layout without taking the
            // name away.
            Toggle(
                "Enable \(app.displayName)",
                isOn: Binding(
                    get: { isOn },
                    set: { env.setConnectorApproved(app, $0) }
                )
            )
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel("Enable \(app.displayName)")

        case .modified:
            // Not a toggle. This is a fresh decision about more access than
            // was granted, so it reads as one.
            Button("Allow") { env.setConnectorApproved(app, true) }
                .buttonStyle(.bordered)

        case .invalid:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
/// Keychain a dozen times while it is being pasted.
private struct CredentialField: View {
    @Environment(AppEnvironment.self) private var env
    let connectorId: String
    let field: ConnectorAuthField

    @State private var value = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(field.label + (field.required ? "" : " (optional)"))
                    .font(.callout)
                if let help = field.help, !help.isEmpty {
                    Text(help).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control
                .frame(width: 220)
                // Saved when the field loses focus as well as on Return.
                // `onSubmit` alone meant typing a key and clicking Verify
                // without pressing Return verified the *previous* value.
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { save() }
                }
        }
        .task {
            // Once. `task` re-runs when the view identity changes, and the
            // registry rescans freely — reloading would discard whatever the
            // user had half-typed.
            guard !loaded else { return }
            value = env.connectorCredential(connectorId, field.key)
            loaded = true
        }
    }

    @ViewBuilder
    private var control: some View {
        switch field.type {
        case .boolean:
            Toggle("", isOn: Binding(
                get: { value == "true" },
                set: { value = $0 ? "true" : "false"; save() }))
                .toggleStyle(.switch)
                .labelsHidden()
        case .select:
            Picker("", selection: Binding(get: { value }, set: { value = $0; save() })) {
                Text("—").tag("")
                ForEach(field.options ?? [], id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
        case .secret, .unknown:
            // An unknown type is masked, not shown in the clear. Showing a
            // visible field masked is a cosmetic annoyance; the reverse puts
            // somebody's token on screen in a screen-share.
            SecureField("", text: $value, prompt: prompt)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
        case .string, .url:
            TextField("", text: $value, prompt: prompt)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
        }
    }

    /// The greyed hint *inside* the field.
    ///
    /// `TextField(_ title:, text:)` renders its first argument as a **label
    /// beside the field**, not as a placeholder — which put the example
    /// package name in the middle of the row, wrapped over two lines, looking
    /// like a value somebody had entered. `prompt:` is the placeholder.
    private var prompt: Text? {
        guard let placeholder = field.placeholder, !placeholder.isEmpty else { return nil }
        return Text(placeholder)
    }

    private func save() {
        env.setConnectorCredential(connectorId, field.key, value)
    }
}
