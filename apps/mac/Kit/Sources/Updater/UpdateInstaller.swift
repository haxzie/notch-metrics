import AppKit
import Foundation
import MetricsCore

public enum InstallError: Error, Sendable, Equatable {
    /// The app is running from a quarantine-translocated copy.
    ///
    /// macOS mounts a downloaded app at a read-only random path the first time
    /// it runs, so replacing the bundle in place is not merely blocked — the
    /// path is not where the user thinks the app lives. The honest fix is for
    /// them to drag it to /Applications once.
    case translocated
    case destinationNotWritable(String)
    case helperMissing
    case copyFailed(String)
}

/// Replaces the running bundle and relaunches.
public struct UpdateInstaller: Sendable {
    public init() {}

    public func install(mountedApp: URL) throws {
        let destination = Bundle.main.bundleURL

        // `AppTranslocation` appears in the path of a translocated bundle.
        guard !destination.path.contains("AppTranslocation") else {
            throw InstallError.translocated
        }

        let parent = destination.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            // Deliberately not escalating. A privileged helper (SMJobBless) is
            // a large amount of permanently-installed attack surface for a case
            // that is rare and has a perfectly good manual fallback.
            throw InstallError.destinationNotWritable(parent.path)
        }

        let staging = AppPaths.updates.appendingPathComponent(
            "staged-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let staged = staging.appendingPathComponent(destination.lastPathComponent)

        // `ditto`, never `cp -R`. It preserves extended attributes, symlinks
        // and the nested structure the code signature covers; a `cp`-copied
        // bundle fails validation, and macOS reports that to the user as "the
        // application is damaged" rather than as a bad copy.
        try run("/usr/bin/ditto", [mountedApp.path, staged.path], error: InstallError.copyFailed)

        // The quarantine flag rides along from the download and would make the
        // freshly installed copy prompt on first launch.
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path], error: InstallError.copyFailed)

        // The helper has to be copied out first: it lives inside the bundle it
        // is about to replace.
        // `forAuxiliaryExecutable` only looks in Contents/MacOS; Xcode's
        // "embed" phase for a tool target puts it in Contents/Resources. Check
        // both rather than depending on which the project happens to produce.
        guard let bundledHelper = Bundle.main.url(forAuxiliaryExecutable: "UpdateInstaller")
            ?? Bundle.main.url(forResource: "UpdateInstaller", withExtension: nil)
        else { throw InstallError.helperMissing }

        let helper = staging.appendingPathComponent("UpdateInstaller")
        try run("/usr/bin/ditto", [bundledHelper.path, helper.path], error: InstallError.copyFailed)

        let process = Process()
        process.executableURL = helper
        process.arguments = [
            "--wait-pid", String(ProcessInfo.processInfo.processIdentifier),
            "--staged", staged.path,
            "--destination", destination.path,
            "--relaunch",
        ]
        try? process.run()

        // The helper polls for this process to exit, so quitting is the signal.
        NSApplication.shared.terminate(nil)
    }

    private func run(_ path: String, _ arguments: [String], error: (String) -> InstallError) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = Pipe()
        let err = Pipe()
        process.standardError = err

        try process.run()
        let data = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw error(String(data: data, encoding: .utf8) ?? "\(path) exited \(process.terminationStatus)")
        }
    }
}
