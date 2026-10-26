import Foundation
import MetricsCore
import Testing

@testable import PluginRuntime

/// Removing an installed app.
///
/// The deletion itself is one line; what it must *not* delete is the part
/// worth pinning. `install` copies rather than moves precisely so that
/// removing an app cannot take somebody's project with it.
struct ConnectorRemovalTests {
    @MainActor
    @Test("removing deletes the installed copy")
    func removesTheInstalledCopy() throws {
        let source = try ConnectorImportTests.temporaryRoot("src")
        let root = try ConnectorImportTests.temporaryRoot("root")
        try ConnectorImport.install(from: try ConnectorImportTests.makeSource(in: source), into: root)
        #expect(ConnectorRegistry.scan(root: root, approved: [:]).count == 1)

        try ConnectorImport.remove(id: "linear", from: root)
        #expect(ConnectorRegistry.scan(root: root, approved: [:]).isEmpty)
    }

    @Test("removing leaves the folder it was built from alone")
    func sourceSurvivesRemoval() throws {
        let source = try ConnectorImportTests.temporaryRoot("src")
        let root = try ConnectorImportTests.temporaryRoot("root")
        let project = try ConnectorImportTests.makeSource(in: source)
        try ConnectorImport.install(from: project, into: root)

        try ConnectorImport.remove(id: "linear", from: root)
        // The whole reason `install` copies. Someone who loaded an app from
        // their own checkout must not lose it by removing the app.
        #expect(
            FileManager.default.fileExists(
                atPath: project.appendingPathComponent("manifest.json").path))
    }

    @Test("removing something already gone is not an error")
    func removingTwiceIsFine() throws {
        let root = try ConnectorImportTests.temporaryRoot("root")
        // Reachable by clicking Remove on a row the registry has not rescanned
        // yet. Throwing there would put an error on screen for work that is
        // already done.
        try ConnectorImport.remove(id: "never-installed", from: root)
    }

    @Test("an id that could escape the root is refused")
    func refusesTraversal() throws {
        let root = try ConnectorImportTests.temporaryRoot("root")
        let outside = root.deletingLastPathComponent().appendingPathComponent("bystander.txt")
        try Data("keep me".utf8).write(to: outside)

        // The id comes from a manifest on disk — not user input in the usual
        // sense, but it reaches `removeItem`, and that is not a call to make on
        // a path assembled from a file somebody else wrote.
        for id in ["../bystander.txt", "..", ".", "", "a/b"] {
            #expect(throws: ConnectorImport.Failure.self) {
                try ConnectorImport.remove(id: id, from: root)
            }
        }
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }
}

/// Reload has to actually re-run the app.
struct ConnectorReloadTests {
    @Test("invalidating lets an app run again before its interval is up")
    func invalidateForcesARun() async {
        let scheduler = ConnectorScheduler()
        let app = ConnectorSchedulerTests.app(every: 900)
        let t0 = ConnectorSchedulerTests.t0
        await scheduler.recordRun(app, at: t0)
        #expect(await scheduler.isDue(app, now: t0.addingTimeInterval(10)) == false)

        // The interval exists to stop polling, not to make an explicit
        // "Reload" wait out a window nobody asked for.
        await scheduler.invalidate(id: app.id)
        #expect(await scheduler.isDue(app, now: t0.addingTimeInterval(10)))
    }

    @Test("invalidating one app leaves the others alone")
    func invalidateIsScoped() async {
        let scheduler = ConnectorScheduler()
        let a = ConnectorSchedulerTests.app(id: "a")
        let b = ConnectorSchedulerTests.app(id: "b")
        let t0 = ConnectorSchedulerTests.t0
        await scheduler.recordRun(a, at: t0)
        await scheduler.recordRun(b, at: t0)

        await scheduler.invalidate(id: "a")
        #expect(await scheduler.isDue(a, now: t0.addingTimeInterval(10)))
        #expect(await scheduler.isDue(b, now: t0.addingTimeInterval(10)) == false)
    }
}
