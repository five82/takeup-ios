import Foundation

/// The downloads as a library: movies and shorts stand for themselves,
/// episodes gather under the seasons and shows captured alongside them, and
/// every screen with no Loom reads this instead of the API - the same items,
/// the same hierarchy, the same handful of questions (`library`, `item`,
/// `children`).
///
/// Listings only offer completed downloads, because a half-transferred file
/// cannot play. `item(_:)` answers for any download so a detail screen opened
/// mid-transfer still has something to draw.
///
/// Deliberately free of UI imports and singletons so the whole shape stays
/// reachable from plain unit tests.
struct OfflineCatalog {
    private let ancestorsById: [Int64: Item]
    private let libraryKinds: [Int64: String]
    /// Snapshots of downloads still in flight. Unlike Android, where one
    /// DownloadEntry list spans every transfer state, iOS only ever adds an
    /// entry once a transfer finishes; this is the mid-transfer half, kept
    /// out of every ready-only listing but still answerable by `item(_:)`.
    private let pendingItemsById: [Int64: Item]

    private let itemsById: [Int64: Item]
    private let ready: [Item]
    private let episodesByShow: [Int64: [Item]]
    private let shows: [Item]
    private let looseEpisodes: [Item]

    init(
        entries: [DownloadEntry] = [],
        ancestors: [Int64: Item] = [:],
        libraryKinds: [Int64: String] = [:],
        pending: [Int64: PendingProgress] = [:],
        pendingItems: [Int64: Item] = [:]
    ) {
        // Struct initializers cannot let a closure capture `self` before every
        // stored property has a value, even for read-only access - so this
        // works entirely off local copies of the parameters and only assigns
        // to `self` once each derived value is fully computed.

        // Newest download first, so anything derived from this order leads
        // with what landed most recently.
        let downloaded = entries.sorted { $0.downloadedAt > $1.downloadedAt }

        var items: [Int64: Item] = [:]
        for entry in downloaded {
            items[entry.item.id] = Self.withPendingProgress(entry.item, pending[entry.item.id])
        }

        let ready = downloaded.compactMap { items[$0.item.id] }

        var byShow: [Int64: [Item]] = [:]
        for episode in ready where episode.kind == "episode" {
            guard let showId = Self.showId(of: episode, ancestors: ancestors),
                  ancestors[showId] != nil
            else { continue }
            byShow[showId, default: []].append(episode)
        }

        let shows = byShow.keys.compactMap { ancestors[$0] }

        // Episodes downloaded before their show was captured. Shown as
        // themselves rather than dropped: the file is on the device either way.
        let grouped = Set(byShow.values.flatMap { $0 }.map(\.id))
        let looseEpisodes = ready.filter { $0.kind == "episode" && !grouped.contains($0.id) }

        self.ancestorsById = ancestors
        self.libraryKinds = libraryKinds
        self.pendingItemsById = pendingItems
        self.itemsById = items
        self.ready = ready
        self.episodesByShow = byShow
        self.shows = shows
        self.looseEpisodes = looseEpisodes
    }

    // MARK: - Queries

    /// What a library tab holds offline, in the same A-Z order Loom serves.
    func library(_ kind: String) -> [Item] {
        if kind == "tv" {
            return (shows + looseEpisodes).sorted { $0.title < $1.title }
        }
        // An item does not carry its library's kind, so the cached id-to-kind
        // map fills that in. Anything downloaded before the map knew its
        // library lands under Movies rather than vanishing from every tab.
        return ready
            .filter { $0.kind == "movie" && (libraryKinds[$0.libraryId ?? 0] ?? "movies") == kind }
            .sorted { $0.title < $1.title }
    }

    /// Answers for any download, even one still mid-transfer, so a detail
    /// screen opened while a file is downloading still has something to draw.
    /// Every other query below only draws from completed downloads.
    func item(_ id: Int64) -> Item? { itemsById[id] ?? ancestorsById[id] ?? pendingItemsById[id] }

    /// A show's downloaded seasons, or a season's downloaded episodes.
    func children(_ id: Int64) -> [Item] {
        switch ancestorsById[id]?.kind {
        case "show": seasons(of: id)
        case "season": episodes(ofSeason: id)
        default: []
        }
    }

    /// Every downloaded episode of a show, in running order.
    func episodes(showId: Int64) -> [Item] {
        (episodesByShow[showId] ?? []).sorted {
            ($0.seasonNumber ?? 0, $0.episodeNumber ?? 0) < ($1.seasonNumber ?? 0, $1.episodeNumber ?? 0)
        }
    }

    /// The show an episode belongs to, when it was captured with the download.
    func show(forEpisode episodeId: Int64) -> Item? {
        guard let episode = itemsById[episodeId],
              let showId = Self.showId(of: episode, ancestors: ancestorsById)
        else { return nil }
        return ancestorsById[showId]
    }

