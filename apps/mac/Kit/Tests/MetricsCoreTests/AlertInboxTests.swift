import Foundation
import Testing

@testable import MetricsCore

/// `AlertInbox` and `EnergyPolicy` — the two pieces of the notification feature
/// that are pure enough to test without a window or a network.
struct AlertInboxTests {
    /// An isolated inbox per test. `NOTCH_SUPPORT_DIR` exists for this, but a
    /// temporary URL is more direct and lets tests run in parallel.
    private func inbox() -> (AlertInbox, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alerts-\(UUID().uuidString).json")
        return (AlertInbox(url: url), url)
    }

    private func alert(
        _ id: String,
        seq: Int,
        ago: TimeInterval = 0,
        integrationId: String? = "int_1",
        read: Bool = false,
        alert raise: Bool = true
    ) -> NotchAlert {
        NotchAlert(
            id: id,
            seq: seq,
            integrationId: integrationId,
            provider: "stripe",
            connectionLabel: "Acme",
            typeId: "payment_received",
            severity: .success,
            title: "Payment \(id)",
            body: nil,
            amount: 100,
            currency: "USD",
            url: nil,
            occurredAt: ISO8601.string(from: Date().addingTimeInterval(-ago)),
            createdAt: ISO8601.string(from: Date().addingTimeInterval(-ago)),
            read: read,
            alert: raise)
    }

    private func page(
        _ items: [NotchAlert],
        seq: Int? = nil,
        hasMore: Bool = false,
        oldestSeq: Int? = nil,
        truncated: Bool = false
    ) -> AlertFeedPage {
        AlertFeedPage(
            seq: seq ?? (items.map(\.seq).max() ?? 0),
            unread: items.filter { !$0.read }.count,
            items: items,
            connections: [
                AlertConnectionSummary(
                    integrationId: "int_1", provider: "stripe", label: "Acme",
                    unread: items.count, total: items.count)
            ],
            hasMore: hasMore,
            oldestSeq: oldestSeq,
            truncated: truncated,
            pollAfterSeconds: 300)
    }

    @Test("a re-delivered row is not a new row")
    func dedupes() async {
        let (box, _) = inbox()
        let first = await box.merge(page([alert("a", seq: 1), alert("b", seq: 2)]))
        #expect(first.arrived.count == 2)

        // The same page again — which happens whenever a cursor is replayed.
        let second = await box.merge(page([alert("a", seq: 1), alert("b", seq: 2)]))
        #expect(second.arrived.isEmpty)
        #expect(second.snapshot.alerts.count == 2)
    }

    @Test("the cap keeps the newest, and never regresses the cursor")
    func capsAndHoldsCursor() async {
        let (box, _) = inbox()
        // Oldest first, so if the cap kept the wrong end it would be obvious.
        let many = (0..<250).map { alert("a\($0)", seq: $0 + 1, ago: Double(250 - $0) * 60) }
        _ = await box.merge(page(many))

        let snapshot = await box.snapshot()
        #expect(snapshot.alerts.count == AlertInbox.maxAlerts)
        #expect(snapshot.alerts.first?.id == "a249")
        #expect(await box.cursor == 250)

        // A page that arrives out of order must not rewind the cursor and
        // re-deliver everything after it.
        _ = await box.merge(page([alert("late", seq: 5)], seq: 5))
        #expect(await box.cursor == 250)
    }

    @Test("rows older than the retention window are pruned, with their read ids")
    func prunes() async {
        let (box, url) = inbox()
        let old = alert("old", seq: 1, ago: 40 * 86_400)
        let recent = alert("recent", seq: 2)
        _ = await box.merge(page([old, recent]))
        await box.markRead(["old", "recent"])

        let snapshot = await box.snapshot()
        #expect(snapshot.alerts.map(\.id) == ["recent"])
        #expect(await box.unreadCount(in: .all) == 0)

        // The read-id set is pruned to the surviving rows, or the file grows
        // forever holding ids of alerts that are gone. Observable only through
        // the file, so assert on the file.
        await box.flush()
        let raw = try! #require(try? Data(contentsOf: url))
        let text = String(decoding: raw, as: UTF8.self)
        #expect(text.contains("recent"))
        #expect(!text.contains("\"old\""), "a pruned alert's read id was kept")
    }

