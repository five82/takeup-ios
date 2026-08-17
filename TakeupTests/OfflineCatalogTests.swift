import Foundation
import Testing
@testable import Takeup

/// makeItem (TestSupport.swift) covers most fixtures but has no libraryId
/// parameter; the kind-slicing tests need one, so this builds the Item
/// directly. Item's fields are all `let`, so there is no copy-and-mutate path.
private func catalogItem(
    id: Int64,
    libraryId: Int64? = nil,
    kind: String = "episode",
    parentId: Int64? = nil,
    season: Int? = nil,
    episode: Int? = nil,
    title: String = "Item",
    progress: Takeup.Progress? = nil
) -> Item {
    Item(
        id: id, libraryId: libraryId, parentId: parentId, kind: kind, title: title,
        year: nil, seasonNumber: season, episodeNumber: episode,
        episodeEndNumber: nil, tmdbId: nil, overview: nil, tagline: nil,
        releaseDate: nil, genres: nil, credits: nil, voteAverage: nil,
        contentRating: nil, status: nil, totalSeasons: nil,
        posterImageId: nil, posterImageTag: nil, backdropImageId: nil,
        backdropImageTag: nil, logoImageId: nil, logoImageTag: nil,
        thumbImageId: nil, thumbImageTag: nil, mediaTag: nil, durationMs: nil,
        addedAt: nil, updatedAt: nil, media: nil, progress: progress,
        episodeCount: nil, unwatchedCount: nil, seriesTitle: nil, seasonTitle: nil
    )
}

private func entry(_ item: Item, downloadedAt: Date = .now) -> DownloadEntry {
    DownloadEntry(item: item, relativePath: "\(item.id).media", size: 1, downloadedAt: downloadedAt)
}

struct OfflineCatalogTests {
    // MARK: - Grouping

    @Test func episodesGroupUnderTheirCapturedSeasonAndShow() {
        let show = catalogItem(id: 1, kind: "show", title: "Show")
        let season = catalogItem(id: 2, kind: "season", parentId: 1, season: 1, title: "Season 1")
        let episode1 = catalogItem(id: 3, kind: "episode", parentId: 2, season: 1, episode: 2, title: "Ep 2")
        let episode2 = catalogItem(id: 4, kind: "episode", parentId: 2, season: 1, episode: 1, title: "Ep 1")

        let catalog = OfflineCatalog(
            entries: [entry(episode1), entry(episode2)],
            ancestors: [1: show, 2: season]
        )

        #expect(catalog.episodes(showId: 1).map(\.id) == [4, 3]) // running order, not download order
        #expect(catalog.children(1).map(\.id) == [2]) // show -> seasons
        #expect(catalog.children(2).map(\.id) == [4, 3]) // season -> episodes
        #expect(catalog.library("tv").map(\.id) == [1])
        #expect(catalog.show(forEpisode: 3)?.id == 1)
    }

    @Test func episodesAreLooseWhenTheirShowWasNeverCaptured() {
        // The season itself was never captured, so the episode cannot resolve
        // a show id at all.
        let episode = catalogItem(id: 3, kind: "episode", parentId: 99, season: 1, episode: 1, title: "Orphan")

        let catalog = OfflineCatalog(entries: [entry(episode)], ancestors: [:])

        #expect(catalog.show(forEpisode: 3) == nil)
        #expect(catalog.library("tv").map(\.id) == [3])
    }

    @Test func episodesAreLooseWhenOnlyTheSeasonWasCapturedNotTheShow() {
        // The season is known but its own parent (the show) never was, so the
        // grouping cannot climb all the way to a show.
        let season = catalogItem(id: 2, kind: "season", parentId: 1, season: 1, title: "Season 1")
        let episode = catalogItem(id: 3, kind: "episode", parentId: 2, season: 1, episode: 1, title: "Ep 1")

        let catalog = OfflineCatalog(entries: [entry(episode)], ancestors: [2: season])

        #expect(catalog.library("tv").map(\.id) == [3])
        // Sibling chaining still works off the season when the show is missing.
        #expect(catalog.siblingEpisodes(of: 3).map(\.id) == [3])
    }

    // MARK: - Kind slicing