    /// The downloaded episodes the player can chain through after this one:
    /// its show's, or its season's when the show was never captured.
    func siblingEpisodes(of episodeId: Int64) -> [Item] {
        guard let episode = itemsById[episodeId] else { return [] }
        if let showId = Self.showId(of: episode, ancestors: ancestorsById), episodesByShow[showId] != nil {
            return episodes(showId: showId)
        }
        guard let seasonId = episode.parentId else { return [] }
        return episodes(ofSeason: seasonId)
    }

    /// Started and unfinished, most recently downloaded first.
    func continueWatching() -> [Item] {
        ready.filter { item in
            guard let progress = item.progress else { return false }
            return !(progress.played ?? false) && (progress.positionMs ?? 0) > 0 && (progress.durationMs ?? 0) > 0
        }
    }

    /// The newest downloads, each show standing in for the episodes beneath it.
    func recent() -> [Item] {
        var seen = Set<Int64>()
        var result: [Item] = []
        for item in ready {
            let resolved = item.kind == "episode" ? (show(forEpisode: item.id) ?? item) : item
            if seen.insert(resolved.id).inserted { result.append(resolved) }
        }
        return result
    }

    /// Everything on the device in one A-Z grid, for a tab with no libraries to split.
    func all() -> [Item] { recent().sorted { $0.title < $1.title } }

    /// Offline search. Loom matches on word starts across titles and credited
    /// people; with no server there is only what the snapshots carry, so this
    /// is a plain substring match over the title and the show a title sits under.
    func search(_ query: String) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var seen = Set<Int64>()
        var pool: [Item] = []
        for item in shows + ready where seen.insert(item.id).inserted {
            pool.append(item)
        }
        return pool
            .filter { item in
                item.title.localizedCaseInsensitiveContains(trimmed) ||
                    (show(forEpisode: item.id)?.title.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
            .sorted { $0.title < $1.title }
    }

    // MARK: - Private helpers

    private func seasons(of showId: Int64) -> [Item] {
        var seen = Set<Int64>()
        var result: [Item] = []
        for episode in episodesByShow[showId] ?? [] {
            guard let parentId = episode.parentId, let season = ancestorsById[parentId],
                  seen.insert(season.id).inserted
            else { continue }
            result.append(season)
        }
        return result.sorted { ($0.seasonNumber ?? 0) < ($1.seasonNumber ?? 0) }
    }

    private func episodes(ofSeason seasonId: Int64) -> [Item] {
        ready
            .filter { $0.kind == "episode" && $0.parentId == seasonId }
            .sorted { ($0.episodeNumber ?? 0) < ($1.episodeNumber ?? 0) }
    }

    private static func showId(of episode: Item, ancestors: [Int64: Item]) -> Int64? {
        episode.parentId.flatMap { ancestors[$0] }?.parentId
    }

    /// Folds a position queued by offline playback over the snapshot it
    /// belongs to. The snapshot froze when the download started, so without
    /// this an item watched offline keeps offering the resume point it had
    /// before it was watched.
    ///
    /// The played and resume thresholds mirror Loom's own, so a title
    /// finished offline leaves Continue Watching here exactly as it will once
    /// the position flushes.
    private static func withPendingProgress(_ item: Item, _ queued: PendingProgress?) -> Item {
        guard let queued, queued.durationMs > 0 else { return item }
        let fraction = Double(queued.positionMs) / Double(queued.durationMs)
        let played = fraction >= playedFraction
        let resumable = !played && queued.durationMs >= minResumeDurationMs && fraction >= minResumeFraction
        let progress = Progress(
            positionMs: queued.positionMs,
            durationMs: queued.durationMs,
            played: played,
            resumePositionMs: resumable ? queued.positionMs : 0,
            updatedAt: item.progress?.updatedAt
        )
        return Item(
            id: item.id,
            libraryId: item.libraryId,
            parentId: item.parentId,
            kind: item.kind,
            title: item.title,
            year: item.year,
            seasonNumber: item.seasonNumber,
            episodeNumber: item.episodeNumber,
            episodeEndNumber: item.episodeEndNumber,
            tmdbId: item.tmdbId,
            overview: item.overview,
            tagline: item.tagline,
            releaseDate: item.releaseDate,
            genres: item.genres,
            credits: item.credits,
            voteAverage: item.voteAverage,
            contentRating: item.contentRating,
            status: item.status,
            totalSeasons: item.totalSeasons,
            posterImageId: item.posterImageId,
            posterImageTag: item.posterImageTag,
            backdropImageId: item.backdropImageId,
            backdropImageTag: item.backdropImageTag,
            logoImageId: item.logoImageId,
            logoImageTag: item.logoImageTag,
            thumbImageId: item.thumbImageId,
            thumbImageTag: item.thumbImageTag,
            mediaTag: item.mediaTag,
            durationMs: item.durationMs,
            addedAt: item.addedAt,
            updatedAt: item.updatedAt,
            media: item.media,
            progress: progress,
            episodeCount: item.episodeCount,
            unwatchedCount: item.unwatchedCount,
            seriesTitle: item.seriesTitle,
            seasonTitle: item.seasonTitle
        )
    }

    private static let playedFraction = 0.90
    private static let minResumeFraction = 0.05
    private static let minResumeDurationMs: Int64 = 5 * 60 * 1000
}
