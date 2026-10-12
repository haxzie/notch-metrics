import Foundation
import MetricsCore

/// What a feed reports upwards.
public enum AlertFeedEvent: Sendable {
    case page(AlertFeedPage)
    /// The server told us how often to ask. A floor on whatever the energy
    /// gate wants, because only the server knows the cron's stagger.
    case cadence(Duration)
    /// Plain language, for the pane's status line — not an error code.
    case degraded(String)
    /// The token is gone. Stop, do not back off: retrying an expired token on
    /// a backoff curve is a quiet way to lock an account.
    case unauthorized
}

/// The one transport seam.
///
/// Polling today; long-poll, SSE, a WebSocket or an APNs-triggered fetch all
/// satisfy this and nothing above it needs to know which is running. The
/// cursor is owned by `AlertInbox` rather than by the feed, which is what makes
/// swapping one implementation for another lossless.
public protocol AlertFeed: Actor {
    func start(from cursor: Int) async
    func stop() async
    /// A hint, not a command. Polling treats it as "ask now"; a streaming
    /// implementation would treat it as "reconnect if the socket is dead".
    func pokeNow() async
    func setCadence(_ cadence: Cadence) async
    /// Created once in `init`. A computed property that makes a new stream per
    /// access would give two callers half the events each.
    ///
    /// `nonisolated` because it is a constant: the owner has to be able to
    /// start iterating without first hopping onto the actor, and hopping would
    /// mean the loop could miss events yielded in between.
    nonisolated var events: AsyncStream<AlertFeedEvent> { get }
}

/// The polling implementation.
public actor PollingAlertFeed: AlertFeed {
    private let api: APIClient
    private let continuation: AsyncStream<AlertFeedEvent>.Continuation
    public nonisolated let events: AsyncStream<AlertFeedEvent>

    private var loop: Task<Void, Never>?
    private var cursor: Int = 0
    private var cadence: Cadence = .every(.seconds(300))
    /// The server's floor, held separately so an energy change cannot widen a
    /// poll past what the server asked for — or narrow it inside that.
    private var serverFloor: Duration = .seconds(300)
    private var backoff: Int = 0
    private var lastFetch: Date = .distantPast

    public init(api: APIClient) {
        self.api = api
        var sink: AsyncStream<AlertFeedEvent>.Continuation!
        self.events = AsyncStream { sink = $0 }
        self.continuation = sink
    }

    public func start(from cursor: Int) {
        self.cursor = cursor
        loop?.cancel()
        loop = Task { [weak self] in
            await self?.run()
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    public func setCadence(_ cadence: Cadence) {
        let previous = self.cadence
        self.cadence = cadence
        // Coming out of suspension fires exactly one immediate fetch. Without
        // this the loop would wait out a full interval it was never sleeping
        // through — the thing that makes a naive timer feel broken on wake.
        if previous == .suspended, cadence != .suspended {
            Task { await self.pokeNow() }
        }
    }

    public func pokeNow() async {
        // Throttled, because wake, screen-unlock and network-up all fire within
        // a second of each other and three pokes would be three fetches.
        guard Date().timeIntervalSince(lastFetch) > 2 else { return }
        await fetch()
    }

    private func run() async {
        while !Task.isCancelled {
            if case .every(let interval) = cadence {
                await fetch()
                // Jittered, so ten thousand Macs do not align on the minute.
                let jitter = Double.random(in: 0.85...1.15)
                let seconds = Double(interval.components.seconds) * jitter
                try? await Task.sleep(for: .seconds(seconds))
            } else {
                // Suspended. Idle here rather than spinning; `setCadence`
                // pokes when conditions change.
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func fetch() async {
        lastFetch = Date()
        do {
            // The cursor poll first: a few hundred bytes to learn whether the
            // feed is worth asking for at all. Most polls stop here.
            let cursorState = try await api.alertCursor()
            serverFloor = .seconds(Int64(cursorState.pollAfterSeconds))
            continuation.yield(.cadence(serverFloor))
            applyFloor()

            guard cursorState.seq > cursor else {
                backoff = 0
                return
            }

            let page = try await api.alerts(since: cursor)
            cursor = max(cursor, page.seq)
            backoff = 0
            continuation.yield(.page(page))
        } catch APIError.unauthorized {
            // Escalation is `AuthStore`'s job; this feed's job is to stop.
            continuation.yield(.unauthorized)
            stop()
        } catch APIError.rateLimited(let retryAfter) {
            // Obeyed literally when the server says how long.
            try? await Task.sleep(for: .seconds(retryAfter ?? 60))
        } catch APIError.offline {
            // Not a degradation worth showing: the energy gate suspends on a
            // lost path anyway, and a banner saying "offline" while the user
            // can see their Wi-Fi is off is noise.
            backoff = min(backoff + 1, 6)
        } catch {
            backoff = min(backoff + 1, 6)
            continuation.yield(.degraded("Couldn't check for notifications."))
            try? await Task.sleep(for: .seconds(min(1 << backoff, 60)))
        }
    }

    /// The server's floor wins over anything the energy gate asked for.
    private func applyFloor() {
        guard case .every(let interval) = cadence else { return }
        if interval < serverFloor { cadence = .every(serverFloor) }
    }
}
