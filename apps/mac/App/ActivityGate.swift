import AppKit
import IOKit.ps
import MetricsCore
import Network
import Observation

/// Senses the machine's power, display and network state and publishes it.
///
/// Thin on purpose: every *decision* is in `EnergyPolicy`, which is a pure
/// function of `EnergyConditions` and therefore table-tested. All that is here
/// is the AppKit, IOKit and Network plumbing that cannot be tested without a
/// real machine, kept small enough that there is nothing to test but the wiring.
@MainActor
@Observable
final class ActivityGate {
    private(set) var conditions = EnergyConditions()

    /// Called whenever anything changes, so the owner can re-pick cadences.
    var onChange: @MainActor (EnergyConditions) -> Void = { _ in }

    private var monitor: NWPathMonitor?
    private var observers: [any NSObjectProtocol] = []
    private var powerSource: CFRunLoopSource?

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter

        // Sleep and wake. The metrics loop had no answer for either: it kept a
        // 300s timer running with the lid shut, which on an eight-hour sleep is
        // ~96 wake-ups and 96 hits against the user's provider rate limit.
        observe(workspace, NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.systemAsleep = false }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displayAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displayAsleep = false }
        // A fast user switch: somebody else is using the machine.
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) {
            $0.sessionActive = false
        }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) {
            $0.sessionActive = true
        }

        // Screen lock is not a public notification. Treated as a nice-to-have
        // on top of `screensDidSleep` rather than a load-bearing signal, so if
        // it ever stops firing the gate still works.
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) {
            $0.screenLocked = true
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) {
            $0.screenLocked = false
        }

        observe(NotificationCenter.default, NSNotification.Name.NSProcessInfoPowerStateDidChange) {
            $0.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        observe(NotificationCenter.default, ProcessInfo.thermalStateDidChangeNotification) {
            let state = ProcessInfo.processInfo.thermalState
            $0.thermalPressure = state == .serious || state == .critical
        }

        startNetworkMonitor()
        startPowerSourceMonitor()
        refreshSampledState()
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
            self.powerSource = nil
        }
    }

    /// The notch being open means the user is looking at it.
    ///
    /// `NSWindow.occlusionState` is the wrong tool: the panel is a borderless
    /// always-on-top `NSPanel` fixed at `NotchPanel.maxSize`, so AppKit calls
    /// it visible whether collapsed or expanded.
    func setNotchExpanded(_ expanded: Bool) {
        guard conditions.notchExpanded != expanded else { return }
        conditions.notchExpanded = expanded
        onChange(conditions)
    }

    private func observe(
        _ centre: NotificationCenter, _ name: Notification.Name,
        _ apply: @escaping @MainActor (inout EnergyConditions) -> Void
    ) {
        let token = centre.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                apply(&self.conditions)
                self.onChange(self.conditions)
            }
        }
        observers.append(token)
    }

    private func observe(
        _ centre: DistributedNotificationCenter, _ name: Notification.Name,
        _ apply: @escaping @MainActor (inout EnergyConditions) -> Void
    ) {
        let token = centre.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                apply(&self.conditions)
                self.onChange(self.conditions)
            }
        }
        observers.append(token)
    }

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.conditions.networkSatisfied = path.status == .satisfied
                // A personal hotspot, and Low Data Mode. Neither is somewhere
                // to run a recurring poll.
                self.conditions.networkExpensive = path.isExpensive
                self.conditions.networkConstrained = path.isConstrained
                self.onChange(self.conditions)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.notchmetrics.path", qos: .utility))
        self.monitor = monitor
    }

    /// There is no `ProcessInfo` power-source API — only `isLowPowerModeEnabled`
    /// — so IOKit is the one public answer to "is this on battery".
    private func startPowerSourceMonitor() {
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let gate = Unmanaged<ActivityGate>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in gate.refreshSampledState() }
        }
        if let source = IOPSNotificationCreateRunLoopSource(
            callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
    }

    private func refreshSampledState() {
        conditions.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = ProcessInfo.processInfo.thermalState
        conditions.thermalPressure = thermal == .serious || thermal == .critical

        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        {
            let onAC =
                (IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String?)
                == kIOPMACPowerKey
            conditions.onBattery = !onAC

            // The first source with a capacity is the internal battery; a Mac
            // with none leaves `batteryPercent` nil, which the policy reads as
            // "do not apply the low-battery tier".
            for source in sources {
                guard
                    let description = IOPSGetPowerSourceDescription(blob, source)?
                        .takeUnretainedValue() as? [String: Any],
                    let current = description[kIOPSCurrentCapacityKey] as? Int,
                    let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
                else { continue }
                conditions.batteryPercent = Int((Double(current) / Double(max)) * 100)
                break
            }
        }
        onChange(conditions)
    }
}
