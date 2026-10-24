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
    /// Zero: the notch opens the instant the pointer reaches it.
    ///
    /// A dwell debounces a pointer travelling to the menu bar, and the cost is
    /// that the notch always feels a beat behind the cursor. Instant is the
    /// better default; this stays configurable for anyone who disagrees.
    public var hoverDwellMilliseconds: Int = 0
    /// Zero as well, so it closes the moment the pointer leaves.
    public var collapseDelayMilliseconds: Int = 0
    public var reduceMotionOverride: Bool? = nil
    /// Plugins the user has enabled, each pinned to the digest that was
    /// approved. An agent can drop a file into Application Support; it should
    /// not thereby start making network calls.
    ///
    /// A map rather than the `Set<String>` this was, because a set approves an
    /// **id** and the contents behind an id can be rewritten afterwards — by
    /// the same agent, including its `allowedHosts`. Pinning the digest means
    /// a rewrite has to be approved again, which is the only version of this
    /// gate that holds for longer than a moment.
    public var approvedPlugins: [String: String] = [:]
    public var checkForUpdatesAutomatically: Bool = true

    // MARK: Notifications

    /// How long a notification banner stays out of the notch. Zero turns
    /// banners off and leaves the bell's badge as the only surface.
    public var alertBannerSeconds: Int = 4
    /// Whether to show the in-notch banner at all. Separate from the seconds so
    /// turning banners off and on again remembers the duration.
    public var alertBannersEnabled: Bool = true

    /// What a notification sounds like when it drops.
    ///
    /// Silent by default, deliberately. The banner already arrives unprompted
    /// and is visible on its own; adding audio to every existing install on an
    /// update is the kind of change that gets reported as a bug rather than
    /// noticed as a feature. The picker previews each one, so turning it on is
    /// a single informed choice.
    public var alertSound: AlertSound = .none

    public init() {}

    /// Decoded field by field, every one optional, each falling back to the
    /// default above.
    ///
    /// **Not** the synthesised initialiser, and this is load-bearing rather
    /// than style. Swift's synthesised `init(from:)` ignores property defaults
    /// and throws `keyNotFound` for any key the file does not have — so the
    /// moment a release adds a preference, every *existing* user's
    /// `settings.json` fails to decode, `SettingsStore.load` returns nil, and
    /// the app silently resets launch-at-login, their display choice, their
    /// hover timings and their approved plugins along with it.
    ///
    /// That is a one-line change away at all times, so it is written out in
    /// full here and pinned by `AppSettingsTests.oldFileKeepsItsValues`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings()

        func value<T: Decodable>(_ key: CodingKeys, _ default: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? `default`
        }

        schemaVersion = value(.schemaVersion, fallback.schemaVersion)
        displayPolicy = value(.displayPolicy, fallback.displayPolicy)
        showInFullscreen = value(.showInFullscreen, fallback.showInFullscreen)
        showMenuBarIcon = value(.showMenuBarIcon, fallback.showMenuBarIcon)
        launchAtLogin = value(.launchAtLogin, fallback.launchAtLogin)
        hoverDwellMilliseconds = value(.hoverDwellMilliseconds, fallback.hoverDwellMilliseconds)
        collapseDelayMilliseconds = value(
            .collapseDelayMilliseconds, fallback.collapseDelayMilliseconds)
        // Genuinely optional rather than defaulted: nil means "follow the
        // system", which is not the same as either true or false.
        reduceMotionOverride = try? c.decodeIfPresent(Bool.self, forKey: .reduceMotionOverride)
        // No migration from the old `approvedPluginIDs`, deliberately. Those
        // recorded an id and no digest, so honouring one would mean approving
        // whatever happens to be on disk now — the exact thing the digest
        // exists to prevent. Re-approval costs a toggle, and the custom-metric
        // path has never shipped, so in practice there is nothing to migrate.
        approvedPlugins = value(.approvedPlugins, fallback.approvedPlugins)
        checkForUpdatesAutomatically = value(
            .checkForUpdatesAutomatically, fallback.checkForUpdatesAutomatically)
        alertBannerSeconds = value(.alertBannerSeconds, fallback.alertBannerSeconds)
        alertBannersEnabled = value(.alertBannersEnabled, fallback.alertBannersEnabled)
        alertSound = value(.alertSound, fallback.alertSound)
    }
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
