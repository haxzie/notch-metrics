import AppKit
import MetricsCore

/// Plays a notification's sound.
///
/// In the app target rather than in `NotchUI`, so the controller stays a view
/// layer that knows nothing about preferences — the same split the banner's
/// text and duration already use.
@MainActor
enum AlertSoundPlayer {
    /// Held across plays so a previously started sound is stopped first.
    ///
    /// `NSSound.play()` on a fresh instance each time lets two overlap, which
    /// is exactly what a burst of notifications would do — and two Pings a
    /// tenth of a second apart sound like a fault rather than two payments.
    private static var current: NSSound?

    static func play(_ sound: AlertSound) {
        guard let name = sound.systemName else { return }
        // `NSSound(named:)` resolves from /System/Library/Sounds and the app
        // bundle. A sound Apple has removed returns nil rather than throwing,
        // and silence is the right outcome.
        guard let next = NSSound(named: name) else { return }

        current?.stop()
        current = next
        next.play()
    }
}
