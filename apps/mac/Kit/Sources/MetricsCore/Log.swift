import Foundation
import OSLog

/// The app's loggers.
///
/// `os.Logger` rather than `print` or `NSLog`: it is off until somebody asks
/// for it, it survives into a sysdiagnose, and it is what
/// `log stream --predicate 'subsystem == "com.notchmetrics.app"'` reads — which
/// is the only way to see what a shipped, windowless, menu-bar-less app is
/// doing on somebody else's Mac.
public enum Log {
    private static let subsystem = AppPaths.bundleIdentifier

    /// Opening, closing, and display reconfiguration. The notch's behaviour is
    /// driven by pointer events nobody can reproduce on request, so this is
    /// the only way to find out why it opened when it should not have.
    public static let notch = Logger(subsystem: subsystem, category: "notch")
    public static let api = Logger(subsystem: subsystem, category: "api")
    public static let plugins = Logger(subsystem: subsystem, category: "plugins")
    public static let updater = Logger(subsystem: subsystem, category: "updater")
}
