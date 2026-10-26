import Foundation
import MetricsCore

public enum PluginState: Sendable, Equatable {
    /// On disk, parseable, but not yet enabled by the user.
    ///
    /// New plugins start here deliberately. An agent can write a directory into
    /// Application Support; it should not thereby start making network calls
    /// with the user's API keys and nobody having said yes.
    case pendingApproval
    case ready
    /// Approved once, and the bytes on disk are no longer the bytes that were
    /// approved.
    ///
    /// Not an error and not a silent re-approval. The installed copy lives in
    /// a directory the user owns, so anything able to write there once can
    /// write there again — and approving a metric approves its `allowedHosts`
    /// and its secrets as much as its code. A rewrite therefore asks again
    /// rather than inheriting the yes it was given for different contents.
    case modified
    case invalid(reason: String)
}

public struct LoadedPlugin: Sendable, Identifiable, Equatable {
    public let id: String
    public let directory: URL
    public let manifest: PluginManifest?
    public let state: PluginState
    /// A stable SHA-256 over the manifest and the entry — see `PluginDigest`.
    ///
    /// Stable is the operative word. This used to be built from
    /// `Data.hashValue`, which Swift seeds per process, so it changed on every
    /// launch and could not be compared with anything recorded earlier.
    public let contentHash: String

    public var displayName: String { manifest?.name ?? id }

    /// The app this metric belongs to, as a user would name it.
    ///
    /// `appId` is required of anything the MCP server writes, but a manifest
    /// placed in the folder by hand may carry neither field, and a metric with
    /// no app still has to appear somewhere rather than vanish from the list.
    public var appDisplayName: String {
        if let name = manifest?.appName, !name.isEmpty { return name }
        if let id = manifest?.appId, !id.isEmpty { return id.capitalized }
        return "Other"
    }
}

/// Discovers plugins and watches the directory for changes.
@MainActor
@Observable
public final class PluginRegistry {
    public private(set) var plugins: [LoadedPlugin] = []

    private let root: URL
    /// id → the digest that was approved. Not a set of ids: approval is of
    /// *contents*, which is the whole of `PluginState.modified`.
    private var approved: [String: String]
    private var watcher: DirectoryWatcher?

    /// Called with metrics that have appeared since the last scan.
    ///
    /// The MCP server and the CLI write into this directory while the app is
    /// running, so an arrival is something that happens *to* the app rather
    /// than something a person did in it. Without a signal here the metric
    /// sits in a folder nobody is looking at: the agent says "enable it in
    /// Settings" and the user has no reason to believe anything happened.
    ///
    /// Not fired for the first scan at launch. Everything is new then, and a
    /// stack of banners for metrics that have been installed for weeks is
    /// noise that teaches people to ignore the banner.
    public var onAdded: (([LoadedPlugin]) -> Void)?

    /// Nil until the first scan, which is what distinguishes "nothing
    /// installed" from "not looked yet" — the two would otherwise both be an
    /// empty set, and the first scan would announce everything.
    private var known: Set<String>?

    public init(root: URL = AppPaths.metrics, approved: [String: String] = [:]) {
        self.root = root
        self.approved = approved
    }

    public func setApproved(_ digestsByID: [String: String]) {
        approved = digestsByID
        reload()
    }

    public func start() {
        reload()
        // Agents write these files while the app is running — live reload is
        // the entire point of the MCP workflow, not a nicety.
        // The watch is no longer live *reload* — an installed copy is not
        // meant to change under a running app, and the MCP workflow rewrites
        // through register/refresh, which is an explicit act. It stays
        // because it is how a rewrite is *noticed*: a rescan recomputes the
        // digest, and a plugin whose bytes moved stops being `.ready`.
        watcher = DirectoryWatcher(url: root) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    public func stop() {
        watcher = nil
    }

    public func reload() {
        plugins = Self.scan(root: root, approved: approved)

        let present = Set(plugins.map(\.id))
        defer { known = present }
        guard let known else { return }

        let arrived = plugins.filter { !known.contains($0.id) }
        // Invalid ones are deliberately included. A metric an agent has just
        // written and got wrong is exactly when somebody needs telling, and
        // the row in Settings carries the reason.
        if !arrived.isEmpty { onAdded?(arrived) }
    }

    static func scan(root: URL, approved: [String: String]) -> [LoadedPlugin] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return [] }

        return entries.compactMap { directory -> LoadedPlugin? in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { return nil }

            let id = directory.lastPathComponent
            // `.staging` is the MCP server's scratch space; it is not a plugin.
            guard !id.hasPrefix(".") else { return nil }

            let manifestURL = directory.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL) else {
                return LoadedPlugin(
                    id: id, directory: directory, manifest: nil,
                    state: .invalid(reason: "No manifest.json in this folder."),
                    contentHash: "")
            }

            let manifest: PluginManifest
            do {
                manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
            } catch {
                // Reported, not skipped. A plugin that silently vanishes from
                // the settings list is one nobody can fix, because nothing
                // anywhere says what is wrong with it.
                return LoadedPlugin(
                    id: id, directory: directory, manifest: nil,
                    state: .invalid(reason: readable(error)), contentHash: "")
            }

            let entryURL = directory.appendingPathComponent(manifest.entry)
            guard let entry = try? Data(contentsOf: entryURL) else {
                return LoadedPlugin(
                    id: id, directory: directory, manifest: manifest,
                    state: .invalid(reason: "\(manifest.entry) is missing."), contentHash: "")
            }

            // The digest covers the manifest as well as the code, because
            // approving a metric approves which hosts it may reach.
            let digest = PluginDigest.of(manifest: data, entry: entry)
            let state: PluginState
            switch approved[id] {
            case nil: state = .pendingApproval
            case digest: state = .ready
            default: state = .modified
            }

            return LoadedPlugin(
                id: id,
                directory: directory,
                manifest: manifest,
                state: state,
                contentHash: digest
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private static func readable(_ error: any Error) -> String {
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

/// A debounced FSEvents watch on one directory.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let callback: @Sendable () -> Void
    private var debounce: DispatchWorkItem?

    init(url: URL, callback: @escaping @Sendable () -> Void) {
        self.callback = callback
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let handler: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue().fire()
        }

        stream = FSEventStreamCreate(
            kCFAllocatorDefault, handler, &context,
            [url.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3, FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))

        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    private func fire() {
        // Writing a plugin is several file operations in a burst — manifest,
        // entry, sometimes a README — and rescanning on each one shows up as a
        // flicker in the settings list.
        debounce?.cancel()
        let work = DispatchWorkItem { [callback] in callback() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    deinit {
        debounce?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
