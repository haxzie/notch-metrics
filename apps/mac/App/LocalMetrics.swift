import Foundation
import MetricsAPI
import MetricsCore
import Providers

/// Reading a widget's number on this Mac, with no Worker in the path.
///
/// The seam between `NotchWidget`, which is what the grid holds, and
/// `MetricWindow`, which is what an adapter takes. Everything the adapter is
/// not trusted with is resolved here: the window the range means, the unit
/// the catalogue declares, the timestamps on the answer. An adapter returns
/// a number and its points, and nothing else.
enum LocalMetrics {
    /// One widget's fetch, with everything it needs already read off the
    /// main actor.
    ///
    /// A struct rather than five arguments because it crosses into a task
    /// group: gathering the isolated state up front is what lets the fetches
    /// run in parallel instead of hopping back to the main actor one at a
    /// time for each field.
    struct Job: Sendable {
        let index: Int
        let widget: NotchWidget
        let connection: LocalConnection
        let unit: MetricUnit?
        let comparePrevious: Bool
        let credentials: [String: String]
    }

    static func fetch(_ job: Job, now: Date = Date()) async -> MetricResult {
        await fetch(
            widget: job.widget, connection: job.connection, unit: job.unit,
            comparePrevious: job.comparePrevious, now: now, credentials: job.credentials)
    }

    /// Answers one widget, or explains why it cannot.
    ///
    /// Never throws. The caller is filling a slot in a batch whose other
    /// entries came from the Worker, and a thrown error there would take the
    /// whole refresh down with one broken tile.
    static func fetch(
        widget: NotchWidget,
        connection: LocalConnection,
        unit: MetricUnit?,
        comparePrevious: Bool = false,
        now: Date = Date(),
        credentials: [String: String]
    ) async -> MetricResult {
        let metric = widget.metric ?? ""
        // The same window the Worker would have derived from the range. See
        // `TimeRange.duration`, which exists for exactly this.
        let to = now
        let from = now.addingTimeInterval(-widget.range.duration)

        let window = MetricWindow(
            metric: metric,
            from: from,
            to: to,
            granularity: widget.range.defaultGranularity,
            // A tile with no chart does not need the points, and saying so
            // lets the adapter skip a page walk nobody draws the result of.
            // The same test `MetricQueryRequest` makes, so a widget asks the
            // two paths for the same thing.
            wantSeries: widget.chart != .none,
            // From the descriptor, exactly as `supportsCompare(provider,
            // metric)` decides it on the Worker. A metric that cannot answer
            // for a previous period must not be asked to.
            comparePrevious: comparePrevious,
            params: widget.params,
            timeZone: .current,
            // The account's own currency, which `verify` read from the
            // provider. There is no app-wide preference to override it with,
            // and converting is not an option: there is no rate to convert at.
            preferredCurrency: connection.currency ?? "USD")

        do {
            let value = try await ProviderRegistry.fetch(
                connection.provider, credentials: credentials, window: window)
            return .success(
                series(value, widget: widget, connection: connection,
                       unit: unit, window: window, now: now))
        } catch let failure as ProviderFailure {
            return .failure(
                MetricFailure(
                    integrationId: connection.id, metric: metric,
                    code: code(for: failure), message: failure.message,
                    retryAfterSeconds: retryAfter(for: failure)))
        } catch {
            return .failure(
                MetricFailure(
                    integrationId: connection.id, metric: metric,
                    code: .providerDown, message: error.localizedDescription,
                    retryAfterSeconds: nil))
        }
    }

    private static func series(
        _ value: MetricValue, widget: NotchWidget, connection: LocalConnection,
        unit: MetricUnit?, window: MetricWindow, now: Date
    ) -> MetricSeries {
        let iso = ISO8601DateFormatter()
        return MetricSeries(
            integrationId: connection.id,
            metric: window.metric,
            // From the catalogue, not from the adapter. The unit decides how
            // the tile formats the number, and two sources for it is how a
            // count ends up rendered as £412.
            unit: unit ?? (value.currency != nil ? .currency : .count),
            currency: value.currency,
            value: value.value,
            previousValue: value.previousValue,
            delta: nil,
            points: value.points,
            granularity: window.granularity,
            range: widget.range,
            from: iso.string(from: window.from),
            to: iso.string(from: window.to),
            format: nil,
            generatedAt: iso.string(from: now),
            // Always fresh: this *is* the fetch. The server sets this when it
            // serves a number out of its own cache, and there is no such
            // cache on this path.
            stale: false,
            items: value.items)
    }

    /// `ProviderFailure` in the vocabulary the tiles already understand.
    ///
    /// Deliberately not `notFound` for anything: that code tells the refresh
    /// loop the integration is gone and to unbind the widget, and a local
    /// connection cannot disappear behind the app's back — it is in the
    /// app's own settings file.
    private static func code(for failure: ProviderFailure) -> MetricErrorCode {
        switch failure {
        case .authFailed: return .authFailed
        case .rateLimited: return .rateLimited
        case .providerDown: return .providerDown
        // No `badResponse` in the tile vocabulary. `providerDown` is the
        // honest neighbour: an answer this adapter cannot read is their
        // problem to fix and ours to retry, not something the user can act
        // on by replacing a key.
        case .badResponse: return .providerDown
        case .unsupported: return .unsupported
        }
    }

    private static func retryAfter(for failure: ProviderFailure) -> Int? {
        guard case .rateLimited(_, let seconds) = failure, let seconds else { return nil }
        return Int(seconds)
    }
}
