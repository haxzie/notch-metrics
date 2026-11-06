import MetricsAPI
import MetricsCore
import Providers
import SwiftUI

/// The state behind `ConnectIntegrationPane`.
///
/// Holds the typed values, checks them against the manifest, verifies them
/// against the provider, and only then writes anything down. That order is
/// the point: the Worker's connect route has always verified before it
/// inserted a row, and a local form that stored first would leave people with
/// a connection that looks made and answers nothing.
@MainActor
@Observable
final class ConnectModel {
    enum State {
        case loading
        case ready(ConnectorEntry)
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var isWorking = false
    /// What went wrong, shown under the form. Never a credential: the
    /// provider's message is passed through, and `ProviderFailure` carries
    /// only what the provider said about the request.
    private(set) var failureMessage: String?

    /// Typed values, by field key. In memory only until a verify succeeds.
    private var values: [String: String] = [:]
    /// Fields the user has touched and left invalid, so the form does not
    /// scold somebody about a key they have not finished typing.
    private var touched: Set<String> = []

    func load(_ connectorId: String, env: AppEnvironment) async {
        guard case .loading = state else { return }
        do {
            let catalogue = try await env.catalogue()
            guard let connector = catalogue.allConnectors.first(where: { $0.id == connectorId })
            else {
                state = .failed("This build does not know about \(connectorId).")
                return
            }
            // Defaults the manifest declared, so a `select` opens on something
            // rather than on an empty row the user has to discover is a menu.
            for field in connector.fields {
                if let preset = field.default, !preset.isEmpty { values[field.key] = preset }
            }
            state = .ready(connector)
        } catch {
            state = .failed("Could not load \(connectorId): \(error.localizedDescription)")
        }
    }

    /// The connector once the catalogue has answered.
    ///
    /// Exposed because the pane no longer owns the buttons: Connect and
    /// Cancel moved into the notch's header, which is a different view over
    /// the same model, and it cannot pattern-match `state` from there.
    var connector: ConnectorEntry? {
        if case .ready(let connector) = state { return connector }
        return nil
    }

    /// Whether Connect can be pressed right now.
    var canConnect: Bool {
        guard let connector, !isWorking else { return false }
        return isComplete(connector)
    }

    func binding(for field: AuthField) -> Binding<String> {
        Binding(
            get: { self.values[field.key] ?? "" },
            set: { newValue in
                // An unchanged value is not an edit. SwiftUI writes the
                // current contents back through the binding when a field
                // takes or loses focus, so without this guard simply
                // clicking into an empty required field marked it touched
                // and answered with "Required." before a key was pressed.
                guard newValue != (self.values[field.key] ?? "") else { return }
                self.values[field.key] = newValue
                self.touched.insert(field.key)
                // The last failure was about the old value. Leaving it up
                // while somebody corrects the field reads as a form that has
                // stopped responding.
                self.failureMessage = nil
            })
    }

    /// Why this field is not acceptable yet, once it has been touched.
    func problem(for field: AuthField) -> String? {
        guard touched.contains(field.key) else { return nil }
        let value = trimmed(field.key)
        if value.isEmpty { return field.required ? "Required." : nil }
        guard let pattern = field.pattern, !pattern.isEmpty else { return nil }
        return matches(value, pattern) ? nil : "That does not look right."
    }

    /// Whether Connect can be pressed.
    ///
    /// Required fields present and every pattern satisfied. The pattern is a
    /// hint the manifest supplies for exactly this: catching a mistyped key
    /// here costs nothing, where sending it costs a round trip to the
    /// provider and comes back as "invalid API key", which reads as the key
    /// being wrong rather than mistyped.
    func isComplete(_ connector: ConnectorEntry) -> Bool {
        connector.fields.allSatisfy { field in
            let value = trimmed(field.key)
            if value.isEmpty { return !field.required }
            guard let pattern = field.pattern, !pattern.isEmpty else { return true }
            return matches(value, pattern)
        }
    }

    /// Verifies, then stores, using the connector this model was loaded for.
    func connect(env: AppEnvironment) async -> Bool {
        guard let connector else { return false }
        return await connect(connector, env: env)
    }

    /// Verifies, then stores. Returns true when the connection was made.
    func connect(_ connector: ConnectorEntry, env: AppEnvironment) async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        failureMessage = nil
        defer { isWorking = false }

        // Trimmed once, here. A key pasted with a trailing newline is the
        // single most common way a correct credential is rejected.
        let credentials = connector.fields.reduce(into: [String: String]()) { out, field in
            let value = trimmed(field.key)
            if !value.isEmpty { out[field.key] = value }
        }

        do {
            let account = try await ProviderRegistry.verify(connector.id, credentials: credentials)
            try await env.storeConnection(
                provider: connector.id, credentials: credentials, account: account)
            return true
        } catch let failure as ProviderFailure {
            failureMessage = failure.message
            return false
        } catch {
            failureMessage = error.localizedDescription
            return false
        }
    }

    /// The mark and colour for the header, with the server's name and colour
    /// winning over the built-in entry — so a connector added after this build
    /// still renders correctly.
    func app(for connector: ConnectorEntry) -> MetricApp {
        AppCatalog.resolve(
            connector.id,
            overrides: [
                connector.id: MetricApp(
                    id: connector.id,
                    name: connector.name,
                    symbol: AppCatalog.resolve(connector.id).symbol,
                    accentHex: connector.accentColor.replacingOccurrences(of: "#", with: ""))
            ])
    }

    private func trimmed(_ key: String) -> String {
        (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whole-string match, like the HTML `pattern` attribute the manifests are
    /// written against.
    ///
    /// Anchored here rather than trusted to anchor itself.
    /// `NSRegularExpression` matches anywhere in the string by default, so a
    /// manifest that wrote `sk_[A-Za-z0-9]+` without the `^` and `$` would
    /// accept a key with anything in front of it. Every manifest today does
    /// anchor, and wrapping one that already has is harmless — `^` and `$`
    /// are zero-width.
    private func matches(_ value: String, _ pattern: String) -> Bool {
        let anchored = "^(?:\(pattern))$"
        guard let regex = try? NSRegularExpression(pattern: anchored) else {
            // An unreadable pattern must not block a real key. It is a hint
            // from a server this build may be older than, not a rule.
            return true
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }
}
