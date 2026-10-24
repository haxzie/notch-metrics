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
    private let node: URL
    private let script: URL
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

        if let script {
            self.script = script
        } else if let override = ProcessInfo.processInfo.environment["NOTCH_RUNNER_PATH"] {
            self.script = URL(fileURLWithPath: override)
        } else if let bundled = Bundle.main.url(forResource: "runner", withExtension: "mjs") {
            self.script = bundled
        } else {
            throw PluginRunnerError.runnerMissing
        }

        if let node {
            self.node = node
            return
        }
        let searched = NodeLocator.candidates()
        guard let first = searched.first(where: fileExists) else {
            throw PluginRunnerError.nodeMissing(searched: searched.map(\.path))
        }
        self.node = first
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
        process.executableURL = node
        // The script by absolute path, so nothing depends on a working
        // directory or a resolvable `PATH`.
        process.arguments = [script.path, "run", "--dir", plugin.directory.path]
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
        let killed = TimeoutWitness()
        let watchdog = Task {
            try await Task.sleep(for: .seconds(killDeadline))
            // The runner aborts itself on its own signal; this is for the
            // plugin that ignores it — a `while (true)` does not observe an
            // AbortSignal, and only SIGKILL ends it.
            await killed.record()
            if process.isRunning { process.terminate() }
            try await Task.sleep(for: .milliseconds(500))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }

        let out = await outData
        let err = await errData
        // Awaited, not `waitUntilExit()`. That call blocks the thread it is
        // on for as long as the plugin runs — up to twenty seconds — and the
        // threads available to Swift concurrency are a small shared pool.
        // Blocking one to wait on a subprocess is how a handful of slow
        // metrics stall work that has nothing to do with them.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // One-shot, because both arms below can fire. The handler is not
            // called for a process that has *already* exited, so the
            // `isRunning` check is needed — but a process that exits between
            // the two lines runs both, and resuming a continuation twice is a
            // crash rather than a warning.
            let once = ResumeOnce(continuation)
            process.terminationHandler = { _ in once.fire() }
            if !process.isRunning { once.fire() }
        }
        watchdog.cancel()

        appendLog(plugin: plugin.id, stderr: err)

        // Two ways a run times out, and only one of them used to be read.
        //
        // The runner exiting 3 is the polite case: it noticed its own
        // deadline and said so. The other is the plugin that ignored the
        // abort signal and had to be killed — it prints nothing, dies by
        // signal rather than with a status, and so fell through to
        // `unreadableOutput`. A hung metric therefore reported "no output"
        // on the tile while `PluginFailureCode.timeout.shortReason` — the
        // words "Timed out", written for exactly this — went unused.
        if await killed.fired { throw PluginRunnerError.timedOut }

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

/// Whether the watchdog had to kill the run.
///
/// An actor rather than a captured `var` because the watchdog writes it from
/// its own task while `run` reads it from another, which is precisely the
/// data race strict concurrency refuses to compile. It holds one bool and is
/// written at most once.
private actor TimeoutWitness {
    private(set) var fired = false
    func record() { fired = true }
}


/// Resumes a continuation at most once.
///
/// `Process` gives two ways to learn that a subprocess ended and no way to
/// use exactly one of them safely: the termination handler does not fire for
/// a process that already exited, and checking `isRunning` races the handler.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func fire() {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }
}
