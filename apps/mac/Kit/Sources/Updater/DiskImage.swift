import Foundation

public enum DiskImageError: Error, Sendable {
    case attachFailed(String)
    case noMountPoint
    case noApplication
}

/// Mounts and unmounts a downloaded disk image.
public enum DiskImage {
    /// Mounts read-only, out of the way, and hands back the mount point.
    ///
    /// `-nobrowse` keeps it out of Finder's sidebar, and `-mountrandom /tmp`
    /// keeps it out of `/Volumes`, where a name collision with an already
    /// mounted image would silently mount ours as "Notch Metrics 1".
    public static func attach(_ url: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = [
            "attach", url.path, "-nobrowse", "-readonly", "-mountrandom", "/tmp", "-plist",
        ]

        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()

        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DiskImageError.attachFailed("hdiutil exited \(process.terminationStatus)")
        }

        // Parsed as a property list rather than scraped from the text output,
        // which changes between macOS releases and is localised.
        guard let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil) as? [String: Any],
            let entities = plist["system-entities"] as? [[String: Any]],
            let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first
        else { throw DiskImageError.noMountPoint }

        return URL(fileURLWithPath: mountPoint, isDirectory: true)
    }

    public static func detach(_ mountPoint: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        // Forced, because a Finder window or a Spotlight indexer holding the
        // volume would otherwise leave it mounted forever.
        process.arguments = ["detach", mountPoint.path, "-force"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    public static func application(in mountPoint: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: mountPoint, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw DiskImageError.noApplication
        }
        return app
    }
}
