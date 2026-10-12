import Foundation
import OSLog

/// An append-only log on disk, next to the app's other state.
///
/// `os.Logger` is still the primary channel and nothing here replaces it —
/// but reading it means Console.app or `log stream --predicate …`, and the
/// one thing you cannot do with it is ask somebody to send you the last
/// hour. A plain file can be tailed, grepped and attached to a message,
/// which is the difference between diagnosing a provider that only misbehaves
/// on one person's account and guessing at it.
///
/// An actor because every call site is already async and the alternative is a
/// lock around a file handle. Writes are serialised and ordered; nothing here
/// is on a path where a few microseconds matter.
public actor LogFile {
    public static let shared = LogFile()

    /// Kept deliberately small. This is a diagnostic aid, not an audit trail,
    /// and a logger with no bound is a disk filling up on a machine whose
    /// owner never asked for it.
    private static let keepDays = 5
    private static let maxBytes = 2 * 1024 * 1024

    private let directory: URL
    private var handle: FileHandle?
    private var openedFor: String?

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        // Fixed locale and zone: a log read by somebody in another zone is
        // being compared against a server log that is always UTC.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public init(directory: URL = AppPaths.logs) {
        self.directory = directory
    }

    /// Where to tell somebody to look.
    public nonisolated var todayPath: String {
        directory.appendingPathComponent("app-\(Self.day.string(from: Date())).log").path
    }

    /// One line, with a UTC timestamp and a category.
    ///
    /// Never pass a credential. Callers are expected to have redacted
    /// already — `redacted(_:)` is here for the cases where a token could
    /// reach a message by accident, such as a URL somebody put one in.
    public func write(_ category: String, _ message: String) {
        let line = "\(Self.stamp.string(from: Date()))  [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            let handle = try handleForToday()
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // A logger that throws is a logger that takes the app down over
            // a full disk. The unified log still has the line.
            Log.api.error("log file write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Rotates on the date rather than on a timer, so a file is one day and
    /// its name says which.
    private func handleForToday() throws -> FileHandle {
        let today = Self.day.string(from: Date())
        if let handle, openedFor == today { return handle }

        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("app-\(today).log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        try? handle?.close()
        let opened = try FileHandle(forWritingTo: url)
        handle = opened
        openedFor = today
        prune()
        return opened
    }

    /// Drops files past the window, and truncates today's if a loop has run
    /// away with it — a day's worth of a retry storm should not be the reason
    /// somebody cannot open their log.
    private func prune() {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }

        let cutoff = Date().addingTimeInterval(-Double(Self.keepDays) * 86_400)
        for file in files where file.lastPathComponent.hasPrefix("app-") {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified < cutoff { try? manager.removeItem(at: file) }
        }

        let url = directory.appendingPathComponent("app-\(Self.day.string(from: Date())).log")
        let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if size > Self.maxBytes {
            try? handle?.truncate(atOffset: 0)
        }
    }

    /// Blanks anything that looks like a bearer token or a provider key.
    ///
    /// Belt and braces. Nothing is supposed to hand a credential to a logger,
    /// but a log is exactly the artefact somebody pastes into a chat, and one
    /// leaked key is worse than every diagnostic this file will ever provide.
    public nonisolated static func redacted(_ text: String) -> String {
        var out = text
        for pattern in [
            #"Bearer\s+[A-Za-z0-9._\-]+"#,
            #"sk-[A-Za-z0-9._\-]{8,}"#,
            #"(?i)(api[_-]?key|token|secret)=([^&\s]+)"#,
        ] {
            out = out.replacingOccurrences(
                of: pattern, with: "«redacted»", options: .regularExpression)
        }
        return out
    }
}
