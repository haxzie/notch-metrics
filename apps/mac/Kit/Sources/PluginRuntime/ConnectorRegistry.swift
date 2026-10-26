import Foundation
import MetricsCore

/// A connector found on disk, with whatever the user has said about it.
public struct LoadedConnector: Sendable, Identifiable, Equatable {
    public let id: String
    public let directory: URL
    public let manifest: ConnectorManifest?
    public let state: PluginState
    /// A stable SHA-256 over the manifest and the entry — see `PluginDigest`.
    ///
    /// No longer what approval is pinned to; the scheduler still uses it to
    /// notice a rewrite and re-run promptly rather than at the next tick.
    public let contentHash: String
    /// What this app asks for. Approval is recorded against this — see
    /// `ConnectorGrants`.
    public let grants: ConnectorGrants
    /// What enabling it would newly permit, when it is `.modified`.
    public let newGrants: [String]

    public init(
        id: String, directory: URL, manifest: ConnectorManifest?, state: PluginState,
        contentHash: String,
        grants: ConnectorGrants = ConnectorGrants(hosts: [], hostCredentials: [], secrets: []),
        newGrants: [String] = []
    ) {
        self.id = id
        self.directory = directory
        self.manifest = manifest
        self.state = state
        self.contentHash = contentHash
        self.grants = grants
        self.newGrants = newGrants
    }

    public var displayName: String { manifest?.name ?? id }
    public var metricCount: Int { manifest?.metrics.count ?? 0 }

    /// What this app declared it looks like.
    public var icon: CustomAppIcon? { manifest?.icon }

    /// The artwork, for the one arm that has any.
    ///
    /// Resolution lives in `CustomAppIcon.fileURL(in:)`, which appends a
    /// single path component — so a manifest naming `../../../../etc/passwd`
    /// cannot reach outside its own directory even if it gets past the
    /// schema's pattern.
    public var iconURL: URL? { manifest?.icon?.fileURL(in: directory) }

    /// Where this lives, shortened the way the Finder shows it.
    public var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = directory.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// Discovers connectors and watches the directory for changes.
///
/// Deliberately a near-copy of `PluginRegistry` rather than a generic shared
/// with it. The two formats are converging — a connector is what a plugin
/// should have been — and the single-metric path is on its way out, so a
/// shared abstraction here would be scaffolding around something scheduled
/// for deletion.
@MainActor
@Observable
public final class ConnectorRegistry {
    public private(set) var connectors: [LoadedConnector] = []

    private let root: URL
    /// id → `ConnectorGrants.canonical` for what was approved. Approval is of
    /// *grants*, not of contents; see `ConnectorGrants` for why it stopped
    /// being a digest. Older entries hold a bare SHA and are handled in
    /// `scan`.
    private var approved: [String: String]
    private var watcher: DirectoryWatcher?

    /// Called with connectors that have appeared since the last scan. Not
    /// fired for the first scan, when everything is new.
    public var onAdded: (([LoadedConnector]) -> Void)?

    private var known: Set<String>?

    public init(root: URL = AppPaths.connectors, approved: [String: String] = [:]) {
        self.root = root
        self.approved = approved
    }

    public func setApproved(_ digestsByID: [String: String]) {
        approved = digestsByID
        reload()
    }

    /// Enabled apps whose approval is still stored as a content digest, with
    /// the grants that should replace it.
    ///
    /// Read by the environment and written back to Settings, so the migration
    /// in `scan` is a one-off rather than a fallback every launch re-derives.
    public var legacyApprovals: [String: String] {
        var upgrades: [String: String] = [:]
        for connector in connectors where connector.state == .ready {
            guard let stored = approved[connector.id], ConnectorGrants.parse(stored) == nil
            else { continue }
            upgrades[connector.id] = connector.grants.canonical
        }
        return upgrades
    }

