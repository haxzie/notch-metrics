import Foundation
import Testing

@testable import MetricsCore

/// `settings.json` is written by one release and read by the next, so what
/// happens to a file that predates a new preference is a shipping concern
/// rather than a detail.
struct AppSettingsTests {
    /// A real settings file from before notifications existed.
    private let v1 = """
        {
          "approvedPluginIDs": ["github-stars"],
          "checkForUpdatesAutomatically": false,
          "collapseDelayMilliseconds": 120,
          "displayPolicy": { "builtIn": {} },
          "hoverDwellMilliseconds": 80,
          "launchAtLogin": false,
          "schemaVersion": 1,
          "showInFullscreen": false,
          "showMenuBarIcon": true
        }
        """

    @Test("a file written before a preference existed keeps everything else")
    func oldFileKeepsItsValues() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(v1.utf8))

        // The whole point. Swift's *synthesised* `init(from:)` ignores property
        // defaults and throws `keyNotFound` on any key the file lacks — so
        // without the hand-written one in `Settings.swift`, adding a single
        // preference silently resets every other preference the user has ever
        // set, on the release that adds it.
        #expect(settings.launchAtLogin == false)
        #expect(settings.showMenuBarIcon == true)
        #expect(settings.showInFullscreen == false)
        #expect(settings.hoverDwellMilliseconds == 80)
        #expect(settings.collapseDelayMilliseconds == 120)
        #expect(settings.checkForUpdatesAutomatically == false)

        // ...and the one preference that deliberately does *not* carry over.
        // `approvedPluginIDs` recorded an id with no digest, so honouring it
        // would approve whatever is on disk now rather than what the user
        // actually said yes to. Re-approval is a toggle; silently blessing
        // rewritten code is not recoverable. Every other value above still
        // survives, which is what this test is really guarding.
        #expect(settings.approvedPlugins == [:])

        // And the preferences that file has never heard of take their defaults.
        #expect(settings.alertBannersEnabled == true)
        #expect(settings.alertBannerSeconds == 4)
        #expect(settings.alertSound == .none)
    }

    @Test("an empty object decodes to the defaults rather than throwing")
    func emptyObjectIsAllDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings == AppSettings())
    }

    @Test("a preference round-trips through the file format")
    func roundTrips() throws {
        var settings = AppSettings()
        settings.alertSound = .glass
        settings.alertBannerSeconds = 9
        settings.approvedPlugins = ["a": "deadbeef", "b": "cafebabe"]
        settings.reduceMotionOverride = true

        let again = try JSONDecoder().decode(
            AppSettings.self, from: try JSONEncoder().encode(settings))
        #expect(again == settings)
        // Nil is a third state here — "follow the system" — so it has to
        // survive as nil rather than collapsing to false.
        var noOverride = settings
        noOverride.reduceMotionOverride = nil
        let decoded = try JSONDecoder().decode(
            AppSettings.self, from: try JSONEncoder().encode(noOverride))
        #expect(decoded.reduceMotionOverride == nil)
    }

    @Test("a sound this build has never heard of falls back to silence")
    func unknownSoundFallsBack() throws {
        // A sound removed by a future macOS, or written by a newer build, must
        // not cost the user the rest of their settings file.
        let json = #"{"alertSound":"a_sound_from_the_future","launchAtLogin":false}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.alertSound == .none)
        #expect(settings.launchAtLogin == false)
    }

    @Test("every offered sound names a file the system actually ships")
    func soundsExist() {
        for sound in AlertSound.allCases {
            guard let name = sound.systemName else { continue }
            let path = "/System/Library/Sounds/\(name).aiff"
            // A picker entry that plays nothing is worse than one fewer choice.
            #expect(
                FileManager.default.fileExists(atPath: path),
                "\(sound.label) names \(path), which is not installed")
        }
    }
}
