import Foundation
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

    @Test func homeCardLinesPlaceAnEpisodeUnderItsShow() {
        // The show itself is the card's heading, so it is deliberately absent
        // from both lines rather than repeated in them.
        let episode = makeItem(id: 1, season: 4, episode: 5, title: "The Constant")
        #expect(episodeLine(episode) == "S4E5 · The Constant")
        let started = makeItem(
            id: 1, season: 4, episode: 5, title: "The Constant",
            progress: Takeup.Progress(
                positionMs: nil, durationMs: 60 * 60_000, played: nil,
                resumePositionMs: 30 * 60_000, updatedAt: nil
            )
        )
        #expect(continueLine(started) == "S4E5 · The Constant · 30 m left")
    }

    @Test func continueLineLeavesAMovieItsTimeAlone() {
        // A movie's thumb already carries its title, so it gets no heading and
        // no episode line - only what is left to watch.
        let movie = makeItem(
            id: 2, kind: "movie", title: "Heat",
            progress: Takeup.Progress(
                positionMs: nil, durationMs: 171 * 60_000, played: nil,
                resumePositionMs: 111 * 60_000, updatedAt: nil
            )
        )
        #expect(episodeLine(movie) == nil)
        #expect(continueLine(movie) == "1 h 0 m left")
    }

    @Test func clockDropsHoursWhenZero() {
        #expect(formatClock(59) == "0:59")
        #expect(formatClock(61) == "1:01")
        #expect(formatClock(3_671) == "1:01:11")
    }

    @Test func resolutionBadgesUseServerLabels() {
        #expect(resolutionBadge("4k") == "4K")
        #expect(resolutionBadge("1080p") == "1080p")
        #expect(resolutionBadge("720p") == "720p")
        #expect(resolutionBadge("sd") == "SD")
        #expect(resolutionBadge(nil) == nil)
        #expect(resolutionBadge("unknown") == nil)
    }

    @Test func timestampsReadLikeTheAndroidApp() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-08-20T22:00:00Z"))
        let locale = Locale(identifier: "en_US_POSIX")

        #expect(formatTimestamp("2026-08-20T17:04:05.123456789Z", timeZone: zone, locale: locale, now: now) == "Today at 1:04 PM")
        #expect(formatTimestamp("2026-08-20T03:32:00Z", timeZone: zone, locale: locale, now: now) == "Yesterday at 11:32 PM")
        #expect(formatTimestamp("2026-08-18T13:05:00Z", timeZone: zone, locale: locale, now: now) == "Aug 18 at 9:05 AM")
        #expect(formatTimestamp("2025-12-30T14:05:00Z", timeZone: zone, locale: locale, now: now) == "Dec 30, 2025 at 9:05 AM")
        #expect(formatTimestamp("soon", timeZone: zone, locale: locale, now: now) == "soon")
    }
}