    public func start() {
        reload()
        watcher = DirectoryWatcher(url: root) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    public func stop() { watcher = nil }

    public func reload() {
        connectors = Self.scan(root: root, approved: approved)

        let present = Set(connectors.map(\.id))
        defer { known = present }
        guard let known else { return }

        let arrived = connectors.filter { !known.contains($0.id) }
        if !arrived.isEmpty { onAdded?(arrived) }
    }

    static func scan(root: URL, approved: [String: String]) -> [LoadedConnector] {
        let fm = FileManager.default
        guard
            let entries = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        else { return [] }

        return entries.compactMap { directory -> LoadedConnector? in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { return nil }

            let id = directory.lastPathComponent
            // `.staging` is the MCP server's scratch space, not a connector.
            guard !id.hasPrefix(".") else { return nil }

            switch Self.load(id: id, directory: directory) {
            case let .failure(reason):
                return LoadedConnector(
                    id: id, directory: directory, manifest: nil,
                    state: .invalid(reason: reason), contentHash: "")
            case let .success(manifest, digest):
                let grants = ConnectorGrants(manifest: manifest)
                let state: PluginState
                var newGrants: [String] = []

                switch approved[id] {
                case nil:
                    state = .pendingApproval
                case let stored?:
                    guard let previous = ConnectorGrants.parse(stored) else {
                        // A content digest from a build before grants were
                        // recorded. It carries no grant list, so there is
                        // nothing to compare against — but the user *did*
                        // enable this app, and an upgrade is not a reason to
                        // re-ask. The grants on disk are adopted as what was
                        // approved; `legacyApprovals` then persists them so
                        // this branch runs once per app, ever.
                        //
                        // The accepted cost: a widening slipped in between
                        // the old approval and this upgrade is adopted
                        // unasked. Bounded by that one window, against a
                        // prompt every installed app would have shown on
                        // first launch after updating.
                        state = .ready
                        break
                    }
                    if grants.isCovered(by: previous) {
                        state = .ready
                    } else {
                        state = .modified
                        newGrants = grants.additions(over: previous)
                    }
                }
                return LoadedConnector(
                    id: id, directory: directory, manifest: manifest, state: state,
                    contentHash: digest, grants: grants, newGrants: newGrants)
            }
        }
        .sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    nonisolated enum LoadOutcome {
        case success(manifest: ConnectorManifest, digest: String)
        case failure(reason: String)
    }

    /// Reads and validates one connector directory.
    ///
    /// Shared with the importer so that what "Load app" accepts and what the
    /// registry will later run are decided by one piece of code. A picker that
    /// accepted a directory the scanner then rejects is how you get an app
    /// that imports happily and shows an error forever.
    nonisolated static func load(id: String, directory: URL) -> LoadOutcome {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            return .failure(reason: "No manifest.json in this folder.")
        }

        let manifest: ConnectorManifest
        do {
            manifest = try JSONDecoder().decode(ConnectorManifest.self, from: data)
        } catch {
            return .failure(reason: readable(error))
        }

        // The id is the directory name everywhere else, so a manifest that
        // disagrees would be approved under one name and run under another.
        guard manifest.id == id else {
            return .failure(
                reason: "This folder is named \"\(id)\" but its manifest says \"\(manifest.id)\".")
        }

        guard let entry = try? Data(contentsOf: directory.appendingPathComponent(manifest.entry))
        else {
            return .failure(reason: "\(manifest.entry) is missing.")
        }

        // Still over the manifest as well as the code: this is what tells the
        // scheduler an app was rewritten and should re-run now. It is no
        // longer what approval is compared against.
        return .success(manifest: manifest, digest: PluginDigest.of(manifest: data, entry: entry))
    }

    nonisolated private static func readable(_ error: any Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        switch decoding {
        case let .keyNotFound(key, _): return "manifest.json is missing \"\(key.stringValue)\"."
        case let .typeMismatch(_, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "manifest.json has the wrong type for \"\(path)\"."
        case let .valueNotFound(_, context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "manifest.json has no value for \"\(path)\"."
        default: return "manifest.json could not be read."
        }
    }
}

/// Bringing a folder the user picked under the app's own directory.
///
/// The Chrome-extension bargain: what runs is a *copy* the app owns, not the
/// project directory the user is still editing. Without the copy, a connector
/// approved at lunchtime is running different code by the afternoon with no
/// rescan in between, because a build in a watched project rewrites it in
/// place.
public enum ConnectorImport {
    public enum Failure: LocalizedError, Equatable {
        case notADirectory
        case invalid(reason: String)
        case alreadyInstalled(id: String)
        case copyFailed(reason: String)

        public var errorDescription: String? {
            switch self {
            case .notADirectory:
                "Pick the folder that contains manifest.json."
            case let .invalid(reason):
                reason
            case let .alreadyInstalled(id):
                "\"\(id)\" is already installed. Remove it first to load it again."
            case let .copyFailed(reason):
                "The app could not be copied: \(reason)"
            }
        }
    }

    /// Validates `source` and copies it to `root/<id>`.
    ///
    /// Validation happens against the *source*, before anything is written, so
    /// a folder that was never going to work does not leave a half-installed
    /// directory behind for the scanner to report as broken.
    @discardableResult
    public static func install(
        from source: URL, into root: URL = AppPaths.connectors, replacing: Bool = false
    ) throws -> ConnectorManifest {
        let fm = FileManager.default
        guard (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            throw Failure.notADirectory
        }

        // The id comes from the manifest, not from the folder name the user
        // happened to pick: `~/code/my-linear-thing` must install as `linear`.
        guard let data = try? Data(contentsOf: source.appendingPathComponent("manifest.json")),
            let probe = try? JSONDecoder().decode(ConnectorManifest.self, from: data)
        else {
            throw Failure.invalid(reason: "No readable manifest.json in this folder.")
        }

        let manifest: ConnectorManifest
        switch ConnectorRegistry.load(id: probe.id, directory: source) {
        case let .failure(reason): throw Failure.invalid(reason: reason)
        case let .success(loaded, _): manifest = loaded
        }

        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(manifest.id, isDirectory: true)

        if fm.fileExists(atPath: destination.path) {
            guard replacing else { throw Failure.alreadyInstalled(id: manifest.id) }
            try? fm.removeItem(at: destination)
        }

        do {
            // `copyItem` rather than a move: the user keeps their project, and
            // the app gets a copy nothing else is writing to.
            try fm.copyItem(at: source, to: destination)
        } catch {
            throw Failure.copyFailed(reason: error.localizedDescription)
        }
        return manifest
    }
}

extension ConnectorImport {
    /// Deletes an installed app's directory.
    ///
    /// Only the copy the app owns. The folder the user built it in is theirs
    /// and is never touched — `install` copied rather than moved for exactly
    /// this reason, so removing an app here cannot delete somebody's project.
    public static func remove(id: String, from root: URL = AppPaths.connectors) throws {
        try assertSafe(id)
        let directory = root.appendingPathComponent(id, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    /// Refuses an id that could name something outside the connectors root.
    ///
    /// The id comes from a manifest on disk, so it is not user input in the
    /// usual sense — but it reaches `removeItem`, and that is not a call to
    /// make on a path assembled from a file somebody else wrote.
    private static func assertSafe(_ id: String) throws {
        guard !id.isEmpty, !id.contains("/"), id != ".", id != ".." else {
            throw Failure.invalid(reason: "\"\(id)\" is not a valid app id.")
        }
    }
}
