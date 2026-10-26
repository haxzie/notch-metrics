import Foundation
import MetricsCore

/// Locating the runner and the Node to execute it with.
///
/// Shared by `PluginRunner` and `ConnectorRunner`. Both need the same two
/// paths resolved the same way, and a second copy of this is a second place
/// for `NOTCH_RUNNER_PATH` to be read slightly differently.
public struct RunnerTools: Sendable {
    public let node: URL
    public let script: URL

    public init(
        node: URL? = nil,
        script: URL? = nil,
        fileExists: (URL) -> Bool = { FileManager.default.isExecutableFile(atPath: $0.path) }
    ) throws {
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
}

/// What one runner invocation produced.
public struct RunnerOutput: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let status: Int32
    /// True when the watchdog had to kill it rather than it exiting on its own.
    public let killed: Bool

    /// The first line of stdout, which is the runner's whole contract.
    public var firstLine: String? {
        String(data: stdout, encoding: .utf8)?.split(separator: "\n").first.map(String.init)
    }

    /// The tail of stderr, for an error message a user can act on.
    public var errorTail: String {
        String(data: stderr, encoding: .utf8)?.suffix(500).description ?? "no output"
    }
}

/// Spawning the runner and getting its answer back without deadlocking.
///
/// Extracted from `PluginRunner` when connectors needed the identical dance.
/// It is worth one shared implementation rather than two similar ones,
/// because every line here is load-bearing against a specific failure:
///
/// - Both pipes are drained **concurrently** with the wait. Reading one to
///   completion first is the classic deadlock: a plugin logging more than the
///   64 KB pipe buffer blocks on stderr for ever while we block on stdout.
/// - The exit is awaited through a continuation, never `waitUntilExit()`,
///   which blocks its thread for the whole run. Swift concurrency's thread
///   pool is small, so blocking one to watch a subprocess is how a few slow
///   metrics stall work unrelated to them.
/// - The watchdog escalates `terminate()` to `SIGKILL`, because a `while
///   (true)` does not observe an AbortSignal and nothing else ends it.
public enum RunnerProcess {
    /// - Parameters:
    ///   - arguments: everything after the interpreter and the script path.
    ///   - input: written to stdin and the stream then closed. The runner
    ///     blocks until the stream ends, so the close is not optional.
    ///   - killAfter: the deadline, already including whatever grace the
    ///     caller wants over the manifest's own timeout.
    public static func run(
        tools: RunnerTools,
        arguments: [String],
        workingDirectory: URL,
        input: Data,
        killAfter: TimeInterval
    ) async throws -> RunnerOutput {
        let process = Process()
        process.executableURL = tools.node
        // The script by absolute path, so nothing depends on a working
        // directory or a resolvable `PATH`.
        process.arguments = [tools.script.path] + arguments
        process.currentDirectoryURL = workingDirectory

        // A minimal environment. Anything inherited here is also inherited by
        // whatever the connector spawns, and is dumped verbatim by most crash
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

        // Credentials go in on stdin, never argv — which is world-readable
        // through `ps` — and never the environment, for the reason above.
        stdin.fileHandleForWriting.write(input)
        try? stdin.fileHandleForWriting.close()

        async let outData = Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }.value
        async let errData = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }.value

        let killed = TimeoutWitness()
        let watchdog = Task {
            try await Task.sleep(for: .seconds(killAfter))
            await killed.record()
            if process.isRunning { process.terminate() }
            try await Task.sleep(for: .milliseconds(500))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }

        let out = await outData
        let err = await errData

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

        return RunnerOutput(
            stdout: out, stderr: err, status: process.terminationStatus,
            killed: await killed.fired)
    }

    /// Keeps the last 200 lines, which is what a user pastes back into their
    /// agent to get the thing fixed.
    public static func appendLog(id: String, stderr: Data) {
        guard !stderr.isEmpty, let text = String(data: stderr, encoding: .utf8) else { return }

        let url = AppPaths.pluginLogs.appendingPathComponent("\(id).log")
        try? FileManager.default.createDirectory(
            at: AppPaths.pluginLogs, withIntermediateDirectories: true)

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let lines = (existing + text).split(separator: "\n", omittingEmptySubsequences: false)
        try? lines.suffix(200).joined(separator: "\n")
            .write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Whether the watchdog had to kill the run.
///
/// An actor rather than a captured `var` because the watchdog writes it from
/// its own task while the caller reads it from another, which is precisely the
/// data race strict concurrency refuses to compile. It holds one bool and is
/// written at most once.
actor TimeoutWitness {
    private(set) var fired = false
    func record() { fired = true }
}

/// Resumes a continuation at most once.
///
/// `Process` gives two ways to learn that a subprocess ended and no way to
/// use exactly one of them safely: the termination handler does not fire for
/// a process that already exited, and checking `isRunning` races the handler.
final class ResumeOnce: @unchecked Sendable {
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
