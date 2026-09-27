import Foundation
import Testing
@testable import Takeup

private final class StubURLProtocol: URLProtocol {
    static var reply: (URLRequest) -> (Int, Data) = { _ in (200, Data("{}".utf8)) }
    static var requests: [URLRequest] = []
    static var bodies: [Data?] = []
    private static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        }
        Self.bodies.append(body)
        let (status, data) = Self.reply(request)
        Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset(reply: @escaping (URLRequest) -> (Int, Data)) {
        lock.lock()
        requests = []
        bodies = []
        self.reply = reply
        lock.unlock()
    }

    static func lastRequest() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.last
    }

    static func lastBody() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return bodies.last ?? nil
    }
}

@Suite(.serialized) struct LoomClientTests {
    private func client(blocked: @escaping @Sendable () -> Bool = { false }) -> LoomClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return LoomClient(baseURL: URL(string: "http://loom.test:8097")!, blocked: blocked, session: URLSession(configuration: config))
    }

    @Test func queriesCarryPagingAndFilters() async throws {
        StubURLProtocol.reset { _ in (200, Data(#"{"items":null,"limit":12,"offset":24}"#.utf8)) }
        let page = try await client().items(library: "movies", genreId: 28, limit: 12, offset: 24)
        #expect(page.items.isEmpty)
        #expect(page.limit == 12)
        let request = try #require(StubURLProtocol.lastRequest())
        #expect(request.url?.path == "/api/v1/items")
        let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.contains(URLQueryItem(name: "library", value: "movies")))
        #expect(query.contains(URLQueryItem(name: "genre_id", value: "28")))
        #expect(query.contains(URLQueryItem(name: "limit", value: "12")))
        #expect(query.contains(URLQueryItem(name: "offset", value: "24")))
    }

    @Test func writesSendExpectedMethodsAndBodies() async throws {
        StubURLProtocol.reset { request in
            if request.url?.path.hasSuffix("/progress") == true {
                return (200, Data(#"{"position_ms":1200,"played":false}"#.utf8))
            }
            return (200, Data(#"{"updated":1}"#.utf8))
        }
        let api = client()
        try await api.setPlayed(id: 31, true)
        #expect(StubURLProtocol.lastRequest()?.httpMethod == "POST")
        try await api.setPlayed(id: 31, false)
        #expect(StubURLProtocol.lastRequest()?.httpMethod == "DELETE")
        let progress = try await api.reportProgress(id: 31, positionMs: 1200, durationMs: 5000)
        #expect(progress.positionMs == 1200)
        let request = try #require(StubURLProtocol.lastRequest())
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(StubURLProtocol.lastBody())
        let values = try #require(JSONSerialization.jsonObject(with: body) as? [String: Int])
        #expect(values == ["position_ms": 1200, "duration_ms": 5000])
    }

    @Test func emptyResponsesAndServerErrors() async throws {
        StubURLProtocol.reset { _ in (200, Data()) }
        try await client().health()
        StubURLProtocol.reset { _ in (200, Data(#"{"items":null}"#.utf8)) }
        #expect(try await client().collections().isEmpty)
        #expect(try await client().genres().isEmpty)
        StubURLProtocol.reset { _ in (503, Data(#"{"error":"Loom is busy"}"#.utf8)) }
        do {
            try await client().health()
            Issue.record("Expected LoomError")
        } catch let error as LoomError {
            #expect(error.statusCode == 503)
            #expect(error.errorDescription == "Loom is busy")
        }
    }

    @Test func blockedRequestsNeverHitTransport() async {
        StubURLProtocol.reset { _ in (200, Data()) }
        do {
            try await client(blocked: { true }).health()
            Issue.record("Expected offline error")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(StubURLProtocol.lastRequest() == nil)
    }

    @Test func imageAndPlaybackURLsResolveFromServer() throws {
        let api = client()
        #expect(api.imageURL(id: nil, tag: nil, width: 240) == nil)
        #expect(api.imageURL(id: 0, tag: nil, width: 240) == nil)
        let image = api.imageURL(id: 72, tag: "v2", width: 480)
        #expect(image?.path == "/api/v1/images/72")
        #expect(URLComponents(url: try #require(image), resolvingAgainstBaseURL: false)?.queryItems == [
            URLQueryItem(name: "width", value: "480"), URLQueryItem(name: "tag", value: "v2")
        ])
        let playback = try loomDecoder().decode(PlaybackInfo.self, from: Data(#"{"item_id":31,"media":{"id":1},"stream_url":"/api/v1/items/31/stream"}"#.utf8))
        #expect(api.streamURL(for: playback)?.absoluteString == "http://loom.test:8097/api/v1/items/31/stream")
    }
}
