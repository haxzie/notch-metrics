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
    case invalid(reason: String)
}

public struct LoadedPlugin: Sendable, Identifiable, Equatable {
    public let id: String
    public let directory: URL
    public let manifest: PluginManifest?
    public let state: PluginState
    /// Changes when the manifest or entry file changes, so cached results can
    /// be invalidated when an agent edits a plugin while the app is running.
    public let contentHash: String

    public var displayName: String { manifest?.name ?? id }
}

/// Discovers plugins and watches the directory for changes.
@MainActor
@Observable
public final class PluginRegistry {
    public private(set) var plugins: [LoadedPlugin] = []

    private let root: URL
    private var approved: Set<String>
    private var watcher: DirectoryWatcher?

    public init(root: URL = AppPaths.metrics, approved: Set<String> = []) {
        self.root = root
        self.approved = approved
    }

    public func setApproved(_ ids: Set<String>) {
        approved = ids
        reload()
    }

    public func start() {
        reload()
        // Agents write these files while the app is running — live reload is
        // the entire point of the MCP workflow, not a nicety.
        watcher = DirectoryWatcher(url: root) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    public func stop() {
        watcher = nil
    }

    public func reload() {
        plugins = Self.scan(root: root, approved: approved)
    }

    static func scan(root: URL, approved: Set<String>) -> [LoadedPlugin] {
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

            return LoadedPlugin(
                id: id,
                directory: directory,
                manifest: manifest,
                state: approved.contains(id) ? .ready : .pendingApproval,
                contentHash: "\(data.hashValue)-\(entry.hashValue)"
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
