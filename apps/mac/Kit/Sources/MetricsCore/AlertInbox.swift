import Foundation

/// What the pane renders: an immutable value, so the UI never holds the actor.
public struct AlertSnapshot: Sendable, Equatable {
    public var alerts: [NotchAlert]
    public var connections: [AlertConnectionSummary]
    public var unread: Int
    public var cursor: Int
    public var hasMore: Bool

    public init(
        alerts: [NotchAlert] = [],
        connections: [AlertConnectionSummary] = [],
        unread: Int = 0,
        cursor: Int = 0,
        hasMore: Bool = false
    ) {
        self.alerts = alerts
        self.connections = connections
        self.unread = unread
        self.cursor = cursor
        self.hasMore = hasMore
    }
}

/// What a merge produced, and specifically what may be bannered.
public struct AlertMergeOutcome: Sendable, Equatable {
    /// Post-dedupe, post-`lastSeen`. **The only thing allowed to raise a
    /// banner.**
    public var arrived: [NotchAlert]
    /// Too many at once to show one at a time — show a single summary instead.
    public var collapsed: Bool
    public var snapshot: AlertSnapshot

    public init(arrived: [NotchAlert], collapsed: Bool, snapshot: AlertSnapshot) {
        self.arrived = arrived
        self.collapsed = collapsed
        self.snapshot = snapshot
    }
}

public enum AlertScope: Sendable, Equatable {
    case all
    case connection(String)
}

