import Foundation

/// How often the app is allowed to do network work, as a pure function of the
/// machine's state.
///
/// Split deliberately: the *decision* lives here with no imports beyond
/// Foundation, so every row of the cadence table is a unit test. The *sensing*
/// — IOKit, AppKit notifications, `NWPathMonitor` — lives in the app target,
/// where it is thin enough that there is nothing to test but the wiring.
///
/// This exists because the app had no battery awareness at all: the metrics
/// refresh was a bare `while { await refresh(); try? await Task.sleep(300) }`,
/// running on battery, in Low Power Mode, with the lid shut and the Wi-Fi off.
/// Adding a second always-on loop beside it would have doubled that.
public struct EnergyConditions: Sendable, Equatable {
    public var onBattery: Bool
    /// Nil when unknown — not every Mac has a battery.
    public var batteryPercent: Int?
    public var lowPowerMode: Bool
    /// `.serious` or `.critical`.
    public var thermalPressure: Bool
    public var displayAsleep: Bool
    public var systemAsleep: Bool
    /// False during a fast user switch.
    public var sessionActive: Bool
    public var screenLocked: Bool
    public var networkSatisfied: Bool
    /// A personal hotspot.
    public var networkExpensive: Bool
    /// Low Data Mode.
    public var networkConstrained: Bool
    /// The notch is open, so the user is looking at it.
    public var notchExpanded: Bool

    public init(
        onBattery: Bool = false,
        batteryPercent: Int? = nil,
        lowPowerMode: Bool = false,
        thermalPressure: Bool = false,
        displayAsleep: Bool = false,
        systemAsleep: Bool = false,
        sessionActive: Bool = true,
        screenLocked: Bool = false,
        networkSatisfied: Bool = true,
        networkExpensive: Bool = false,
        networkConstrained: Bool = false,
        notchExpanded: Bool = false
    ) {
        self.onBattery = onBattery
        self.batteryPercent = batteryPercent
        self.lowPowerMode = lowPowerMode
        self.thermalPressure = thermalPressure
        self.displayAsleep = displayAsleep
        self.systemAsleep = systemAsleep
        self.sessionActive = sessionActive
        self.screenLocked = screenLocked
        self.networkSatisfied = networkSatisfied
        self.networkExpensive = networkExpensive
        self.networkConstrained = networkConstrained
        self.notchExpanded = notchExpanded
    }
}

public enum Cadence: Sendable, Equatable {
    /// Suspended, with **no backlog**. Coming out of this fires exactly one
    /// immediate fetch — which is the failure mode of a naive sleep loop that
    /// wakes to find twelve overdue iterations.
    case suspended
    case every(Duration)

    public var interval: Duration? {
        switch self {
        case .suspended: return nil
        case .every(let d): return d
        }
    }
}

public enum EnergyPolicy {
    /// Nothing polls faster than this, whatever the conditions say.
    static let alertFloor = Duration.seconds(60)

    /// Why work is suspended, for the status line in Settings — a cadence the
    /// user cannot see is a bug report nobody can write.
    public static func suspensionReason(_ c: EnergyConditions) -> String? {
        if c.systemAsleep { return "asleep" }
        if !c.networkSatisfied { return "offline" }
        if !c.sessionActive { return "another user is signed in" }
        if c.displayAsleep { return "the display is asleep" }
        if c.screenLocked { return "the screen is locked" }
        return nil
    }

    /// How often to ask whether there are new notifications.
    ///
    /// `serverFloor` is the Worker's `x-notch-poll-after`, and it **wins over
    /// anything this computes**: only the server knows the cron's stagger, so
    /// polling faster than it evaluates produces literally nothing.
    public static func alertCadence(
        _ c: EnergyConditions,
        serverFloor: Duration = .seconds(300)
    ) -> Cadence {
        if suspensionReason(c) != nil { return .suspended }

        // Low Power Mode, thermal pressure and a metered link all mean the same
        // thing: stop asking. Notifications still arrive on the metrics batch,
        // which rides along at no extra cost.
        if c.lowPowerMode || c.thermalPressure || c.networkExpensive || c.networkConstrained {
            return .suspended
        }

        let wanted: Duration
        if let percent = c.batteryPercent, c.onBattery, percent <= 20 {
            wanted = .seconds(600)
        } else if c.onBattery {
            wanted = c.notchExpanded ? .seconds(60) : .seconds(180)
        } else {
            wanted = c.notchExpanded ? .seconds(30) : .seconds(60)
        }

        return .every(max(wanted, max(serverFloor, Self.alertFloor)))
    }

    /// How often to refetch the metrics the notch displays.
    ///
    /// A poll is not the same as a provider call: the Worker answers most of
    /// these from its cache, and each metric's own freshness decides when that
    /// cache is re-read — a payment every 60s, a Search Console figure that is
    /// itself two days behind on the slow TTL. So asking more often costs a
    /// cheap round trip, not somebody's rate limit, and the numbers that can
    /// move actually move.
    ///
    /// Still gated hard on power, because the round trip is cheap and the
    /// *radio* is not.
    public static func metricCadence(_ c: EnergyConditions) -> Cadence {
        if suspensionReason(c) != nil { return .suspended }
        if c.lowPowerMode || c.thermalPressure { return .every(.seconds(900)) }
        if c.networkExpensive || c.networkConstrained { return .every(.seconds(900)) }
        if let percent = c.batteryPercent, c.onBattery, percent <= 20 {
            return .every(.seconds(900))
        }
        // Looking at it: match the fastest thing the server will serve, so an
        // open notch is as live as the data can be.
        if c.notchExpanded { return .every(.seconds(30)) }
        // On battery the radio cost is the whole argument, and a number nobody
        // is looking at does not need to be a minute old.
        if c.onBattery { return .every(.seconds(180)) }
        return .every(.seconds(60))
    }
}

/// `Duration` is Comparable but has no `max`, and the floors above read far
/// worse written as ternaries.
private func max(_ a: Duration, _ b: Duration) -> Duration { a > b ? a : b }
