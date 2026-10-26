import Foundation
import MetricsCore

public enum PluginRunnerError: Error, Sendable, Equatable {
    /// The bundled runner script is missing — a damaged or hand-assembled
    /// bundle.
    case runnerMissing
    /// No Node on this machine, or none new enough. Distinct from
    /// `runnerMissing` because the remedy is the user's, not ours: this is the
    /// one failure here that a person can actually fix.
    case nodeMissing(searched: [String])
    case nodeTooOld(path: String, version: String)
    case spawnFailed(String)
    case timedOut
    case unreadableOutput(String)
    case failed(PluginFailureCode, String)
}

/// Spawns the runner, one invocation per metric.
///
/// The runner is an esbuild bundle — one `.mjs`, about 800 KB — executed with
/// Node from the user's own machine. It used to be a self-contained Bun
/// executable, which needed no Node at all; that was 61 MB against a 16 MB
/// app, so the trade was reversed. See `packages/metric-runtime/build.mjs`.
///
/// What that costs is `NodeLocator`. A GUI app launched from Finder inherits
/// no shell `PATH`, and stock macOS has no `/usr/bin/node` — so the users most
/// likely to have Node are the ones whose Node this process cannot see. The
/// locator exists entirely to close that gap, and it is why a bare
/// `Process()` on `"node"` would appear to work in development and fail for
/// everyone who launches the app normally.
public struct PluginRunner: Sendable {
    private let tools: RunnerTools
    private let secrets: any SecretStore

    /// - Parameters:
    ///   - node: an explicit interpreter, for the tests. Otherwise located.
    ///   - script: an explicit runner bundle, for the tests. Otherwise
    ///     `NOTCH_RUNNER_PATH`, then the copy inside the app bundle.
    public init(
        secrets: any SecretStore,
        node: URL? = nil,
        script: URL? = nil,
        fileExists: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) throws {
        self.secrets = secrets
        self.tools = try RunnerTools(node: node, script: script, fileExists: fileExists)
    }

    public func run(_ plugin: LoadedPlugin) async throws -> PluginValue {
        guard let manifest = plugin.manifest else {
            throw PluginRunnerError.failed(.manifest, "This metric has no usable manifest.")
        }

        var declared: [String: String] = [:]
        for secret in manifest.secrets {
            if let value = try? secrets.string(for: .plugin(plugin.id, secret.key)) {
                declared[secret.key] = value
            }
        }

        let output = try await RunnerProcess.run(
            tools: tools,
            arguments: ["run", "--dir", plugin.directory.path],
            workingDirectory: plugin.directory,
            input: try JSONEncoder().encode(["secrets": declared]),
            // Two seconds of grace over the manifest's own deadline, so the
            // runner gets to report its timeout politely before being killed.
            killAfter: Double(manifest.timeoutMs) / 1000 + 2.0)

        RunnerProcess.appendLog(id: plugin.id, stderr: output.stderr)

        // Two ways a run times out, and only one of them used to be read.
        //
        // The runner exiting 3 is the polite case: it noticed its own
        // deadline and said so. The other is the plugin that ignored the
        // abort signal and had to be killed — it prints nothing, dies by
        // signal rather than with a status, and so fell through to
        // `unreadableOutput`. A hung metric therefore reported "no output"
        // on the tile while `PluginFailureCode.timeout.shortReason` — the
        // words "Timed out", written for exactly this — went unused.
        if output.killed { throw PluginRunnerError.timedOut }
        guard output.status != PluginExit.timeout else { throw PluginRunnerError.timedOut }

        guard let line = output.firstLine,
            let result = try? JSONDecoder().decode(PluginRunResult.self, from: Data(line.utf8))
        else {
            throw PluginRunnerError.unreadableOutput(output.errorTail)
        }

        switch result {
        case let .success(value, _, _, _):
            return value
        case let .failure(code, message, _, _, _):
            throw PluginRunnerError.failed(code, message)
        }
    }

}
