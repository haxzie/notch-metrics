import Foundation
import Testing

import MetricsCore
@testable import Updater

@Suite struct UpdateFeedTests {
    private func feed(_ stub: StubTransport) -> UpdateFeed {
        UpdateFeed(api: apiBase, mirror: mirrorBase, transport: stub.transport)
    }

    @Test("reads the release from the Worker")
    func readsTheWorker() async throws {
        let stub = StubTransport()
        stub.answer(apiURL, status: 200, body: manifestJSON())

        let manifest = try #require(await feed(stub).latest())
        #expect(manifest.version == "0.3.0")
        #expect(manifest.build == 140)
        #expect(stub.requested == [apiURL])
    }

    /// The one that matters. `PINNED_VERSION` makes the Worker answer 404, and
    /// a fallback to the bucket on a 404 would hand every client the build the
    /// rollback just withheld.
    @Test("a 404 from the Worker is an answer, not a reason to read the bucket")
    func doesNotRouteAroundARollback() async throws {
        let stub = StubTransport()
        stub.answer(apiURL, status: 404, body: #"{"code":"NOT_FOUND"}"#)
        stub.answer(mirrorURL, status: 200, body: manifestJSON(version: "9.9.9", build: 999))

        #expect(try await feed(stub).latest() == nil)
        #expect(stub.requested == [apiURL])
    }

    @Test("falls back to the bucket when the Worker is unreachable")
    func fallsBackOnAnOutage() async throws {
        let stub = StubTransport()
        stub.fail(apiURL)
        stub.answer(mirrorURL, status: 200, body: manifestJSON())

        let manifest = try #require(await feed(stub).latest())
        #expect(manifest.version == "0.3.0")
        #expect(stub.requested == [apiURL, mirrorURL])
    }

    @Test("falls back on a 5xx too")
    func fallsBackOnAServerError() async throws {
        let stub = StubTransport()
        stub.answer(apiURL, status: 502, body: #"{"code":"BAD_MANIFEST"}"#)
        stub.answer(mirrorURL, status: 200, body: manifestJSON())

        _ = try #require(await feed(stub).latest())
        #expect(stub.requested == [apiURL, mirrorURL])
    }

    /// A manifest that does not decode must not send us to fetch the same bad
    /// manifest from the other place it is published.
    @Test("a manifest that does not decode throws instead of falling back")
    func doesNotFallBackOnGarbage() async {
        let stub = StubTransport()
        stub.answer(apiURL, status: 200, body: #"{"version":"0.3.0"}"#)
        stub.answer(mirrorURL, status: 200, body: manifestJSON())

        await #expect(throws: UpdateFeedError.self) { try await feed(stub).latest() }
        #expect(stub.requested == [apiURL])
    }
}

@Suite struct ManifestSupportTests {
    private func manifest(minimum: String, platform: String = "darwin-arm64") throws -> LatestManifest {
        let text = manifestJSON(minimum: minimum)
            .replacingOccurrences(of: "darwin-arm64", with: platform)
        return try JSONDecoder().decode(LatestManifest.self, from: Data(text.utf8))
    }

    @Test("a build needing a newer macOS is not offered")
    func respectsTheMinimum() throws {
        let sonoma = OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 0)
        #expect(try manifest(minimum: "14.0").isSupported(by: sonoma))
        #expect(try manifest(minimum: "15.0").isSupported(by: sonoma) == false)
    }

    @Test("an Intel build is never offered")
    func refusesAnotherPlatform() throws {
        let sequoia = OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        #expect(try manifest(minimum: "14.0", platform: "darwin-x86_64").isSupported(by: sequoia) == false)
    }
}