/// The notification inbox: one file, one atomic write, like `layout.json`.
public actor AlertInbox {
    /// Hard cap. 200 × ~300 bytes is 60KB — the number matters less than the
    /// fact that it is bounded.
    static let maxAlerts = 200
    static let maxAgeDays = 30

    /// Above this many new rows in one merge, banners collapse to a summary.
    static let burstLimit = 3
    /// And nothing older than this is ever bannered, in any case.
    static let bannerHorizon: TimeInterval = 15 * 60

    private struct File: Codable, Sendable {
        var schemaVersion = 1
        var cursor: Int = 0
        /// When the pane was last opened. Decides *banner* suppression, which
        /// is a different question from read state.
        var lastSeenAt: String?
        var alerts: [NotchAlert] = []
        var readIDs: Set<String> = []
        var connections: [AlertConnectionSummary] = []
        var hasMore: Bool = false
    }

    private let url: URL
    private var file: File
    private var saveTask: Task<Void, Never>?

    public init(url: URL = AppPaths.alerts) {
        self.url = url
        self.file = Self.load(from: url) ?? File()
    }

    public var cursor: Int { file.cursor }

    public func snapshot() -> AlertSnapshot {
        // `readIDs` is projected on to the rows here rather than left for the
        // UI to consult separately. Every view renders unread from
        // `NotchAlert.read`, so without this a local mark-read moves only the
        // count in the sidebar and leaves the rows themselves bold and dotted.
        let rows = file.alerts.map { row -> NotchAlert in
            guard !row.read, file.readIDs.contains(row.id) else { return row }
            var copy = row
            copy.read = true
            return copy
        }

        // The server's per-connection counts predate those same local reads, so
        // they are netted against the ones it has not seen yet. Once the next
        // feed page comes back with `read` set, `pending` is empty and this is
        // the server's own number again.
        let pending = pendingReads()

        return AlertSnapshot(
            alerts: rows,
            connections: file.connections.map { summary in
                guard let id = summary.integrationId, let local = pending[id] else {
                    return summary
                }
                var copy = summary
                copy.unread = Swift.max(0, summary.unread - local)
                return copy
            },
            unread: rows.filter { !$0.read }.count,
            cursor: file.cursor,
            hasMore: file.hasMore)
    }

    /// Rows marked read locally that the server still reports as unread, by
    /// connection.
    private func pendingReads() -> [String: Int] {
        var counts: [String: Int] = [:]
        for alert in file.alerts where !alert.read && file.readIDs.contains(alert.id) {
            guard let id = alert.integrationId else { continue }
            counts[id, default: 0] += 1
        }
        return counts
    }

    private func isRead(_ alert: NotchAlert) -> Bool {
        alert.read || file.readIDs.contains(alert.id)
    }

    /// Folds a live-sync page in and reports what newly arrived.
    public func merge(_ page: AlertFeedPage) -> AlertMergeOutcome {
        let known = Set(file.alerts.map(\.id))
        let arrived = page.items.filter { !known.contains($0.id) }

        apply(page)

        // Two independent gates, because the server's `truncated` is a hint and
        // this one is not: banner individually only for a handful, and only for
        // things that actually just happened. A laptop opened after eight hours
        // asleep must produce a badge and at most one banner, never 47.
        let horizon = max(
            Self.lastSeen(file.lastSeenAt) ?? .distantPast,
            Date().addingTimeInterval(-Self.bannerHorizon))
        let fresh = arrived.filter { ($0.occurred ?? .distantPast) > horizon && $0.alert }
        let collapsed = page.truncated || fresh.count > Self.burstLimit

        return AlertMergeOutcome(
            arrived: collapsed ? [] : fresh,
            collapsed: collapsed && !fresh.isEmpty,
            snapshot: snapshot())
    }

    /// Folds a history page in. Never produces banners: scrolling back is not
    /// news, and must not suppress the banners for what arrives while you read.
    public func append(_ page: AlertFeedPage) -> AlertSnapshot {
        apply(page, advanceCursor: false)
        return snapshot()
    }

    private func apply(_ page: AlertFeedPage, advanceCursor: Bool = true) {
        var byID: [String: NotchAlert] = [:]
        for alert in file.alerts { byID[alert.id] = alert }
        // The server's copy wins on a conflict: it is authoritative for read
        // state and for the quiet-hours decision.
        for alert in page.items { byID[alert.id] = alert }

        let cutoff = Date().addingTimeInterval(-Double(Self.maxAgeDays) * 86_400)
        file.alerts =
            byID.values
            .filter { ($0.occurred ?? Date()) > cutoff }
            // Sorted on `occurredAt`, never on `seq`: a row found by a later
            // evaluation can carry a higher seq than an older one beside it.
            .sorted { ($0.occurred ?? .distantPast) > ($1.occurred ?? .distantPast) }
            .prefix(Self.maxAlerts)
            .map { $0 }

        // Pruned to the surviving set, or the file grows forever with the ids
        // of alerts that are gone.
        let surviving = Set(file.alerts.map(\.id))
        file.readIDs = file.readIDs.intersection(surviving)

        if !page.connections.isEmpty { file.connections = page.connections }
        file.hasMore = page.hasMore
        // Never regresses: a page that arrives out of order must not rewind the
        // cursor and re-deliver everything after it.
        if advanceCursor { file.cursor = Swift.max(file.cursor, page.seq) }
        scheduleSave()
    }

    public func markRead(_ ids: [String]) {
        // Intersected with what is actually held, so the invariant
        // `readIDs ⊆ alerts` holds after *every* mutation rather than only
        // after a merge. An id for a row that is already gone is a no-op, and
        // keeping it would leak a little state on every prune.
        let live = Set(file.alerts.map(\.id))
        file.readIDs.formUnion(ids.filter(live.contains))
        scheduleSave()
    }

    public func markAllRead(in scope: AlertScope) {
        switch scope {
        case .all:
            file.readIDs.formUnion(file.alerts.map(\.id))
        case .connection(let integrationId):
            file.readIDs.formUnion(
                file.alerts.filter { $0.integrationId == integrationId }.map(\.id))
        }
        scheduleSave()
    }

    public func unreadCount(in scope: AlertScope) -> Int {
        switch scope {
        case .all:
            return file.alerts.filter { !isRead($0) }.count
        case .connection(let integrationId):
            return file.alerts.filter { $0.integrationId == integrationId && !isRead($0) }.count
        }
    }

    /// Stamped when the pane is opened. Suppresses *banner* backfill only.
    public func stampSeen(_ date: Date = Date()) {
        file.lastSeenAt = ISO8601.string(from: date)
        scheduleSave()
    }

    /// Dropped on sign-out: the next account's notifications are not this one's.
    public func clear() {
        file = File()
        scheduleSave()
    }

    private static func lastSeen(_ raw: String?) -> Date? {
        raw.flatMap(ISO8601.parse)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = file
        let target = url
        saveTask = Task {
            // Same 500ms debounce as `SettingsStore`: marking ten rows read
            // should not write the file ten times.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            Self.write(snapshot, to: target)
        }
    }

    /// Forces a write now — on quit, where the debounce would lose the change.
    public func flush() {
        saveTask?.cancel()
        Self.write(file, to: url)
    }

    private static func load(from url: URL) -> File? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // A truncated or hand-edited file yields an empty inbox rather than
        // throwing: a corrupt cache must not stop the app launching.
        return try? JSONDecoder().decode(File.self, from: data)
    }

    private static func write(_ file: File, to url: URL) {
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Atomic, so a crash mid-write cannot leave a half-written inbox.
        try? data.write(to: url, options: .atomic)
    }
}
