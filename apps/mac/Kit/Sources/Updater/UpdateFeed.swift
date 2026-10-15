import Foundation
import MetricsCore

public enum UpdateFeedError: Error, Sendable, Equatable {
    /// Neither the Worker nor the bucket answered.
    case unreachable(String)
    case malformed(String)
}

/// Where the app learns that a newer build exists.
///
/// Two sources, and the order between them is the whole design.
///
/// The Worker's `/v1/updates/latest` is asked first because it is the only one
/// that can *withhold* a release: `PINNED_VERSION` is how a bad build is
/// pulled back in one deploy. The bucket is the fallback for the case the
/// Worker is down, so an outage in our API does not freeze every installed
/// copy on the version it happens to have.
public struct UpdateFeed: Sendable {
    /// One GET, as a closure.
    ///
    /// Injected rather than taking a `URLSession`, because stubbing a session
    /// means a `URLProtocol` subclass, and a `URLProtocol` can only reach its
    /// canned answers through global state — which two test suites running
    /// concurrently then share.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let api: URL
    let mirror: URL
    private let transport: Transport

    public init(api: URL, mirror: URL, transport: @escaping Transport = Self.urlSession) {
        self.api = api
        self.mirror = mirror
        self.transport = transport
    }

    public static let urlSession: Transport = { request in
        try await URLSession.shared.data(for: request)
    }

    /// The current release, or `nil` for "there is nothing on offer".
    ///
    /// `nil` covers both "no release has ever been published" and "the Worker
    /// is withholding this one". Both are 404, and the app does the same thing
    /// in either case.
    public func latest() async throws -> LatestManifest? {
        do {
            return try await fetch(api.appendingPathComponent("v1/updates/latest"))
        } catch UpdateFeedError.unreachable(let why) {
            // Only a transport failure or a 5xx falls through to the bucket.
            //
            // A 404 is the Worker *answering*, and "no update available" is
            // exactly what a withheld release looks like. Treating that as a
            // reason to go and read the bucket directly would route every
            // client straight around the rollback it just performed, which is
            // the one thing this fallback must never do.
            Log.updater.notice("update feed unreachable (\(why, privacy: .public)); trying the mirror")
            return try await fetch(mirror.appendingPathComponent("desktop/latest.json"))
        }
    }

    private func fetch(_ url: URL) async throws -> LatestManifest? {
        var request = URLRequest(url: url)
        // Short. Checking for updates is background work and must never be the
        // reason a settings pane sits spinning.
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw UpdateFeedError.unreachable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UpdateFeedError.unreachable("no HTTP response")
        }

        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw UpdateFeedError.unreachable("status \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(LatestManifest.self, from: data)
        } catch {
            // Deliberately *not* unreachable: a manifest that does not decode
            // is not a reason to go and read the same bad manifest off the
            // bucket, and it must not be acted on either.
            throw UpdateFeedError.malformed(error.localizedDescription)
        }
    }
}
