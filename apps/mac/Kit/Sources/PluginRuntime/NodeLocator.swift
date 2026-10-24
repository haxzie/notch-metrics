import Foundation

/// Finds a Node to run the metric runner with.
///
/// The runner used to be a 61 MB Bun executable, chosen precisely so this
/// problem did not exist. It bought independence from the user's machine at
/// 4.8× the app's download, for a feature most people never touch — so the
/// trade was reversed, and this is the bill.
///
/// **A GUI app inherits no shell `PATH`.** Launched from Finder, this process
/// gets a minimal environment; `/usr/bin/node` does not exist on stock macOS,
/// and the people most likely to have Node — nvm, fnm, Homebrew users — are
/// exactly the ones whose Node lives somewhere only their shell knows about.
/// So looking for `node` on `PATH` finds nothing on the machines that have it.
///
/// Hence the order below: the cheap certain answers first, the managers' own
/// layouts next, and a login shell last because spawning one costs ~100 ms and
/// is the only way to ask a user's own configuration where their Node is.
public enum NodeLocator {
    /// The floor the runner is built for. See `build.mjs` — esbuild targets
    /// `node20`, so anything older may meet syntax it cannot parse.
    public static let minimumMajor = 20

    public enum Failure: Error, Sendable, Equatable {
        /// Nothing anywhere. The message is shown to the user, so it says what
        /// to do rather than what went wrong.
        case notFound
        /// Found, but too old to run what we built.
        case tooOld(path: String, version: String)
    }

    /// Where to look, in order. Absolute paths only — see the note on `PATH`.
    ///
    /// Exposed for the tests, and because the Settings pane will want to show
    /// the user what was searched when it found nothing.
    public static func candidates(
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        contentsOfDirectory: (URL) -> [String] = { url in
            (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        }
    ) -> [URL] {
        var found: [URL] = []

        // An explicit override wins and is never second-guessed. This is what
        // a user picking a binary in Settings will write, and what the debug
        // launch uses.
        if let override = environment["NOTCH_NODE_PATH"], !override.isEmpty {
            found.append(URL(fileURLWithPath: override))
        }

        // Homebrew, Apple silicon then Intel, then a system install. Ordered
        // by how likely they are to be the one the user actually uses.
        found += ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"]
            .map { URL(fileURLWithPath: $0) }

        // Version managers keep every install side by side, so the newest is
        // the best guess at "the one they mean". Sorted numerically: a plain
        // string sort puts v9 above v20, which would hand back a Node four
        // years older than the one they installed yesterday.
        let managed: [URL] = [
            home.appendingPathComponent(".nvm/versions/node"),
            home.appendingPathComponent(".local/share/fnm/node-versions"),
            home.appendingPathComponent("Library/Application Support/fnm/node-versions"),
            home.appendingPathComponent(".volta/tools/image/node"),
        ]
        for root in managed {
            let versions = contentsOfDirectory(root)
                .filter { $0.hasPrefix("v") || $0.first?.isNumber == true }
                .sorted { left, right in
                    compareVersions(left, right) == .orderedDescending
                }
            for version in versions {
                // fnm and volta nest one level deeper than nvm does.
                found.append(root.appendingPathComponent("\(version)/bin/node"))
                found.append(root.appendingPathComponent("\(version)/installation/bin/node"))
            }
        }

        return found
    }

    /// `v20.11.0` against `v9.1.0`, numerically.
    ///
    /// Leading `v` optional, missing components treated as zero, and anything
    /// unparseable sorts last rather than crashing — a directory in here is
    /// whatever the user's version manager put there, not something we chose.
    static func compareVersions(_ left: String, _ right: String) -> ComparisonResult {
        let parse = { (s: String) -> [Int] in
            s.drop(while: { !$0.isNumber })
                .split(separator: ".")
                .map { Int($0.prefix(while: \.isNumber)) ?? -1 }
        }
        let l = parse(left), r = parse(right)
        for i in 0..<max(l.count, r.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// The major version a `node --version` string reports, or nil.
    static func major(of output: String) -> Int? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("v") || trimmed.first?.isNumber == true else { return nil }
        return Int(trimmed.drop(while: { !$0.isNumber }).prefix(while: \.isNumber))
    }
}
