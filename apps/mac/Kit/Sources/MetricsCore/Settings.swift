import Foundation

/// Every preference, in one Codable struct written to one file.
///
/// Not `@AppStorage`. Five modules each reaching for a string key becomes
/// untyped soup within a month, with no single place to see what the app
/// actually remembers or to migrate it.
public struct AppSettings: Codable, Sendable, Equatable {
    public var schemaVersion: Int = 1
    public var displayPolicy: NotchDisplayPolicy = .builtIn
    /// The notch is drawn over fullscreen apps by default: on a notch Mac that
    /// region is black and the menu bar is hidden, so it is free space.
    public var showInFullscreen: Bool = true
    public var showMenuBarIcon: Bool = false
    public var launchAtLogin: Bool = true
    public var hoverDwellMilliseconds: Int = 120
    public var collapseDelayMilliseconds: Int = 400
    public var reduceMotionOverride: Bool? = nil
    /// Plugins are not executed until the user enables them here. An agent can
    /// drop a file into Application Support; it should not thereby start making
    /// network calls.
    public var approvedPluginIDs: Set<String> = []
    public var checkForUpdatesAutomatically: Bool = true

    public init() {}
}

/// Debounced, atomic persistence for `AppSettings`.
public actor SettingsStore {
    private let url: URL
    private var settings: AppSettings
    private var saveTask: Task<Void, Never>?

    public init(url: URL = AppPaths.settings) {
        self.url = url
        self.settings = Self.load(from: url) ?? AppSettings()
    }

    public var current: AppSettings { settings }

    public func update(_ mutate: @Sendable (inout AppSettings) -> Void) {
        mutate(&settings)
        scheduleSave()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = settings
        let target = url
        saveTask = Task {
            // Debounced: a slider being dragged would otherwise write a file
            // per frame.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            Self.write(snapshot, to: target)
        }
    }

    /// Forces a write now — on quit, where the debounce would lose the change.
    public func flush() {
        saveTask?.cancel()
        Self.write(settings, to: url)
    }

    private static func load(from url: URL) -> AppSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    private static func write(_ settings: AppSettings, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Atomic, so a crash mid-write leaves the previous settings rather
        // than a truncated file that fails to decode on next launch.
        try? data.write(to: url, options: .atomic)
    }
}
