import Foundation
import MetricsCore

public enum PluginRunnerError: Error, Sendable, Equatable {
    /// The embedded binary is missing — a damaged or hand-assembled bundle.
    case runnerMissing
    case spawnFailed(String)
    case timedOut
    case unreadableOutput(String)
    case failed(PluginFailureCode, String)
}

/// Spawns the embedded runner, one invocation per metric.
///
/// The runner is a single compiled binary inside the app bundle, so custom
/// metrics work on a machine with no Node and no Bun installed. That matters
/// more than it sounds: a GUI app launched from Finder inherits no shell PATH,
/// so even a user who *has* Node often has one this process cannot find.
public struct PluginRunner: Sendable {
    private let executable: URL
    private let secrets: any SecretStore

    public init(secrets: any SecretStore, executable: URL? = nil) throws {
        self.secrets = secrets
        if let executable {
            self.executable = executable
        } else if let override = ProcessInfo.processInfo.environment["NOTCH_RUNNER_PATH"] {
            self.executable = URL(fileURLWithPath: override)
        } else if let bundled = Bundle.main.url(
            forResource: "notch-metric-runner", withExtension: nil, subdirectory: "bin")
        {
            self.executable = bundled
        } else {
            throw PluginRunnerError.runnerMissing
        }
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

        let process = Process()
        process.executableURL = executable
        process.arguments = ["run", "--dir", plugin.directory.path]
        process.currentDirectoryURL = plugin.directory

        // A minimal environment. Anything inherited here is also inherited by
        // whatever the plugin spawns, and is dumped verbatim by most crash
        // reporters — so the user's shell environment, with whatever is in it,
        // stays out of this process entirely.
        process.environment = [
            "PATH": "/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
            "TZ": TimeZone.current.identifier,
        ]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw PluginRunnerError.spawnFailed(error.localizedDescription)
        }

        // Secrets go in on stdin and the stream is closed. Not argv, which is
        // world-readable through `ps`; not the environment, for the reason
        // above. Closing matters: the runner blocks until the stream ends.
        let payload = try JSONEncoder().encode(["secrets": declared])
        stdin.fileHandleForWriting.write(payload)
        try? stdin.fileHandleForWriting.close()

        // Both pipes are drained concurrently with the wait. Reading one to
        // completion first is the classic deadlock: a plugin that logs more
        // than the 64 KB pipe buffer blocks on stderr forever while we block
        // on stdout.
        async let outData = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }.value
        async let errData = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }.value

        let killDeadline = Double(manifest.timeoutMs) / 1000 + 2.0
        let watchdog = Task {
            try await Task.sleep(for: .seconds(killDeadline))
            // The runner aborts itself on its own signal; this is for the
            // plugin that ignores it — a `while (true)` does not observe an
            // AbortSignal, and only SIGKILL ends it.
            if process.isRunning { process.terminate() }
            try await Task.sleep(for: .milliseconds(500))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }

        let out = await outData
        let err = await errData
        process.waitUntilExit()
        watchdog.cancel()

        appendLog(plugin: plugin.id, stderr: err)

        guard process.terminationStatus != PluginExit.timeout else {
            throw PluginRunnerError.timedOut
        }

        guard let line = String(data: out, encoding: .utf8)?
            .split(separator: "\n").first.map(String.init),
            let result = try? JSONDecoder().decode(
                PluginRunResult.self, from: Data(line.utf8))
        else {
            throw PluginRunnerError.unreadableOutput(
                String(data: err, encoding: .utf8)?.suffix(500).description ?? "no output")
        }

        switch result {
        case let .success(value, _, _, _):
            return value
        case let .failure(code, message, _, _, _):
            throw PluginRunnerError.failed(code, message)
        }
    }

    /// Keeps the last 200 lines, which is what the Settings pane shows and what
    /// a user pastes back into their agent to get the metric fixed.
    private func appendLog(plugin id: String, stderr: Data) {
        guard !stderr.isEmpty,
              let text = String(data: stderr, encoding: .utf8)
        else { return }

        let url = AppPaths.pluginLogs.appendingPathComponent("\(id).log")
        try? FileManager.default.createDirectory(
            at: AppPaths.pluginLogs, withIntermediateDirectories: true)

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lines = (existing + text).split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.suffix(200).joined(separator: "\n")
        try? kept.write(to: url, atomically: true, encoding: .utf8)
    }
}
