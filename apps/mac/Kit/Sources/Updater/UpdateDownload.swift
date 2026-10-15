import Foundation
import MetricsCore

/// Downloads one file, reporting progress.
///
/// A `URLSessionDownloadTask` rather than `session.data(for:)` or
/// `session.bytes(for:)`: the first holds the whole ~18 MB in memory and
/// reports nothing until it is finished, and the second is an
/// `AsyncSequence` of single bytes, which is eighteen million iterations to
/// move a file. The delegate is the only API that hands back a progress
/// fraction, and a download with no progress bar is one the user cancels
/// because they assume it has hung.
///
/// `@unchecked Sendable` with a lock, because the delegate callbacks arrive on
/// URLSession's own queue while `start(…)` is suspended on another. The two
/// mutable fields are the continuation and the handler, both touched only
/// under `lock`.
final class UpdateDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var onProgress: (@Sendable (Double) -> Void)?

    /// Downloads `url` and moves it to `destination`, which is overwritten.
    func start(
        from url: URL, to destination: URL, onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        lock.withLock { self.onProgress = onProgress }

        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        // Without this the session keeps its strong reference to this delegate
        // alive for the life of the process — one leaked session and one
        // leaked delegate per update check.
        defer { session.finishTasksAndInvalidate() }

        let temporary = try await withCheckedThrowingContinuation { (c: CheckedContinuation<URL, Error>) in
            lock.withLock { self.continuation = c }
            session.downloadTask(with: url).resume()
        }

        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    private func finish(_ result: Result<URL, Error>) {
        // Taken out under the lock and resumed outside it: a continuation may
        // only be resumed once, and `didFinishDownloadingTo` is followed by
        // `didCompleteWithError(nil)` for the same task.
        let pending = lock.withLock {
            let c = continuation
            continuation = nil
            return c
        }
        pending?.resume(with: result)
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        lock.withLock { onProgress }?(fraction)
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo
        location: URL
    ) {
        // A download task treats a 404 as a success whose body happens to be
        // an error page. Caught here, because otherwise the hash check fails
        // instead and reports a corrupt disk image rather than a missing one.
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            finish(.failure(UpdateFeedError.unreachable("status \(http.statusCode)")))
            return
        }

        // The temporary file is deleted the moment this returns, so it is
        // moved somewhere of our own *here* rather than after the await.
        let kept = FileManager.default.temporaryDirectory
            .appendingPathComponent("notch-update-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            finish(.success(kept))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        if let error { finish(.failure(error)) }
        // A nil error after a successful download has already been reported by
        // `didFinishDownloadingTo`; `finish` is idempotent and does nothing.
    }
}
