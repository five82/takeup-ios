import Testing
@testable import Takeup

struct FormatTests {
    @Test func runtimeReadsLikeTheAndroidApp() {
        #expect(formatRuntime(118 * 60_000) == "1 h 58 m")
        #expect(formatRuntime(58 * 60_000) == "58 m")
        #expect(formatRuntime(2 * 3600_000) == "2 h 0 m")
    }

    @Test func episodeLabelsCoverRanges() {
        #expect(episodeLabel(makeItem(id: 1, season: 8, episode: 3)) == "S8E3")
        #expect(episodeLabel(makeItem(id: 2)) == nil)
        var item = makeItem(id: 3, season: 1, episode: 4)
        item = Item(
            id: item.id, libraryId: nil, parentId: nil, kind: item.kind, title: item.title,
            year: nil, seasonNumber: 1, episodeNumber: 4, episodeEndNumber: 5,
            tmdbId: nil, overview: nil, tagline: nil, releaseDate: nil, genres: nil,
            credits: nil, voteAverage: nil, contentRating: nil, status: nil,
            totalSeasons: nil, posterImageId: nil, posterImageTag: nil,
            backdropImageId: nil, backdropImageTag: nil, logoImageId: nil,
            logoImageTag: nil, thumbImageId: nil, thumbImageTag: nil, mediaTag: nil,
            durationMs: nil, addedAt: nil, updatedAt: nil, media: nil, progress: nil,
            episodeCount: nil, unwatchedCount: nil, seriesTitle: nil, seasonTitle: nil
        )
        #expect(episodeLabel(item) == "S1E4-5")
    }

    @Test func remainingLabelNeedsRealProgress() {
        let inProgress = makeItem(
            id: 1, kind: "movie",
            progress: Takeup.Progress(positionMs: nil, durationMs: 120 * 60_000, played: nil, resumePositionMs: 30 * 60_000, updatedAt: nil)
        )
        #expect(remainingLabel(inProgress) == "1 h 30 m left")
        #expect(remainingLabel(makeItem(id: 2)) == nil)
        let finished = makeItem(
            id: 3, kind: "movie",
            progress: Takeup.Progress(positionMs: nil, durationMs: 100, played: true, resumePositionMs: nil, updatedAt: nil)
        )
        #expect(remainingLabel(finished) == nil)
    }

    @Test func clockDropsHoursWhenZero() {
        #expect(formatClock(59) == "0:59")
        #expect(formatClock(61) == "1:01")
        #expect(formatClock(3_671) == "1:01:11")
    }
}
