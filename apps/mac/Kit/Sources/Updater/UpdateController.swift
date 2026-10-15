import Foundation
import MetricsCore
import Observation

/// Everything the Updates pane needs to draw itself.
///
/// Deliberately one enum rather than a handful of booleans. "Downloading" and
/// "ready to install" and "failed" are mutually exclusive, and the version
/// that is being downloaded is only meaningful while a download is happening,
/// so each case carries exactly what that state is about.
public enum UpdateState: Equatable, Sendable {
    /// Nothing has been asked yet.
    case idle
    case checking
    /// Asked, and this build is current. The date is what the pane shows.
    case upToDate(checkedAt: Date)
    case available(LatestManifest)
    case downloading(LatestManifest, fraction: Double)
    /// Hashing the disk image. Separate from `downloading` because on a fast
    /// connection it is the longer half, and a bar that sticks at 100% looks
    /// like a hang.
    case verifying(LatestManifest)
    /// Downloaded, hashed and sitting on disk at this path.
    case readyToInstall(LatestManifest, URL)
    case installing(LatestManifest)
    case failed(String)

    public var manifest: LatestManifest? {
        switch self {
        case let .available(m), let .downloading(m, _), let .verifying(m),
             let .readyToInstall(m, _), let .installing(m):
            return m
        case .idle, .checking, .upToDate, .failed:
            return nil
        }
    }

    /// The version worth putting in front of somebody, if any.
    ///
    /// Drives the chip in the notch. `installing` is excluded because the app
    /// is seconds from quitting and a chip offering an update it is already
    /// applying is an invitation to press something twice.
    public var offer: String? {
        switch self {
        case let .available(m), let .downloading(m, _), let .verifying(m), let .readyToInstall(m, _):
            return m.version
        case .installing, .idle, .checking, .upToDate, .failed:
            return nil
        }
    }

    public var isBusy: Bool {
        switch self {
        case .checking, .downloading, .verifying, .installing: return true
        case .idle, .upToDate, .available, .readyToInstall, .failed: return false
        }
    }
}

/// Finds updates, fetches them, checks them, and hands them to the installer.
///
/// The installing half of this already existed — `SignatureVerifier`,
/// `DiskImage`, `UpdateInstaller` and the signed helper. This is the part that
/// decides *whether* to install anything, and it is kept separate from them so
/// the policy (how often to look, what counts as newer, what to do on a
/// failure) is readable in one file without the process-spawning underneath.
@MainActor
@Observable
public final class UpdateController {
    public private(set) var state: UpdateState = .idle {
        didSet { if state.offer != oldValue.offer { onOfferChanged(state.offer) } }
    }

    /// The notch's chip, driven from here.
    ///
    /// A callback rather than letting the notch observe this object: NotchUI
    /// does not depend on the app target and must not learn what a manifest
    /// is to draw a capsule. Fired only when the *offer* changes, so a
    /// download's forty progress ticks do not each touch the view model.
    public var onOfferChanged: @MainActor (String?) -> Void = { _ in }

    /// Set from settings. Checked at the point of the automatic poll rather
    /// than used to tear the timer down, so toggling it takes effect at the
    /// next tick with no restart.
    public var automatic = true

    private let feed: UpdateFeed
    private let runningVersion: String
    private let runningBuild: Int
    /// Where downloaded disk images live.
    ///
    /// Injected rather than read from `AppPaths.updates` at the point of use,
    /// because the only other way to point the tests somewhere disposable is
    /// an environment variable — and that is process-global state three
    /// concurrently running tests then fight over, with the loser pruning the
    /// developer's real Caches directory.
    private let downloads: URL
    private var poller: Task<Void, Never>?

    /// Six hours.
    ///
    /// Releases happen a few times a month. Polling hourly would be four
    /// hundred requests a month per install to learn the same thing, and
    /// nobody is waiting on an update they do not know exists.
    private static let interval: Duration = .seconds(6 * 60 * 60)

    /// A minute after launch, not at launch.
    ///
    /// Launch is already contending for the network with the first metrics
    /// refresh, which the user is actually looking at.
    private static let initialDelay: Duration = .seconds(60)

