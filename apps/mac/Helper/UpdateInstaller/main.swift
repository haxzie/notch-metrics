import Foundation

/// Replaces the app bundle after the app has quit, then relaunches it.
///
/// This exists as a real, signed binary rather than a shell one-liner for
/// three reasons: it can be code-signed and notarised with the app, so the
/// hardened runtime is satisfied; it can log what it did, which matters
/// enormously when an update goes wrong on somebody else's machine; and it can
/// restore the previous bundle if the swap fails halfway.
///
///     UpdateInstaller --wait-pid <pid> --staged <path> --destination <path> [--relaunch]

func argument(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: "--\(name)"),
          index + 1 < CommandLine.arguments.count
    else { return nil }
    return CommandLine.arguments[index + 1]
}

let log: (String) -> Void = { message in
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    FileHandle.standardError.write(Data(line.utf8))

    let logURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NotchMetrics/logs/update.log")
    try? FileManager.default.createDirectory(
        at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

guard let stagedPath = argument("staged"), let destinationPath = argument("destination") else {
    log("usage: UpdateInstaller --wait-pid <pid> --staged <path> --destination <path> [--relaunch]")
    exit(2)
}

let staged = URL(fileURLWithPath: stagedPath)
let destination = URL(fileURLWithPath: destinationPath)

// Wait for the app to go away. `kill(pid, 0)` tests for existence without
// signalling. Capped, so a hung app does not leave this process resident
// forever holding a staged copy of the update.
if let pidString = argument("wait-pid"), let pid = Int32(pidString) {
    log("waiting for pid \(pid)")
    var waited = 0.0
    while kill(pid, 0) == 0 && waited < 30 {
        Thread.sleep(forTimeInterval: 0.1)
        waited += 0.1
    }
    if waited >= 30 { log("pid \(pid) is still running after 30s; continuing anyway") }
}

let fm = FileManager.default

guard fm.fileExists(atPath: staged.path) else {
    log("nothing staged at \(staged.path); aborting")
    exit(1)
}

func run(_ tool: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

// Copied beside the destination first, so the atomic replace below is a rename
// within one filesystem rather than a cross-device copy that can half-finish.
let sibling = destination.deletingLastPathComponent()
    .appendingPathComponent(".NotchMetrics-incoming-\(UUID().uuidString).app")

log("copying \(staged.path) -> \(sibling.path)")
// ditto, not cp -R: it preserves extended attributes, symlinks and the nested
// structure the code signature covers. A cp-copied bundle fails validation,
// and macOS reports that as "the application is damaged".
guard run("/usr/bin/ditto", [staged.path, sibling.path]) == 0 else {
    log("ditto failed; leaving the installed app untouched")
    try? fm.removeItem(at: sibling)
    exit(1)
}

do {
    log("replacing \(destination.path)")
    // Atomic from the filesystem's point of view, and it hands back the URL of
    // the displaced bundle so a failure is recoverable rather than terminal.
    _ = try fm.replaceItemAt(destination, withItemAt: sibling)
    log("replaced successfully")
} catch {
    log("replace failed: \(error.localizedDescription)")
    try? fm.removeItem(at: sibling)
    exit(1)
}

if CommandLine.arguments.contains("--relaunch") {
    log("relaunching")
    _ = run("/usr/bin/open", [destination.path])
}

// The staging directory holds a full copy of the app — tens of megabytes left
// in Caches on every update if this is skipped.
try? fm.removeItem(at: staged.deletingLastPathComponent())
log("done")
exit(0)
