import Foundation
import MetricsCore
import Testing

@testable import MetricsAPI

/// What each POST body asked for, across every request a call made.
private final class Recorder: @unchecked Sendable {
    static let shared = Recorder()
    private let lock = NSLock()
    private var _chunks: [[String]] = []

    var chunks: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return _chunks
    }

    func record(_ metrics: [String]) {
        lock.lock()
        _chunks.append(metrics)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        _chunks = []
        lock.unlock()
    }
}

/// Answers a batch POST with one "not found" result per request, so the reply
/// is always index-aligned with what was asked for.
private final class BatchStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        // `httpBody` is nil on a request that has been through URLSession, so
        // the stream is what carries it.
        let body = request.httpBody ?? request.httpBodyStream.map(Self.drain) ?? Data()
        let decoded = try? JSONDecoder().decode(MetricBatchBody.self, from: body)
        let metrics = decoded?.requests.map(\.metric) ?? []
        Recorder.shared.record(metrics)

        let one = #"""
            {"ok":false,"integrationId":"int_1","metric":"m","code":"not_found",\#
            "message":"stub","retryAfterSeconds":null}
            """#
        let json = #"{"results":["# + Array(repeating: one, count: metrics.count)
            .joined(separator: ",") + "]}"

        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["content-type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private struct StubTokens: TokenProviding {
    func validToken() async throws -> String? { "device-token" }
    func clear() async {}
}

private func client() -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [BatchStub.self]
    return APIClient(
        baseURL: URL(string: "https://api.example.com")!,
        tokens: StubTokens(),
        session: URLSession(configuration: configuration))
}

private func asked(_ count: Int) -> [MetricQueryRequest] {
    (1...count).map {
        MetricQueryRequest(
            widget: NotchWidget(integrationId: "int_1", metric: "m\($0)", chart: .sparkline))
    }
}

@Suite(.serialized)
struct MetricBatchChunkTests {
    /// Thirteen is the number that made every tile in a real notch read
    /// "Could not reach Notch Metrics": the server caps a batch at twelve and
    /// rejects the whole body, so one widget too many blanks all of them.
    @Test("a batch past the server's cap is split rather than rejected whole")
    func splitsBeyondTheCap() async throws {
        Recorder.shared.reset()
        let results = try await client().batch(asked(13))

        #expect(Recorder.shared.chunks.map(\.count) == [12, 1])
        // Every metric asked for, once, in the order asked — the results are
        // index-aligned with the request, so order is not cosmetic.
        #expect(Recorder.shared.chunks.flatMap { $0 } == asked(13).map(\.metric))
        #expect(results.count == 13)
    }

    @Test("a batch inside the cap is still a single request")
    func oneRequestWhenItFits() async throws {
        Recorder.shared.reset()
        _ = try await client().batch(asked(12))
        #expect(Recorder.shared.chunks.map(\.count) == [12])
    }

    @Test("nothing to fetch sends no request at all")
    func emptyIsFree() async throws {
        Recorder.shared.reset()
        let results = try await client().batch([])
        #expect(results.isEmpty)
        #expect(Recorder.shared.chunks.isEmpty)
    }
}
