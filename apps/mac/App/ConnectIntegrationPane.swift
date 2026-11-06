import MetricsAPI
import MetricsCore
import NotchUI
import Providers
import SwiftUI

/// Asking for one connector's credentials, in the notch.
///
/// This replaces a trip to the browser. The app used to mint a link, open a
/// tab, and let the website collect the key so the server could keep it —
/// which is why `AppsPane` still says keys are "never stored on this Mac".
/// With the credentials living in this Mac's Keychain there is nothing on the
/// other end of that trip.
///
/// Every field, its help text and the setup steps come from the served
/// manifest rather than from anything compiled in, which is the property that
/// lets a connector ship without a Mac release. This view knows how to draw
/// an `AuthField`; it knows nothing about Stripe.
struct ConnectIntegrationPane: View {
    let connectorId: String
    /// Shared with the header's Connect and Cancel, which are a second view
    /// over the same state — so this is handed in rather than owned here.
    let model: ConnectModel
    /// Only for the failure state, which has no header buttons behind it:
    /// the header offers Cancel once a connector has loaded, and a catalogue
    /// that never answered leaves nothing to cancel.
    let onDone: () -> Void

    @Environment(AppEnvironment.self) private var env
    /// Which field has the caret. Keyed on the field's own key so the pane
    /// can put it on the first one without knowing what that is.
    @FocusState private var focused: String?

    /// The footer, which does not scroll and so is not measured. A constant
    /// because it is one row whatever the connector is.
    private static let chromeHeight: CGFloat = 44

    /// The gap on either side of the rule between the columns.
    ///
    /// One number for both sides. The two halves previously had 0 at the
    /// panel edge and 14 at the rule on the left, against 14 and 14 on the
    /// right, so the left column sat flush to the bezel while the right
    /// floated — which reads as a column that has slipped rather than as two
    /// columns.
    private static let gutter: CGFloat = 14

