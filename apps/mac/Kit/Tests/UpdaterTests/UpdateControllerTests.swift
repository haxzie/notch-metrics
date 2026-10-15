import Foundation
import Testing

import MetricsCore
@testable import Updater

@MainActor
@Suite struct UpdateControllerTests {
    private func controller(_ stub: StubTransport, version: String, build: Int) -> UpdateController {
        UpdateController(
            feed: UpdateFeed(api: apiBase, mirror: mirrorBase, transport: stub.transport),
            runningVersion: version, runningBuild: build)
    }

    /// `upToDate` carries a date, so matching the case is the assertion.
    private func expectUpToDate(_ state: UpdateState, _ comment: Comment = "") {
        if case .upToDate = state { return }
        Issue.record("expected upToDate, got \(state). \(comment)")
    }

    @Test("offers a newer build")
    func offersNewer() async {
        let stub = StubTransport()
        stub.answer(apiURL, status: 200, body: manifestJSON(version: "0.3.0", build: 140))
        let updates = controller(stub, version: "0.2.0", build: 139)

        await updates.check(userInitiated: true)
        #expect(updates.state.manifest?.version == "0.3.0")
    }

    @Test("says nothing is on offer when the build numbers match")
    func sameBuild() async {
        let stub = StubTransport()
        stub.answer(apiURL, status: 200, body: manifestJSON(version: "0.3.0", build: 140))
        let updates = controller(stub, version: "0.3.0", build: 140)

        await updates.check(userInitiated: true)
        expectUpToDate(updates.state)
    }

    /// The bug a semver string comparison produces on the tenth minor release
    /// and never before it: "0.10.0" < "0.9.0" is true for strings. The build
    /// number is what is compared, precisely so this cannot happen.
    @Test("0.10.0 is newer than 0.9.0")
    func tenthMinorRelease() async {
        let stub = StubTransport()
        stub.answer(apiURL, status: 200, body: manifestJSON(version: "0.10.0", build: 201))
        let updates = controller(stub, version: "0.9.0", build: 200)

        await updates.check(userInitiated: true)
        #expect(updates.state.manifest?.version == "0.10.0")
    }

    @Test("never offers an older build, whatever the feed says")
    func refusesADowngrade() async {
        let stub = StubTransport()
        stub.answer(apiURL, status: 200, body: manifestJSON(version: "0.2.0", build: 139))
        let updates = controller(stub, version: "0.3.0", build: 140)

        await updates.check(userInitiated: true)
        expectUpToDate(updates.state)
    }

    /// Not a failure state. This Mac is not the audience for the build, and
    /// "update failed" is a message its owner cannot act on.
    @Test("a build this Mac cannot run reads as up to date, not as an error")
    func unsupportedIsNotAFailure() async {
        let stub = StubTransport()
        stub.answer(
            apiURL, status: 200,
            body: manifestJSON(version: "0.3.0", build: 140, minimum: "99.0"))
        let updates = controller(stub, version: "0.2.0", build: 139)

        await updates.check(userInitiated: true)
        expectUpToDate(updates.state)
    }

    @Test("an unreachable feed says so in words somebody can act on")
    func reportsAnOutage() async {
        let stub = StubTransport()
        stub.fail(apiURL)
        stub.fail(mirrorURL)
        let updates = controller(stub, version: "0.2.0", build: 139)

        await updates.check(userInitiated: true)
        guard case let .failed(message) = updates.state else {
            Issue.record("expected failed, got \(updates.state)")
            return
        }
        #expect(message.contains("connection"))
    }

    @Test("a check with no release published yet is up to date")
    func noReleaseYet() async {
        let stub = StubTransport()
        stub.answer(apiURL, status: 404, body: #"{"code":"NOT_FOUND"}"#)
        let updates = controller(stub, version: "0.2.0", build: 139)

        await updates.check(userInitiated: true)
        expectUpToDate(updates.state)
    }
}
