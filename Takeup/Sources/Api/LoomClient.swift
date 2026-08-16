import Foundation

struct LoomError: Error, LocalizedError {
    let statusCode: Int
    let serverMessage: String?

    var errorDescription: String? {
        serverMessage ?? "Loom request failed (HTTP \(statusCode))"
    }
}

/// Thin client for Loom's /api/v1. Mirrors Takeup Android's LoomApi.kt.
struct LoomClient {
    let baseURL: URL

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // MARK: - Endpoints

    func health() async throws {
        let _: EmptyResponse = try await request("health")
    }

    // List endpoints wrap their arrays in {"items": [...]}; an empty list
    // arrives as {"items": null} (Go marshals nil slices as null).
    private struct Wrapped<Element: Decodable>: Decodable {
        let items: [Element]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decodeIfPresent([Element].self, forKey: .items) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case items
        }
    }

    func libraries() async throws -> [Library] {
        let wrapped: Wrapped<Library> = try await request("libraries")
        return wrapped.items
    }

    func items(library: String? = nil, genreId: Int64? = nil, limit: Int = 60, offset: Int = 0) async throws -> ItemsPage {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let library { query.append(URLQueryItem(name: "library", value: library)) }
        if let genreId { query.append(URLQueryItem(name: "genre_id", value: String(genreId))) }
        return try await request("items", query: query)
    }

    /// The full catalog of a library, paged until a short page marks the end.
    /// Discovery shelves shuffle the whole library, so they need all of it.
    func allItems(library: String) async throws -> [Item] {
        var all: [Item] = []
        let pageSize = 200
        while true {
            let page = try await items(library: library, limit: pageSize, offset: all.count)
            all.append(contentsOf: page.items)
            if page.items.count < pageSize { break }
        }
        return all
    }

    func genres() async throws -> [Genre] {
        let wrapped: Wrapped<Genre> = try await request("genres")
        return wrapped.items
    }

    func collections() async throws -> [MediaCollection] {
        let wrapped: Wrapped<MediaCollection> = try await request("collections")
        return wrapped.items
    }

    /// Marks an item (cascading over shows/seasons) played or unplayed.
    func setPlayed(id: Int64, _ played: Bool) async throws {
        struct Updated: Decodable { let updated: Int? }
        let _: Updated = try await request("items/\(id)/played", method: played ? "POST" : "DELETE")
    }

    func item(id: Int64) async throws -> Item {
        try await request("items/\(id)")
    }

    func children(of id: Int64, limit: Int = 200, offset: Int = 0) async throws -> ItemsPage {
        try await request("items/\(id)/children", query: [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
    }

    func playback(id: Int64) async throws -> PlaybackInfo {
        try await request("items/\(id)/playback")
    }

    func continueWatching(limit: Int = 20) async throws -> ItemsPage {
        try await request("continue-watching", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func nextUp(limit: Int = 20) async throws -> ItemsPage {
        try await request("next-up", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func recentlyAdded(limit: Int = 20) async throws -> ItemsPage {
        try await request("recently-added", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func recentlyPlayed(limit: Int = 20) async throws -> ItemsPage {
        try await request("recently-played", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func featuredPick() async throws -> FeaturedPick {
        try await request("featured-pick")
    }

    func search(query: String, limit: Int = 50) async throws -> SearchResponse {
        try await request("search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
    }

    @discardableResult
    func reportProgress(id: Int64, positionMs: Int64, durationMs: Int64) async throws -> Progress {
        struct Body: Encodable {
            let position_ms: Int64
            let duration_ms: Int64
        }
        return try await request(
            "items/\(id)/progress",
            method: "PUT",
            body: try JSONEncoder().encode(Body(position_ms: positionMs, duration_ms: durationMs))
        )
    }

    func imageOptions(id: Int64, kind: String) async throws -> [ImageOption] {
        let wrapped: Wrapped<ImageOption> = try await request("items/\(id)/images/\(kind)/options")
        return wrapped.items
    }

    /// Loom downloads the full-size original from TMDB before responding, so
    /// this can take several seconds; give it more room than the default request timeout.
    func selectImage(id: Int64, kind: String, provider: String, providerPath: String) async throws {
        struct Body: Encodable {
            let provider: String
            let provider_path: String
        }
        let _: EmptyResponse = try await request(
            "items/\(id)/images/\(kind)",
            method: "PUT",
            body: try JSONEncoder().encode(Body(provider: provider, provider_path: providerPath)),
            timeout: 120
        )
    }

    func resetImage(id: Int64, kind: String) async throws {
        let _: EmptyResponse = try await request("items/\(id)/images/\(kind)/reset", method: "POST")
    }

    // MARK: - URLs

    func streamURL(for playback: PlaybackInfo) -> URL? {
        URL(string: playback.streamUrl, relativeTo: baseURL)?.absoluteURL
    }

    /// Server-resized artwork. Width snaps up to Loom's buckets: 240/480/960/1440.
    func imageURL(id: Int64?, tag: String?, width: Int) -> URL? {
        guard let id, id != 0 else { return nil }
        var components = URLComponents(url: baseURL.appending(path: "api/v1/images/\(id)"), resolvingAgainstBaseURL: false)
        var query = [URLQueryItem(name: "width", value: String(width))]
        if let tag { query.append(URLQueryItem(name: "tag", value: tag)) }
        components?.queryItems = query
        return components?.url
    }

    // MARK: - Plumbing

    private struct EmptyResponse: Decodable {}
    private struct ServerError: Decodable { let error: String? }

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: "api/v1/\(path)"), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if let timeout { request.timeoutInterval = timeout }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = try? Self.decoder.decode(ServerError.self, from: data).error
            throw LoomError(statusCode: status, serverMessage: message ?? nil)
        }
        if T.self == EmptyResponse.self, data.isEmpty {
            return EmptyResponse() as! T
        }
        return try Self.decoder.decode(T.self, from: data)
    }
}
