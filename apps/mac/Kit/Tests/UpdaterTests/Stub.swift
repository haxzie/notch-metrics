import Foundation

@testable import Updater

/// A canned answer for one URL, and a record of what was asked for.
///
/// One instance per test, handed to the feed as its transport. Several of
/// these tests are about a request *not* being made, which no assertion about
/// a response can express.
final class StubTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: Result<(Int, String), Error>] = [:]
    private var asked: [String] = []

    func answer(_ url: String, status: Int, body: String) {
        lock.withLock { answers[url] = .success((status, body)) }
    }

    /// A transport failure, which is a different path from a 500.
    func fail(_ url: String) {
        lock.withLock { answers[url] = .failure(URLError(.cannotConnectToHost)) }
    }

    var requested: [String] { lock.withLock { asked } }

    var transport: UpdateFeed.Transport {
        { [self] request in
            let url = request.url!
            let answer = lock.withLock { () -> Result<(Int, String), Error>? in
                asked.append(url.absoluteString)
                return answers[url.absoluteString]
            }
            guard let answer else { throw URLError(.unsupportedURL) }
            let (status, body) = try answer.get()
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["content-type": "application/json"])!
            return (Data(body.utf8), response)
        }
    }
}

let apiBase = URL(string: "https://api.example.com")!
let mirrorBase = URL(string: "https://assets.example.com")!
let apiURL = "https://api.example.com/v1/updates/latest"
let mirrorURL = "https://assets.example.com/desktop/latest.json"

func manifestJSON(version: String = "0.3.0", build: Int = 140, minimum: String = "14.0") -> String {
    """
    {"version":"\(version)","build":\(build),"tag":"mac-v\(version)",
     "publishedAt":"2026-10-15T00:00:00Z","platform":"darwin-arm64",
     "minimumSystemVersion":"\(minimum)",
     "filename":"NotchMetrics-\(version)-arm64.dmg",
     "url":"https://assets.example.com/desktop/\(version)/NotchMetrics-\(version)-arm64.dmg",
     "size":18000000,"sha256":"\(String(repeating: "a", count: 64))",
     "notes":null,"mandatory":false}
    """
}