    @Test("read state survives a relaunch")
    func persists() async {
        let (box, url) = inbox()
        _ = await box.merge(page([alert("a", seq: 1), alert("b", seq: 2)]))
        await box.markRead(["a"])
        await box.flush()

        let reopened = AlertInbox(url: url)
        let snapshot = await reopened.snapshot()
        #expect(snapshot.alerts.count == 2)
        // Losing this means every notification the user already triaged comes
        // back unread.
        #expect(snapshot.unread == 1)
        #expect(await reopened.cursor == 2)
    }

    @Test("a corrupt file yields an empty inbox rather than throwing")
    func survivesCorruption() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("alerts-corrupt-\(UUID().uuidString).json")
        try? Data("{ not json at all".utf8).write(to: url)

        let box = AlertInbox(url: url)
        #expect(await box.snapshot().alerts.isEmpty)
        #expect(await box.cursor == 0)
    }

    @Test("marking a connection read leaves the others alone")
    func scopedRead() async {
        let (box, _) = inbox()
        _ = await box.merge(
            page([
                alert("a", seq: 1, integrationId: "int_1"),
                alert("b", seq: 2, integrationId: "int_2"),
            ]))

        await box.markAllRead(in: .connection("int_1"))
        #expect(await box.unreadCount(in: .connection("int_1")) == 0)
        #expect(await box.unreadCount(in: .connection("int_2")) == 1)
        #expect(await box.unreadCount(in: .all) == 1)
    }
}

/// The banner decision, which is the single most important rule in the feature:
/// a laptop opened after a long sleep must not fire a banner per row.
struct AlertBannerDecisionTests {
    private func inbox() -> AlertInbox {
        AlertInbox(
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent("alerts-\(UUID().uuidString).json"))
    }

    private func alert(_ id: String, ago: TimeInterval, raise: Bool = true) -> NotchAlert {
        NotchAlert(
            id: id, seq: Int(abs(ago)) + 1, integrationId: "int_1", provider: "stripe",
            connectionLabel: "Acme", typeId: "payment_received", severity: .success,
            title: id, body: nil, amount: nil, currency: nil, url: nil,
            occurredAt: ISO8601.string(from: Date().addingTimeInterval(-ago)),
            createdAt: ISO8601.string(from: Date().addingTimeInterval(-ago)),
            read: false, alert: raise)
    }

    private func page(_ items: [NotchAlert], truncated: Bool = false) -> AlertFeedPage {
        AlertFeedPage(
            seq: items.map(\.seq).max() ?? 0, unread: items.count, items: items,
            connections: [], hasMore: false, oldestSeq: nil, truncated: truncated,
            pollAfterSeconds: 300)
    }

    @Test("a handful of fresh rows banner individually")
    func fewFreshRows() async {
        let outcome = await inbox().merge(page([alert("a", ago: 10), alert("b", ago: 20)]))
        #expect(outcome.arrived.count == 2)
        #expect(!outcome.collapsed)
    }

    @Test("a burst collapses to one summary")
    func burstCollapses() async {
        let many = (0..<47).map { alert("a\($0)", ago: Double($0)) }
        let outcome = await inbox().merge(page(many))

        // Not 47 banners.
        #expect(outcome.arrived.isEmpty)
        #expect(outcome.collapsed)
        // But all of them are still readable in the pane.
        #expect(outcome.snapshot.alerts.count == 47)
    }

    @Test("stale rows never banner, however few there are")
    func staleNeverBanners() async {
        // One row, but eight hours old: the laptop was asleep, not idle.
        let outcome = await inbox().merge(page([alert("a", ago: 8 * 3_600)]))
        #expect(outcome.arrived.isEmpty)
        #expect(!outcome.collapsed)
        #expect(outcome.snapshot.alerts.count == 1)
    }

    @Test("a row raised inside quiet hours is filed, not raised")
    func quietHoursRowIsFiled() async {
        let outcome = await inbox().merge(page([alert("a", ago: 10, raise: false)]))
        #expect(outcome.arrived.isEmpty)
        #expect(outcome.snapshot.alerts.count == 1)
    }

