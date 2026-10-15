import Foundation
import Updater

/// A fixed release, for `NOTCH_DEBUG_UPDATE` and for screenshots.
///
/// The Updates pane is otherwise unscreenshottable in every state that
/// matters: each one needs a published release newer than the build being
/// run, which is a condition that exists for a few minutes a month and never
/// on the machine that just built the app.
enum UpdateSample {
    static let manifest = LatestManifest(
        version: "0.4.0",
        build: 152,
        tag: "mac-v0.4.0",
        publishedAt: "2026-10-15T09:00:00Z",
        platform: "darwin-arm64",
        minimumSystemVersion: "14.0",
        filename: "NotchMetrics-0.4.0-arm64.dmg",
        url: URL(string: "https://assets.notchmetrics.com/desktop/0.4.0/NotchMetrics-0.4.0-arm64.dmg")!,
        size: 18_432_000,
        sha256: String(repeating: "a", count: 64),
        notes: URL(string: "https://notchmetrics.com/changelog#v0-4-0"),
        mandatory: false)

    /// The value of `NOTCH_DEBUG_UPDATE`, as a state.
    static func state(_ name: String) -> UpdateState? {
        switch name {
        case "available", "chip": .available(manifest)
        case "downloading": .downloading(manifest, fraction: 0.42)
        case "verifying": .verifying(manifest)
        case "ready": .readyToInstall(manifest, URL(fileURLWithPath: "/dev/null"))
        case "installing": .installing(manifest)
        case "uptodate": .upToDate(checkedAt: Date().addingTimeInterval(-180))
        case "failed": .failed(
            "The download did not match what the update server described. Try again.")
        default: nil
        }
    }
}
