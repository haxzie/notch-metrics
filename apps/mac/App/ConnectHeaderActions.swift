import MetricsCore
import NotchUI
import SwiftUI

/// Connect and Cancel for the credentials pane, drawn in the notch's header.
///
/// In the header rather than under the form because that is where every
/// other pane puts its commit and its way out — Done and Cancel for the
/// configure pane, Back for the browser — and a form whose buttons are
/// somewhere else reads as a different kind of screen. It also takes Edit
/// Widgets out of the header while this pane is up, which is worth losing:
/// there is nothing behind the form to arrange, and rearranging the grid
/// would throw away a half-typed key.
struct ConnectHeaderActions: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var model: ConnectModel

    var body: some View {
        // Nothing to commit or cancel until the catalogue has answered: the
        // pane is showing a spinner or its own Close, and two ways out of a
        // pane with nothing in it is one too many.
        if model.connector != nil {
            cancel
            connect
        }
    }

    private var cancel: some View {
        Button {
            if let id = model.connector?.id { env.discardConnectModel(for: id) }
            env.notch.endConnecting()
        } label: {
            HStack(spacing: 4) {
                // The chevron says where the button goes; "Cancel" says what
                // it does to what has been typed. Both, because leaving the
                // pane and discarding the key are one action here.
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("Cancel")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(NotchTheme.secondaryText)
        .keyboardShortcut(.cancelAction)
        .help("Do not connect this account")
    }

    private var connect: some View {
        Button {
            Task {
                guard await model.connect(env: env) else { return }
                if let id = model.connector?.id { env.discardConnectModel(for: id) }
                env.notch.endConnecting()
            }
        } label: {
            HStack(spacing: 5) {
                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                        .frame(width: 11, height: 11)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                Text(model.isWorking ? "Checking…" : "Connect")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // The same blue capsule the configure pane's Done wears. Not
            // `.borderedProminent`, which takes the accent colour the user
            // set in System Settings and would make this the one control in
            // the header that does not match the rest.
            .background(
                Capsule().fill(
                    NotchTheme.editHighlight.opacity(model.canConnect ? 0.9 : 0.35)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        // Disabled on an incomplete form rather than failing on submit: a
        // required field left empty is the one mistake the form can see for
        // itself.
        .disabled(!model.canConnect)
        .keyboardShortcut(.defaultAction)
        .help("Check these credentials and save them")
    }
}