    @Test("the server's truncated flag collapses regardless of count")
    func serverTruncationWins() async {
        let outcome = await inbox().merge(page([alert("a", ago: 5)], truncated: true))
        #expect(outcome.arrived.isEmpty)
        #expect(outcome.collapsed)
    }

    @Test("a history page never banners")
    func historyIsSilent() async {
        let box = inbox()
        _ = await box.merge(page([alert("a", ago: 10)]))
        // `append` has no banner path at all — scrolling back is not news.
        let snapshot = await box.append(page([alert("old", ago: 3_600)]))
        #expect(snapshot.alerts.count == 2)
    }
}

/// One assertion per row of the cadence table.
struct EnergyPolicyTests {
    @Test("on AC it polls briskly, and faster still with the notch open")
    func onAC() {
        let idle = EnergyConditions(onBattery: false)
        #expect(EnergyPolicy.alertCadence(idle, serverFloor: .seconds(60)) == .every(.seconds(60)))

        let looking = EnergyConditions(onBattery: false, notchExpanded: true)
        #expect(
            EnergyPolicy.alertCadence(looking, serverFloor: .seconds(30)) == .every(.seconds(60)),
            "the 60s floor still applies")
    }

    @Test("the server's floor wins over anything the power state wants")
    func serverFloorWins() {
        let looking = EnergyConditions(onBattery: false, notchExpanded: true)
        // Only the server knows the cron's stagger: polling faster than it
        // evaluates produces literally nothing.
        #expect(
            EnergyPolicy.alertCadence(looking, serverFloor: .seconds(3600))
                == .every(.seconds(3600)))
    }

    @Test("on battery it backs off, and further still when nearly flat")
    func onBattery() {
        let battery = EnergyConditions(onBattery: true, batteryPercent: 80)
        #expect(
            EnergyPolicy.alertCadence(battery, serverFloor: .seconds(60)) == .every(.seconds(180)))

        let flat = EnergyConditions(onBattery: true, batteryPercent: 15)
        #expect(
            EnergyPolicy.alertCadence(flat, serverFloor: .seconds(60)) == .every(.seconds(600)))
        #expect(EnergyPolicy.metricCadence(flat) == .every(.seconds(900)))
    }

    @Test("Low Power Mode and thermal pressure stop the poll entirely")
    func suspendsOnPowerPressure() {
        // Notifications still arrive on the metrics batch, which rides along at
        // no extra cost — so stopping here loses nothing but the latency.
        #expect(EnergyPolicy.alertCadence(EnergyConditions(lowPowerMode: true)) == .suspended)
        #expect(EnergyPolicy.alertCadence(EnergyConditions(thermalPressure: true)) == .suspended)
        #expect(EnergyPolicy.metricCadence(EnergyConditions(lowPowerMode: true)) == .every(.seconds(900)))
    }

    @Test("a metered link is not polled over")
    func suspendsOnMeteredNetwork() {
        #expect(EnergyPolicy.alertCadence(EnergyConditions(networkExpensive: true)) == .suspended)
        #expect(EnergyPolicy.alertCadence(EnergyConditions(networkConstrained: true)) == .suspended)
    }

    @Test("everything stops when nobody is there, and says why")
    func suspendsWhenAway() {
        let cases: [(EnergyConditions, String)] = [
            (EnergyConditions(systemAsleep: true), "asleep"),
            (EnergyConditions(networkSatisfied: false), "offline"),
            (EnergyConditions(sessionActive: false), "another user is signed in"),
            (EnergyConditions(displayAsleep: true), "the display is asleep"),
            (EnergyConditions(screenLocked: true), "the screen is locked"),
        ]

        for (conditions, reason) in cases {
            #expect(EnergyPolicy.alertCadence(conditions) == .suspended)
            // The metrics loop stops too — this is the part that was previously
            // a bare 300s timer running with the lid shut.
            #expect(EnergyPolicy.metricCadence(conditions) == .suspended)
            // Surfaced in Settings: a cadence the user cannot see is a bug
            // report nobody can write.
            #expect(EnergyPolicy.suspensionReason(conditions) == reason)
        }
    }

    @Test("a machine nobody is bothering has no reason to be suspended")
    func noReasonWhenActive() {
        #expect(EnergyPolicy.suspensionReason(EnergyConditions()) == nil)
    }
}