    @Test func libraryKindSlicingFallsBackToMoviesForAnUnknownLibrary() {
        let known = catalogItem(id: 1, libraryId: 10, kind: "movie", title: "Known Movie")
        let short = catalogItem(id: 2, libraryId: 20, kind: "movie", title: "A Short")
        let unknown = catalogItem(id: 3, libraryId: 30, kind: "movie", title: "Undownloaded Library")

        let catalog = OfflineCatalog(
            entries: [entry(known), entry(short), entry(unknown)],
            libraryKinds: [10: "movies", 20: "shorts"]
        )

        #expect(catalog.library("movies").map(\.id) == [1, 3]) // A-Z: "Known..." < "Undownloaded..."
        #expect(catalog.library("shorts").map(\.id) == [2])
        #expect(catalog.library("tv").isEmpty)
    }

    // MARK: - Progress folding

    @Test func aQueuedPositionPastThePlayedThresholdStripsResume() {
        let item = catalogItem(id: 1, kind: "movie", title: "Movie")
        let pending: [Int64: PendingProgress] = [1: PendingProgress(itemId: 1, positionMs: 5_400_000, durationMs: 6_000_000)]

        let catalog = OfflineCatalog(entries: [entry(item)], pending: pending)

        let folded = catalog.item(1)
        #expect(folded?.progress?.played == true)
        #expect(folded?.progress?.resumePositionMs == 0)
    }

    @Test func aQueuedPositionPastTheResumeFloorWithLongEnoughDurationResumes() {
        let item = catalogItem(id: 1, kind: "movie", title: "Movie")
        // 10% through an 10-minute (600_000ms) title: past the 5% floor and
        // past the 5-minute duration floor, short of the 90% played mark.
        let pending: [Int64: PendingProgress] = [1: PendingProgress(itemId: 1, positionMs: 60_000, durationMs: 600_000)]

        let catalog = OfflineCatalog(entries: [entry(item)], pending: pending)

        let folded = catalog.item(1)
        #expect(folded?.progress?.played == false)
        #expect(folded?.progress?.resumePositionMs == 60_000)
    }

    @Test func aShortTitleNeverOffersResumeEvenPastTheFractionFloor() {
        let item = catalogItem(id: 1, kind: "movie", title: "Movie")
        // 10% through a 1-minute title: past the 5% fraction floor, but the
        // title is under the 5-minute duration floor.
        let pending: [Int64: PendingProgress] = [1: PendingProgress(itemId: 1, positionMs: 6_000, durationMs: 60_000)]

        let catalog = OfflineCatalog(entries: [entry(item)], pending: pending)

        let folded = catalog.item(1)
        #expect(folded?.progress?.played == false)
        #expect(folded?.progress?.resumePositionMs == 0)
    }

    @Test func aShortTitleCanStillBeMarkedPlayed() {
        let item = catalogItem(id: 1, kind: "movie", title: "Movie")
        // 90% through a 1-minute title: the played threshold has no duration floor.
        let pending: [Int64: PendingProgress] = [1: PendingProgress(itemId: 1, positionMs: 54_000, durationMs: 60_000)]

        let catalog = OfflineCatalog(entries: [entry(item)], pending: pending)

        #expect(catalog.item(1)?.progress?.played == true)
    }

    // MARK: - Continue watching

    @Test func continueWatchingKeepsOnlyStartedAndUnfinishedItems() {
        let unstarted = catalogItem(id: 1, kind: "movie", title: "Unstarted",
            progress: Takeup.Progress(positionMs: 0, durationMs: 6_000_000, played: false, resumePositionMs: 0, updatedAt: nil))
        let inProgress = catalogItem(id: 2, kind: "movie", title: "In Progress",
            progress: Takeup.Progress(positionMs: 1_000_000, durationMs: 6_000_000, played: false, resumePositionMs: 1_000_000, updatedAt: nil))
        let finished = catalogItem(id: 3, kind: "movie", title: "Finished",
            progress: Takeup.Progress(positionMs: 5_900_000, durationMs: 6_000_000, played: true, resumePositionMs: 0, updatedAt: nil))
        let untouched = catalogItem(id: 4, kind: "movie", title: "Untouched", progress: nil)

        let catalog = OfflineCatalog(entries: [unstarted, inProgress, finished, untouched].map { entry($0) })

        #expect(catalog.continueWatching().map(\.id) == [2])
    }

    // MARK: - Recent / all

