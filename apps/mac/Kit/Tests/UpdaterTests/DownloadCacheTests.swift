import Foundation
import Testing

import MetricsCore
@testable import Updater

/// The on-disk half of the updater: what survives a relaunch, what is thrown
/// away, and what a corrupted download does.
///
/// Real files in a real directory rather than a mock filesystem. The claims
/// under test are claims about `FileManager` and about the hash of actual
/// bytes, and a mock can make neither of them.
@MainActor
@Suite struct DownloadCacheTests {
    private func temporaryDownloads() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("notch-updater-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ bytes: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(bytes.utf8).write(to: url)
    }

    private func controller(
        _ stub: StubTransport, version: String, build: Int, downloads: URL
    ) -> UpdateController {
        UpdateController(
            feed: UpdateFeed(api: apiBase, mirror: mirrorBase, transport: stub.transport),
            runningVersion: version, runningBuild: build, downloads: downloads)
    }

    @Test("the hash gate rejects a download that does not match the manifest")
    func rejectsACorruptedDownload() throws {
        let root = try temporaryDownloads()
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("image.dmg")
        try write("the bytes that actually arrived", to: file)
        let expected = try SignatureVerifier.sha256(of: file)

        #expect(throws: Never.self) {
            try SignatureVerifier.verifyHash(of: file, expected: expected)
        }

        // One byte different is the whole point: a truncated or tampered image
        // must not reach the mount.
        try write("the bytes that actually arrivee", to: file)
        #expect(throws: VerificationError.self) {
            try SignatureVerifier.verifyHash(of: file, expected: expected)
        }
    }

    @Test("a download for a version no longer on offer is deleted")
    func prunesAnAbandonedDownload() async throws {
        let root = try temporaryDownloads()
        defer { try? FileManager.default.removeItem(at: root) }

        try write("old", to: root.appendingPathComponent("0.2.0/old.dmg"))
        try write("new", to: root.appendingPathComponent("0.3.0/new.dmg"))

        let stub = StubTransport()
        stub.answer(apiURL, status: 200, body: manifestJSON(version: "0.3.0", build: 140))
        await controller(stub, version: "0.2.0", build: 139, downloads: root)
            .check(userInitiated: true)

        let left = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        ).map(\.lastPathComponent).sorted()
        #expect(left == ["0.3.0"])
    }

    /// The leak this closes: the helper cleans its own staging directory, but
    /// the image the install started from belongs to the app, and the app has
    /// quit by then.
    @Test("the previous release's disk image does not survive an update")
    func prunesAfterAnUpdateHasLanded() async throws {
        let root = try temporaryDownloads()
        defer { try? FileManager.default.removeItem(at: root) }

        try write("installed from this", to: root.appendingPathComponent("0.3.0/image.dmg"))

        // The state the app comes back up in: running the version it just
        // installed, with nothing newer on offer.
        let stub = StubTransport()
        stub.answer(apiURL, status: 200, body: manifestJSON(version: "0.3.0", build: 140))
        await controller(stub, version: "0.3.0", build: 140, downloads: root)
            .check(userInitiated: true)

        let left = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)
        #expect(left.isEmpty)
    }

    /// Resuming matters: quitting during a download must not mean fetching
    /// eighteen megabytes again.
    @Test("a verified download already on disk is offered for install, not fetched again")
    func reusesAVerifiedDownload() async throws {
        let root = try temporaryDownloads()
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("0.3.0/NotchMetrics-0.3.0-arm64.dmg")
        try write("pretend this is a disk image", to: file)
        let sha = try SignatureVerifier.sha256(of: file)

        let stub = StubTransport()
        stub.answer(
            apiURL, status: 200,
            body: manifestJSON(version: "0.3.0", build: 140)
                .replacingOccurrences(of: String(repeating: "a", count: 64), with: sha))
        let updates = controller(stub, version: "0.2.0", build: 139, downloads: root)

        await updates.check(userInitiated: true)
        guard case let .readyToInstall(_, url) = updates.state else {
            Issue.record("expected readyToInstall, got \(updates.state)")
            return
        }
        #expect(url == file)
    }

    /// A half-written file from an interrupted download has exactly the right
    /// name, so the name alone must not be trusted.
    @Test("a half-written download with the right name is thrown away, not offered")
    func discardsATruncatedDownload() async throws {
        let root = try temporaryDownloads()
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("0.3.0/NotchMetrics-0.3.0-arm64.dmg")
        try write("only half of it arrived", to: file)

        let stub = StubTransport()
        stub.answer(apiURL, status: 200, body: manifestJSON(version: "0.3.0", build: 140))
        let updates = controller(stub, version: "0.2.0", build: 139, downloads: root)

        await updates.check(userInitiated: true)
        if case .available = updates.state {} else {
            Issue.record("expected available, got \(updates.state)")
        }
        #expect(FileManager.default.fileExists(atPath: file.path) == false)
    }
}
