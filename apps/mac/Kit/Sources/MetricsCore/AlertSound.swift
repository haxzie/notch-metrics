import Foundation

/// The sound a notification arrives with.
///
/// A curated shortlist rather than the whole of `/System/Library/Sounds`.
/// Fourteen are installed, but most are alert tones designed to interrupt —
/// Basso and Sosumi are error sounds, Funk and Frog are jokes — and offering
/// them all makes a picker where most choices are wrong. These are the ones
/// that read as "something arrived" rather than "something broke".
///
/// A raw-value enum rather than a bare string, so a sound removed from a future
/// macOS falls back to silence instead of failing to decode `settings.json` and
/// taking every other preference with it.
public enum AlertSound: String, Codable, Sendable, CaseIterable, Identifiable {
    case none
    case tink
    case pop
    case bottle
    case glass
    case ping
    case purr
    case submarine
    case hero

    public var id: String { rawValue }

    /// The file in `/System/Library/Sounds`, or nil for silence.
    public var systemName: String? {
        switch self {
        case .none: return nil
        case .tink: return "Tink"
        case .pop: return "Pop"
        case .bottle: return "Bottle"
        case .glass: return "Glass"
        case .ping: return "Ping"
        case .purr: return "Purr"
        case .submarine: return "Submarine"
        case .hero: return "Hero"
        }
    }

    public var label: String {
        switch self {
        case .none: return "None"
        case .tink: return "Tink"
        case .pop: return "Pop"
        case .bottle: return "Bottle"
        case .glass: return "Glass"
        case .ping: return "Ping"
        case .purr: return "Purr"
        case .submarine: return "Submarine"
        case .hero: return "Hero"
        }
    }

    /// One line in the picker, because a name alone does not tell anybody what
    /// they are about to inflict on themselves every time a payment lands.
    public var summary: String {
        switch self {
        case .none: return "Silent"
        case .tink: return "A short tick. The least you can hear."
        case .pop: return "A soft bubble. Quiet but present."
        case .bottle: return "A rounded blip, a little warmer than Pop."
        case .glass: return "The classic chime. Noticeable."
        case .ping: return "A clear bell. Carries across a room."
        case .purr: return "A low ripple. Easy to miss on purpose."
        case .submarine: return "A deep sonar note. The most dramatic."
        case .hero: return "A rising flourish. Celebratory, and a lot."
        }
    }

    /// Unknown values decode to silence rather than failing.
    ///
    /// Same bargain as every other enum crossing a boundary here: one sound
    /// removed by Apple must not cost the user their whole settings file.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AlertSound(rawValue: raw) ?? .none
    }
}