    public init(
        feed: UpdateFeed, runningVersion: String, runningBuild: Int,
        downloads: URL = AppPaths.updates
    ) {
        self.feed = feed
        self.runningVersion = runningVersion
        self.runningBuild = runningBuild
        self.downloads = downloads
    }

    /// Reads the running bundle's own version, which is what the real app wants.
    public convenience init(api: URL, mirror: URL) {
        let info = Bundle.main.infoDictionary ?? [:]
        self.init(
            feed: UpdateFeed(api: api, mirror: mirror),
            runningVersion: info["CFBundleShortVersionString"] as? String ?? "0.0.0",
            runningBuild: Int(info["CFBundleVersion"] as? String ?? "") ?? 0)
    }

    // MARK: - Checking

    public func start() {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            try? await Task.sleep(for: Self.initialDelay)
            while !Task.isCancelled {
                if let self, self.automatic, !self.state.isBusy {
                    await self.check(userInitiated: false)
                }
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    public func stop() {
        poller?.cancel()
        poller = nil
    }

    /// `userInitiated` only changes what is shown.
    ///
    /// A background poll that finds nothing must leave the pane alone; the
    /// same poll started by somebody pressing Check Now has to say *something*
    /// or the button looks broken.
    public func check(userInitiated: Bool) async {
        if userInitiated || state == .idle { state = .checking }

        do {
            guard let manifest = try await feed.latest() else {
                state = .upToDate(checkedAt: Date())
                return
            }

            guard manifest.isSupported() else {
                // Not a failure. This Mac is simply not the audience for this
                // build, and saying "update failed" about it would be a lie
                // the user cannot act on.
                Log.updater.notice(
                    "\(manifest.version, privacy: .public) needs macOS \(manifest.minimumSystemVersion, privacy: .public)")
                state = .upToDate(checkedAt: Date())
                return
            }

            // The build number, never the version string. One integer
            // comparison has no edge cases; `"0.10.0" < "0.9.0"` is true under
            // a string compare and would stop the updater dead on the tenth
            // minor release.
            guard manifest.build > runningBuild else {
                prune(keeping: nil)
                state = .upToDate(checkedAt: Date())
                return
            }

            Log.updater.info(
                "\(manifest.version, privacy: .public) (\(manifest.build)) is newer than \(self.runningVersion, privacy: .public) (\(self.runningBuild))")

            // An already-downloaded, already-verified copy survives a relaunch,
            // so quitting the app half way through an update does not mean
            // fetching eighteen megabytes again.
            prune(keeping: manifest.version)
            if let kept = verifiedDownload(for: manifest) {
                state = .readyToInstall(manifest, kept)
            } else {
                state = .available(manifest)
            }
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    // MARK: - Downloading

    public func download() async {
        guard let manifest = state.manifest else { return }
        let destination = location(for: manifest)

        state = .downloading(manifest, fraction: 0)
        do {
            let downloader = UpdateDownload()
            _ = try await downloader.start(from: manifest.url, to: destination) { [weak self] f in
                Task { @MainActor in
                    // Only while still downloading *this* update: a progress
                    // callback landing after a cancel or a failure would drag
                    // the pane back into a state it has left.
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(manifest, fraction: f)
                }
            }

            state = .verifying(manifest)
            // Off the main actor: hashing 18 MB blocks for long enough to drop
            // frames in the progress bar that is still on screen.
            try await Task.detached(priority: .utility) {
                try SignatureVerifier.verifyHash(of: destination, expected: manifest.sha256)
            }.value

            state = .readyToInstall(manifest, destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            Log.updater.error("download failed: \(String(describing: error), privacy: .public)")
            state = .failed(Self.describe(error))
        }
    }

    // MARK: - Installing

    /// Mounts, checks the signature, and hands over to the helper.
    ///
    /// The signature check happens here rather than after the download because
    /// it needs the *app* inside the image, and leaving a disk image mounted
    /// while the user decides whether to restart is a volume in everybody's
    /// Finder for an hour.
    public func install() {
        guard case let .readyToInstall(manifest, image) = state else { return }
        state = .installing(manifest)

        var mount: URL?
        do {
            let mountPoint = try DiskImage.attach(image)
            mount = mountPoint
            let app = try DiskImage.application(in: mountPoint)

            // Both checks, in this order. The hash is already done and proves
            // only that the bytes match what the same manifest claimed; the
            // signature is what binds the build to a key that was never in the
            // delivery path.
            try SignatureVerifier.verifySignature(of: app)
            try SignatureVerifier.verifyNotADowngrade(
                mountedApp: app, manifest: manifest, running: runningVersion)

            Log.updater.info("installing \(manifest.version, privacy: .public)")
            // Does not return in the normal case: it starts the helper and
            // terminates the app.
            try UpdateInstaller().install(mountedApp: app)
        } catch {
            if let mount { DiskImage.detach(mount) }
            Log.updater.error("install failed: \(String(describing: error), privacy: .public)")
            state = .failed(Self.describe(error))
        }
    }

    /// Back to "there is an update" from a failure, so Try again is possible
    /// without another round trip to the feed.
    public func dismissFailure() {
        guard case .failed = state else { return }
        state = .idle
    }

    /// Forces a state, for `NOTCH_DEBUG_UPDATE` and for SwiftUI previews.
    ///
    /// The update pane is otherwise unscreenshottable: every state but
    /// "up to date" needs a release newer than the one being run, which is a
    /// thing that exists for a few minutes a month.
    public func preview(_ state: UpdateState) { self.state = state }

    // MARK: - On disk

    private func location(for manifest: LatestManifest) -> URL {
        downloads
            .appendingPathComponent(manifest.version, isDirectory: true)
            .appendingPathComponent(manifest.filename)
    }

    /// Deletes every downloaded image except the one still on offer.
    ///
    /// Without this a disk image is left in Caches after every single update:
    /// the helper cleans up its own staging directory, but the download the
    /// install started from is the app's and the app is gone by then. Eighteen
    /// megabytes a release, forever, on a machine whose owner never asked.
    private func prune(keeping version: String?) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: downloads, includingPropertiesForKeys: nil)) ?? []
        for url in contents where url.lastPathComponent != version {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func verifiedDownload(for manifest: LatestManifest) -> URL? {
        let url = location(for: manifest)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        // Re-hashed rather than trusted on filename, because a half-written
        // file from an interrupted download has exactly the right name.
        guard (try? SignatureVerifier.verifyHash(of: url, expected: manifest.sha256)) != nil else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    // MARK: - Messages

    /// Plain language, and specific where being specific lets somebody act.
    static func describe(_ error: Error) -> String {
        switch error {
        case UpdateFeedError.unreachable:
            return "Could not reach the update server. Check your connection and try again."
        case UpdateFeedError.malformed:
            return "The update server sent something this version cannot read."
        case let VerificationError.hashMismatch(expected, actual):
            Log.updater.error("hash \(actual, privacy: .public) != \(expected, privacy: .public)")
            return "The download did not match what the update server described. Try again."
        case VerificationError.notSigned, VerificationError.wrongSigner,
             VerificationError.unreadableBundle:
            return "That download is not a signed Notch Metrics build. It has not been installed."
        case let VerificationError.downgrade(from, to):
            return "The download is version \(to), which is older than the installed \(from)."
        case InstallError.translocated:
            return "Notch Metrics is running from a temporary copy, so it cannot replace itself. "
                + "Drag it to your Applications folder once, then update from there."
        case let InstallError.destinationNotWritable(path):
            return "Notch Metrics cannot write to \(path). "
                + "Download the new version from the website instead."
        case InstallError.helperMissing:
            return "This copy of Notch Metrics is incomplete and cannot update itself. "
                + "Download the new version from the website."
        case DiskImageError.attachFailed, DiskImageError.noMountPoint,
             DiskImageError.noApplication:
            return "The downloaded disk image could not be opened."
        default:
            return "The update could not be completed: \(error.localizedDescription)"
        }
    }
}
