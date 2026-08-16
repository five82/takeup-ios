import Foundation

// Models mirroring Loom's /api/v1 JSON (and Takeup Android's LoomDtos.kt).
// The server omits empty/zero fields, so everything but identity is optional.
// Decoded with .convertFromSnakeCase.

struct Item: Decodable, Identifiable, Hashable {
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
    // Present only on search results.
    let seriesTitle: String?
    let seasonTitle: String?

    var isPlayable: Bool { kind == "movie" || kind == "episode" }
}

struct ItemsPage: Decodable {
    let items: [Item]
    let limit: Int?
    let offset: Int?
}

struct SearchResponse: Decodable {
    let items: [Item]
    let fuzzy: Bool?
}

struct FeaturedPick: Decodable {
    let item: Item
    let startsAt: String?
    let endsAt: String?
}

struct Genre: Decodable, Identifiable, Hashable {
    let id: Int64
    let name: String
    let itemCount: Int?
}

struct Credit: Decodable, Hashable {
    let personId: Int64
    let name: String
    let role: String
    let character: String?
}

struct MediaFile: Decodable, Hashable {
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

struct Stream: Decodable, Hashable {
    let index: Int
    let kind: String
    let codec: String?
    let profile: String?
    let language: String?
    let title: String?
    let width: Int?
    let height: Int?
    let channels: Int?
    let channelLayout: String?
    let dynamicRange: String?
    let isDefault: Bool?
    let isForced: Bool?
}

struct Chapter: Decodable, Hashable {
    let index: Int
    let startMs: Int64?
    let title: String?
}

struct Progress: Decodable, Hashable {
    let positionMs: Int64?
    let durationMs: Int64?
    let played: Bool?
    let resumePositionMs: Int64?
    let updatedAt: String?
}

struct Library: Decodable, Identifiable, Hashable {
    let id: Int64
    let kind: String
    let name: String
    let itemCount: Int64?
}

struct MediaCollection: Decodable, Identifiable, Hashable {
    let slug: String
    let title: String
    let items: [Item]

    var id: String { slug }
}

struct PlaybackInfo: Decodable {
    let itemId: Int64
    let media: MediaFile
    let streamUrl: String
}

struct ScanStatus: Decodable {
    let running: Bool?
    let library: String?
    let startedAt: String?
    let lastEndedAt: String?
    let lastError: String?
}
