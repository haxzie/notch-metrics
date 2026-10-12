import Foundation
import Testing

@testable import MetricsCore

@Suite("LogFile")
struct LogFileTests {
    private func scratch() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("logfile-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("writes a line that carries its category and survives a reopen")
    func appends() async throws {
        let directory = scratch()
        let log = LogFile(directory: directory)
        await log.write("api", "GET v1/metrics/batch → 200")
        await log.write("metric", "openai/tokens 7d → bad_response")

        let file = URL(fileURLWithPath: log.todayPath)
        let text = try String(contentsOf: file, encoding: .utf8)
        #expect(text.contains("[api] GET v1/metrics/batch → 200"))
        #expect(text.contains("[metric] openai/tokens 7d → bad_response"))
        // Two lines, not one overwriting the other.
        #expect(text.split(separator: "\n").count == 2)
    }

    @Test("a second logger appends rather than truncating")
    func appendsAcrossInstances() async throws {
        let directory = scratch()
        await LogFile(directory: directory).write("app", "first run")
        let second = LogFile(directory: directory)
        await second.write("app", "second run")

        let text = try String(contentsOf: URL(fileURLWithPath: second.todayPath), encoding: .utf8)
        #expect(text.contains("first run"))
        #expect(text.contains("second run"))
    }

    @Test("drops files past the window and keeps the recent ones")
    func prunes() async throws {
        let directory = scratch()
        let stale = directory.appendingPathComponent("app-2020-01-01.log")
        FileManager.default.createFile(atPath: stale.path, contents: Data("old\n".utf8))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: stale.path)

        let log = LogFile(directory: directory)
        await log.write("app", "today")

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(FileManager.default.fileExists(atPath: log.todayPath))
    }

    /// A log is the artefact somebody pastes into a chat window. One leaked
    /// key is worse than every diagnostic this file will ever provide.
    @Test("blanks anything shaped like a credential")
    func redacts() {
        #expect(!LogFile.redacted("Bearer abc.def-123").contains("abc.def-123"))
        #expect(!LogFile.redacted("key sk-ant-admin01-secretvalue").contains("secretvalue"))
        #expect(!LogFile.redacted("?api_key=hunter2&range=7d").contains("hunter2"))
        // And leaves the part worth reading.
        #expect(LogFile.redacted("?api_key=hunter2&range=7d").contains("range=7d"))
    }
}