    /// Extra room at the two outer edges, on top of the pane's own margin.
    ///
    /// This pane is inset further than the grid or the browser, deliberately.
    /// Those are full-bleed by nature — a wall of tiles, a wall of cards — and
    /// this is a form with a rule down the middle, which needs the margin to
    /// read as two columns rather than as text pushed against the bezel.
    private static let outerInset: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.state {
            case .loading:
                loading
            case .failed(let reason):
                failure(reason)
            case .ready(let connector):
                form(connector)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await model.load(connectorId, env: env)
            // The caret goes in the first field the moment the form has one.
            //
            // Not a nicety. Cmd-V needs a first responder to paste into, and
            // without this the pane opened with nothing focused — so the
            // first thing anybody does here, paste a key, silently did
            // nothing until they had clicked the field. The window being
            // key and the app being active are necessary and were not
            // sufficient; see `NotchWindowController.takeKeyboardFocus`.
            focused = model.connector?.fields.first?.key
        }
    }

    // MARK: - The form

    /// A split, the same shape the configure pane uses and for the same
    /// reason: the notch is far wider than it is tall, so a stack puts the
    /// instructions above the field and pushes the field off the bottom.
    /// Side by side, the steps stay on screen while the key is pasted in —
    /// which matters here more than it does there, because the steps are
    /// being followed in another window at the same time.
    private func form(_ connector: ConnectorEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                instructions(connector)
                    .frame(width: 288)

                // A rule, now that the instructions have no surface of their
                // own to draw the edge. One or the other: a card *and* a
                // divider is two lines saying the same thing.
                Divider()
                    .padding(.horizontal, Self.gutter)

                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            fieldsSection(connector)
                        }
                        .padding(.bottom, 6)
                        // Reports its natural height so the notch opens tall
                        // enough. Measured *inside* the scroll view, where
                        // the content does not depend on the viewport it is
                        // given — measuring the pane itself reads back the
                        // height the notch just imposed, a loop that settles
                        // on the fallback and looks like a form that will
                        // not grow.
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: ConfigurePanelHeightKey.self,
                                    value: proxy.size.height + Self.chromeHeight)
                            })
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollContentBackground(.hidden)

                    Spacer(minLength: 8)
                    footer(connector)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, Self.outerInset)
        }
    }

    /// The credentials, as one titled card of rows.
    ///
    /// The same `section`/`row` idiom as the configure pane rather than a
    /// column of labelled boxes: these two panes open in the same panel, one
    /// after the other on the way to a working tile, and a form that changed
    /// shape between them read as two different apps.
    @ViewBuilder
    private func fieldsSection(_ connector: ConnectorEntry) -> some View {
        if connector.fields.isEmpty {
            // Said rather than left blank. A connector with nothing to ask
            // for would otherwise show an empty card under a "Credentials"
            // heading, which reads as a form that failed to load rather than
            // one with nothing in it.
            section("Credentials") {
                note(
                    "\(connector.name) needs no credentials. "
                        + "Add a widget and name what it should count.",
                    top: 10)
            }
        } else {
            credentialFields(connector)
        }
    }

    @ViewBuilder
    private func credentialFields(_ connector: ConnectorEntry) -> some View {
        section("Credentials") {
            ForEach(Array(connector.fields.enumerated()), id: \.element.key) { index, field in
                if index > 0 { Divider().opacity(0.4) }
                row(field.label, optional: !field.required) {
                    ConnectorFieldControl(
                        field: field, value: model.binding(for: field), focused: $focused)
                }
                // Under the row rather than beside the control: help is a
                // sentence and the control side of a row is 200pt wide.
                if let problem = model.problem(for: field) {
                    note(problem, tone: .orange)
                } else if let help = field.help, !help.isEmpty {
                    note(help)
                }
            }
        }
    }

    // MARK: - The configure pane's idiom

    /// A titled group of rows on one translucent card.
    ///
    /// Copied deliberately from `WidgetConfigurator`, which hand-builds this
    /// rather than using `Form(.grouped)` — that paints its own opaque
    /// background and ignores the notch's material entirely.
    private func section<V: View>(
        _ title: String, @ViewBuilder content: () -> V
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            VStack(spacing: 0) { content() }
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func row<V: View>(
        _ label: String, optional: Bool = false, @ViewBuilder control: () -> V
    ) -> some View {
        HStack(spacing: 12) {
            // Never compressed: a control too wide for the row should
            // truncate on its own side rather than wrap this to a column of
            // single letters.
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 13))
                if optional {
                    Text("optional")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    /// A sentence inside a card.
    ///
    /// `top` is zero when this sits under a row, which has its own bottom
    /// padding, and non-zero when it is the only thing in the card.
    private func note(_ text: String, tone: Color = .secondary, top: CGFloat = 0) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(tone)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, top)
            .padding(.bottom, 10)
    }

    /// The left column: who is being connected, then how to get the key.
    ///
    /// No surface behind it any more, so the two halves are separated by a
    /// rule rather than by a card. The pair of marks sits above the steps and
    /// centred, which is where the web connect page put it — somebody
    /// arriving here is about to paste a credential, and the first question
    /// that needs answering is which two things are being joined.
    @ViewBuilder
    private func instructions(_ connector: ConnectorEntry) -> some View {
        let steps = connector.setupSteps ?? []
        VStack(alignment: .leading, spacing: 12) {
            ConnectionMarks(connector: model.app(for: connector))
                .frame(maxWidth: .infinity, alignment: .center)

            if steps.isEmpty {
                // Said rather than left blank. An empty column beside a form
                // reads as something that has not finished loading.
                Text("Paste the key from \(connector.name) into the field beside this.")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Where to find it")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                ScrollView {
                    SetupSteps(steps: steps, onOpen: open)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollContentBackground(.hidden)
            }

            // The docs link used to sit in the pane's header, which has gone.
            // Kept rather than dropped with it: the numbered steps deep-link
            // to the exact page for connectors whose manifest names one, and
            // this is the only way out for the ones that do not.
            if let docs = URL(string: connector.docsUrl), !connector.docsUrl.isEmpty {
                Button("\(connector.name) documentation") { open(docs) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    /// What the form has to say for itself. The two buttons that used to live
    /// here are in the notch's header now, beside Close, where every other
    /// pane puts its commit and its way out.
    @ViewBuilder
    private func footer(_ connector: ConnectorEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problem = model.failureMessage {
                // Selectable: a provider's own wording is what somebody
                // pastes into a search or a support message.
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Said plainly, because the app spent its whole life so far
            // telling people the opposite.
            Label("Stored in this Mac's Keychain", systemImage: "lock")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading…").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func failure(_ reason: String) -> some View {
        VStack(spacing: 10) {
            Text(reason)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Close", action: onDone).controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    /// Opens a provider's page, and takes the notch down while it is in front.
    ///
    /// The notch is a panel pinned over everything, so leaving it up over the
    /// tab it just opened is both in the way and unclear about which window
    /// wants input. The field values are held in this pane's model, which
    /// survives, so coming back finds the form as it was left.
    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Setup steps

/// "Where do I get this key", as the manifest wrote it.
private struct SetupSteps: View {
    let steps: [SetupStep]
    let onOpen: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(.quaternary))

                    Text(step.text)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let url = step.url {
                        Button {
                            onOpen(url)
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(url.absoluteString)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - One field

/// One credential input, drawn from what the manifest declared.
///
/// Only the control: the label, the optional marker and the help text are the
/// row's, so a credentials row is laid out by the same `row` the configure
/// pane uses and the two panes line up.
///
/// The sibling of `CredentialField` in `SettingsPanes.swift`, which asks for a
/// *local app's* credentials. The difference is deliberate and worth keeping:
/// that one writes each change straight to the Keychain, because the app it
/// belongs to is already installed and there is nothing to cancel. This one
/// holds the values in memory until they have been verified, so abandoning
/// the form leaves no key behind and nothing is stored that was never checked.
private struct ConnectorFieldControl: View {
    let field: AuthField
    @Binding var value: String
    @FocusState.Binding var focused: String?

    var body: some View {
        switch field.type {
        case "boolean":
            Toggle("", isOn: Binding(get: { value == "true" }, set: { value = $0 ? "true" : "false" }))
                .toggleStyle(.switch)
                .labelsHidden()
        case "select":
            Picker("", selection: $value) {
                Text("—").tag("")
                ForEach(field.options ?? [], id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            // Trailing, not filling the 200pt slot. A popup button sizes
            // itself to its widest option, so in a plain `frame(width:)` it
            // floated in the middle of the column while every text field sat
            // flush against the right edge — two controls in one form
            // disagreeing about where the right margin is.
            .frame(width: 200, alignment: .trailing)
        case "secret":
            SecureField(field.placeholder ?? "", text: $value)
                .focused($focused, equals: field.key)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 13))
                // Borderless, matching the configure pane. The placeholder is
                // the whole affordance, which is why every field in every
                // manifest carries one.
                .frame(width: 200, alignment: .trailing)
        default:
            // An unrecognised type gets a plain text field rather than
            // nothing: a connector served to an older build must still be
            // fillable in. Never the other way round — `secret` is read off
            // the declared type and never guessed, because guessing wrong
            // there puts somebody's token on screen in a screen-share.
            TextField(field.placeholder ?? "", text: $value)
                .focused($focused, equals: field.key)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 13))
                // Borderless, matching the configure pane. The placeholder is
                // the whole affordance, which is why every field in every
                // manifest carries one.
                .frame(width: 200, alignment: .trailing)
        }
    }
}

/// Notch Metrics and the connector, as two overlapping tiles.
///
/// The same arrangement the web connect page used, and kept because it
/// answers the first question somebody on this pane has: which two things am
/// I joining. The connector is on top and rotated the other way, so it reads
/// as the thing being added to the app rather than the other way round.
private struct ConnectionMarks: View {
    let connector: MetricApp

    private static let tile: CGFloat = 38
    /// 28% of the side, which is what the web tiles use. A fixed radius makes
    /// the two squares read as different shapes at this size.
    private static var radius: CGFloat { tile * 0.28 }

    var body: some View {
        HStack(spacing: -10) {
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .fill(Color(red: 0x15 / 255, green: 0x10 / 255, blue: 0x1F / 255))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                .overlay(NotchLogo(size: Self.tile * 0.5))
                .frame(width: Self.tile, height: Self.tile)
                .rotationEffect(.degrees(-8))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)

            ConnectorIcon(app: connector, size: Self.tile)
                .rotationEffect(.degrees(8))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                // Above the app's tile in the stacking order, which is what
                // makes the overlap read as one on top of the other rather
                // than as two squares that happen to touch.
                .zIndex(1)
        }
        // Room for the rotation and the shadow, which both reach outside the
        // tiles' own frames and were clipped by the column's padding.
        .padding(.vertical, 6)
    }
}