    @Test func recentReplacesEpisodesWithTheirShowAndDedupsById() {
        let show = catalogItem(id: 1, kind: "show", title: "Show")
        let season = catalogItem(id: 2, kind: "season", parentId: 1, season: 1, title: "Season 1")
        let episode1 = catalogItem(id: 3, kind: "episode", parentId: 2, season: 1, episode: 1, title: "Ep 1")
        let episode2 = catalogItem(id: 4, kind: "episode", parentId: 2, season: 1, episode: 2, title: "Ep 2")
        let movie = catalogItem(id: 5, kind: "movie", title: "A Movie")

        // Explicit, well-separated timestamps: "newest first" order must be
        // deterministic for this test to check dedup order reliably.
        let catalog = OfflineCatalog(
            entries: [
                entry(episode1, downloadedAt: Date(timeIntervalSince1970: 300)),
                entry(episode2, downloadedAt: Date(timeIntervalSince1970: 200)),
                entry(movie, downloadedAt: Date(timeIntervalSince1970: 100)),
            ],
            ancestors: [1: show, 2: season]
        )

        // Both episodes collapse to the one show; the movie stands for itself.
        #expect(catalog.recent().map(\.id) == [1, 5])
        #expect(catalog.all().map(\.id).sorted() == [1, 5])
    }

    // MARK: - Search

    @Test func searchMatchesAnEpisodesOwnTitleOrItsShows() {
        let show = catalogItem(id: 1, kind: "show", title: "Breaking Good")
        let season = catalogItem(id: 2, kind: "season", parentId: 1, season: 1, title: "Season 1")
        let episode = catalogItem(id: 3, kind: "episode", parentId: 2, season: 1, episode: 1, title: "Pilot")
        let unrelated = catalogItem(id: 4, kind: "movie", title: "Unrelated Feature")

        let catalog = OfflineCatalog(
            entries: [entry(episode), entry(unrelated)],
            ancestors: [1: show, 2: season]
        )

        // Matches both the show itself (title match) and the episode (its
        // captured show's title matches), sorted A-Z: "Breaking..." < "Pilot".
        #expect(catalog.search("breaking").map(\.id) == [1, 3])
        #expect(catalog.search("pilot").map(\.id) == [3])
        #expect(catalog.search("nomatch").isEmpty)
        #expect(catalog.search("   ").isEmpty)
    }

    // MARK: - Sibling episodes

    @Test func siblingEpisodesComeFromTheShowWhenOneWasCaptured() {
        let show = catalogItem(id: 1, kind: "show", title: "Show")
        let season1 = catalogItem(id: 2, kind: "season", parentId: 1, season: 1, title: "Season 1")
        let season2 = catalogItem(id: 5, kind: "season", parentId: 1, season: 2, title: "Season 2")
        let episode1 = catalogItem(id: 3, kind: "episode", parentId: 2, season: 1, episode: 1, title: "S1E1")
        let episode2 = catalogItem(id: 4, kind: "episode", parentId: 5, season: 2, episode: 1, title: "S2E1")

        let catalog = OfflineCatalog(
            entries: [entry(episode1), entry(episode2)],
            ancestors: [1: show, 2: season1, 5: season2]
        )

        // Siblings span the whole show, not just the one season.
        #expect(catalog.siblingEpisodes(of: 3).map(\.id) == [3, 4])
    }

    @Test func siblingEpisodesFallBackToTheSeasonWhenNoShowWasCaptured() {
        let season = catalogItem(id: 2, kind: "season", parentId: 1, season: 1, title: "Season 1")
        let episode1 = catalogItem(id: 3, kind: "episode", parentId: 2, season: 1, episode: 1, title: "S1E1")
        let episode2 = catalogItem(id: 4, kind: "episode", parentId: 2, season: 1, episode: 2, title: "S1E2")

        let catalog = OfflineCatalog(entries: [entry(episode1), entry(episode2)], ancestors: [2: season])

        #expect(catalog.siblingEpisodes(of: 3).map(\.id) == [3, 4])
    }

    // MARK: - item(_:) mid-transfer

    @Test func itemAnswersForADownloadStillInFlight() {
        let downloading = catalogItem(id: 9, kind: "movie", title: "Downloading Now")

        let catalog = OfflineCatalog(entries: [], pendingItems: [9: downloading])

        #expect(catalog.item(9)?.id == 9)
        #expect(catalog.all().isEmpty) // not ready, so it draws nowhere else
    }
}
