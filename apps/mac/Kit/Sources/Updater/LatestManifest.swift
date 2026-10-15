import Foundation
import MetricsCore

/// `desktop/latest.json`, and the body of `GET /v1/updates/latest`.
public struct LatestManifest: Codable, Sendable, Equatable {
    public let version: String
    /// A monotonically increasing integer. Compared instead of the semver
    /// string, because one integer comparison has no edge cases.
    public let build: Int
    public let tag: String
    public let publishedAt: String
    public let platform: String
    public let minimumSystemVersion: String
    public let filename: String
    public let url: URL
    public let size: Int
    public let sha256: String
    public let notes: URL?
    public let mandatory: Bool

    /// A public struct gets no public memberwise initialiser, and the only
    /// thing that needs one is `UpdateSample` — the fixed release the Updates
    /// pane is screenshotted against.
    public init(
        version: String, build: Int, tag: String, publishedAt: String, platform: String,
        minimumSystemVersion: String, filename: String, url: URL, size: Int, sha256: String,
        notes: URL?, mandatory: Bool
    ) {
        self.version = version
        self.build = build
        self.tag = tag
        self.publishedAt = publishedAt
        self.platform = platform
        self.minimumSystemVersion = minimumSystemVersion
        self.filename = filename
        self.url = url
        self.size = size
        self.sha256 = sha256
        self.notes = notes
        self.mandatory = mandatory
    }

    /// Whether this Mac can actually run the build on offer.
    ///
    /// Checked before downloading, so a Mac on 14 is not made to fetch 18 MB of
    /// something that will refuse to launch.
    public func isSupported(by system: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Bool {
        guard platform == "darwin-arm64" else { return false }
        guard let required = SemanticVersion(minimumSystemVersion) else { return true }
        let current = SemanticVersion(
            "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)")
        return (current.map { $0 >= required }) ?? true
    }
}
