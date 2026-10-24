import Foundation
import Testing

@testable import PluginRuntime

/// Finding the user's Node.
///
/// This is the cost of not shipping a runtime, and it is all edge case: the
/// users who have Node are disproportionately the ones whose Node is somewhere
/// a GUI app cannot see. The ordering below is the whole feature.
struct NodeLocatorTests {
    static let home = URL(fileURLWithPath: "/Users/someone")

    static func candidates(
        env: [String: String] = [:],
        dirs: [String: [String]] = [:]
    ) -> [String] {
        NodeLocator.candidates(
            home: home,
            environment: env,
            contentsOfDirectory: { dirs[$0.path] ?? [] }
        ).map(\.path)
    }

    @Test("an explicit override is tried before anything else")
    func overrideWins() {
        let found = Self.candidates(env: ["NOTCH_NODE_PATH": "/custom/node"])
        #expect(found.first == "/custom/node")
    }

    @Test("an empty override is ignored rather than tried")
    func emptyOverride() {
        // An unset variable read as "" would otherwise make the first
        // candidate the filesystem root, which exists and is not Node.
        let found = Self.candidates(env: ["NOTCH_NODE_PATH": ""])
        #expect(found.first == "/opt/homebrew/bin/node")
    }

    @Test("Homebrew comes before the system path")
    func homebrewFirst() {
        let found = Self.candidates()
        let brew = found.firstIndex(of: "/opt/homebrew/bin/node")
        let system = found.firstIndex(of: "/usr/bin/node")
        #expect(brew != nil && system != nil)
        #expect(brew! < system!)
    }

    @Test("a version manager's newest install wins, numerically")
    func newestManagedVersion() {
        // The bug this guards: a lexical sort puts v9 above v20, handing back
        // a Node from 2017 on a machine that installed 20 yesterday.
        let found = Self.candidates(dirs: [
            "/Users/someone/.nvm/versions/node": ["v18.19.0", "v9.11.2", "v20.11.0"]
        ])
        let nvm = found.filter { $0.contains(".nvm") }
        #expect(nvm.first == "/Users/someone/.nvm/versions/node/v20.11.0/bin/node")
        #expect(nvm.last?.contains("v9.11.2") == true)
    }

    @Test("fnm and volta nest a level deeper than nvm")
    func layoutDifferences() {
        let found = Self.candidates(dirs: [
            "/Users/someone/.local/share/fnm/node-versions": ["v22.0.0"]
        ])
        // Both shapes are offered because the managers disagree and probing a
        // path that does not exist costs nothing.
        #expect(found.contains("/Users/someone/.local/share/fnm/node-versions/v22.0.0/bin/node"))
        #expect(
            found.contains(
                "/Users/someone/.local/share/fnm/node-versions/v22.0.0/installation/bin/node"))
    }

    @Test("a directory that is not a version is left alone")
    func ignoresStrayDirectories() {
        let found = Self.candidates(dirs: [
            "/Users/someone/.nvm/versions/node": ["v20.11.0", ".DS_Store", "alias"]
        ])
        #expect(found.contains { $0.contains("v20.11.0") })
        #expect(!found.contains { $0.contains("alias") })
        #expect(!found.contains { $0.contains("DS_Store") })
    }

    @Test("versions sort numerically, not as strings")
    func versionOrdering() {
        #expect(NodeLocator.compareVersions("v20.11.0", "v9.11.2") == .orderedDescending)
        #expect(NodeLocator.compareVersions("v20.1.0", "v20.11.0") == .orderedAscending)
        #expect(NodeLocator.compareVersions("20.0.0", "v20") == .orderedSame)
    }

    @Test("the major version is read off what node prints")
    func majorVersion() {
        #expect(NodeLocator.major(of: "v22.22.3\n") == 22)
        #expect(NodeLocator.major(of: "20.0.0") == 20)
        #expect(NodeLocator.major(of: "not a version") == nil)
        #expect(NodeLocator.major(of: "") == nil)
    }

    @Test("the floor matches what the runner is built for")
    func minimumMatchesBuild() {
        // `packages/metric-runtime/build.mjs` targets node20. A floor lower
        // than the build target is a syntax error on a user's machine that
        // nothing here would catch.
        #expect(NodeLocator.minimumMajor == 20)
    }
}
