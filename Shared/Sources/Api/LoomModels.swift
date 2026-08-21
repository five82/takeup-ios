import Foundation

// Models mirroring Loom's /api/v1 JSON (and Takeup Android's LoomDtos.kt).
// The server omits empty/zero fields, so everything but identity is optional.
// Decoded with .convertFromSnakeCase.

struct Item: Codable, Identifiable, Hashable {
    let id: Int64
    let libraryId: Int64?
    let parentId: Int64?
    let kind: String
    let title: String
    let year: Int?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let episodeEndNumber: Int?
    let tmdbId: Int64?
    let overview: String?
    let tagline: String?
    let releaseDate: String?
    let genres: [Genre]?
    let credits: [Credit]?
    let voteAverage: Double?
    let contentRating: String?
    let status: String?
    let totalSeasons: Int?
    let posterImageId: Int64?
    let posterImageTag: String?
    let backdropImageId: Int64?
    let backdropImageTag: String?
    let logoImageId: Int64?
    let logoImageTag: String?
    let thumbImageId: Int64?
    let thumbImageTag: String?
    let mediaTag: String?
    let durationMs: Int64?
    let addedAt: String?
    let updatedAt: String?
    let media: MediaFile?
    let progress: Progress?
    let episodeCount: Int?
    let unwatchedCount: Int?
    // Context for episodes listed outside their show hierarchy: search,
    // Continue Watching, and Next Up.
    let seriesTitle: String?
    let seasonTitle: String?

    var isPlayable: Bool { kind == "movie" || kind == "episode" }
}

// Loom (Go) marshals empty lists as `"items": null`, so `items` must decode
// null as empty here and in every other list wrapper.
struct ItemsPage: Codable {
    let items: [Item]
    let limit: Int?
    let offset: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
        offset = try container.decodeIfPresent(Int.self, forKey: .offset)
    }
}

struct SearchResponse: Codable {
    let items: [Item]
    let fuzzy: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        fuzzy = try container.decodeIfPresent(Bool.self, forKey: .fuzzy)
    }
}

struct FeaturedPick: Codable {
    let item: Item
    let startsAt: String?
    let endsAt: String?
}

struct Genre: Codable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let itemCount: Int?
}

struct Credit: Codable, Hashable {
    let personId: Int64
    let name: String
    let role: String
    let character: String?
}

struct MediaFile: Codable, Hashable {
    let id: Int64
    let itemId: Int64?
    let filename: String?
    let size: Int64?
    let tag: String?
    let durationMs: Int64?
    let container: String?
    let probeError: String?
    let streams: [Stream]?
    let chapters: [Chapter]?
}

struct Stream: Codable, Hashable {
    let index: Int
    let kind: String
    let codec: String?
    let profile: String?
    let language: String?
    let title: String?
    let width: Int?
    let height: Int?
    let resolution: String?
    let channels: Int?
    let channelLayout: String?
    let dynamicRange: String?
    let isDefault: Bool?
    let isForced: Bool?
}

struct Chapter: Codable, Hashable {
    let index: Int
    let startMs: Int64?
    let title: String?
}

struct Progress: Codable, Hashable {
    let positionMs: Int64?
    let durationMs: Int64?
    let played: Bool?
    let resumePositionMs: Int64?
    let updatedAt: String?
}

struct Library: Codable, Identifiable, Hashable {
    let id: Int64
    let kind: String
    let name: String
    let itemCount: Int64?
}

struct MediaCollection: Codable, Identifiable, Hashable {
    let slug: String
    let title: String
    let items: [Item]

    var id: String { slug }
}

struct PlaybackInfo: Codable {
    let itemId: Int64
    let media: MediaFile
    let streamUrl: String
}

struct ScanStatus: Codable {
    let running: Bool?
    let library: String?
    let startedAt: String?
    let lastEndedAt: String?
    let lastError: String?
}

struct ImageOption: Codable, Hashable {
    let provider: String
    let providerPath: String
    let language: String?
    let width: Int
    let height: Int
    let aspectRatio: Double?
    let voteAverage: Double?
    let voteCount: Int?
    let thumbnailUrl: String
    // var: the artwork picker flips this optimistically while Loom applies
    // the selection.
    var selected: Bool
}
