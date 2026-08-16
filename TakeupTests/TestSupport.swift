import Foundation
@testable import Takeup

/// Item's memberwise init spans every field; tests only vary these few.
func makeItem(
    id: Int64,
    kind: String = "episode",
    parentId: Int64? = nil,
    season: Int? = nil,
    episode: Int? = nil,
    title: String = "Item",
    genres: [Genre]? = nil,
    voteAverage: Double? = nil,
    durationMs: Int64? = nil,
    progress: Takeup.Progress? = nil,
    episodeCount: Int? = nil,
    unwatchedCount: Int? = nil
) -> Item {
    Item(
        id: id, libraryId: nil, parentId: parentId, kind: kind, title: title,
        year: nil, seasonNumber: season, episodeNumber: episode,
        episodeEndNumber: nil, tmdbId: nil, overview: nil, tagline: nil,
        releaseDate: nil, genres: genres, credits: nil, voteAverage: voteAverage,
        contentRating: nil, status: nil, totalSeasons: nil,
        posterImageId: nil, posterImageTag: nil, backdropImageId: nil,
        backdropImageTag: nil, logoImageId: nil, logoImageTag: nil,
        thumbImageId: nil, thumbImageTag: nil, mediaTag: nil, durationMs: durationMs,
        addedAt: nil, updatedAt: nil, media: nil, progress: progress,
        episodeCount: episodeCount, unwatchedCount: unwatchedCount, seriesTitle: nil,
        seasonTitle: nil
    )
}

func makeTrack(
    id: Int,
    type: String,
    lang: String? = nil,
    title: String? = nil,
    codec: String? = nil,
    selected: Bool? = nil
) -> MPVTrack {
    MPVTrack(
        id: id, type: type, lang: lang, title: title, codec: codec,
        isDefault: nil, selected: selected
    )
}

/// The client's decoder configuration, for decoding fixtures the same way.
func loomDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}
