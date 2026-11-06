import Foundation

/// Features switched off in this build, with their code left in the tree.
///
/// A flag here is a decision that has been made but not yet made permanent.
/// The alternative is deleting the feature, which throws away the reasoning
/// along with the code and makes reinstating it an archaeology exercise.
public enum FeatureFlags {
    /// Notifications: the bell, the alert centre, the banners, the sounds and
    /// the per-connection settings.
    ///
    /// Off because the feature was entirely server-driven and there is no
    /// longer a server side to drive it. The cron polled each provider with
    /// the credential it held, evaluated the rules and wrote a feed the Mac
    /// read back from `/v1/notifications`. Credentials now live in this Mac's
    /// Keychain and never reach that server, so there is nothing left to
    /// poll with.
    ///
    /// Bringing it back means evaluating rules here instead: the local
    /// scheduler already fetches every widget's number, so a threshold rule
    /// is within reach. The event-sourced ones — a failed payment, a
    /// cancelled subscription — need each adapter's `fetchEvents`, which has
    /// not been ported.
    ///
    /// Read at the entry points rather than around every view, so the code
    /// behind it keeps compiling and keeps being type-checked. A feature that
    /// quietly stops building is one that cannot be switched back on.
    public static let alertsEnabled = false
}
