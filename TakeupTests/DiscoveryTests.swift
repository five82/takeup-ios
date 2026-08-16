import Testing
@testable import Takeup

struct DiscoveryTests {
    private func movie(
        _ id: Int64,
        started: Bool = false,
        vote: Double? = nil,
        durationMs: Int64? = 100 * 60 * 1000,
        genres: [Genre]? = nil
    ) -> Item {
        makeItem(
            id: id, kind: "movie", title: "Movie \(id)",
            genres: genres, voteAverage: vote, durationMs: durationMs,
            progress: started ? Takeup.Progress(positionMs: 1000, durationMs: durationMs, played: nil, resumePositionMs: 1000, updatedAt: nil) : nil
        )
    }

    private func makeLibrary(count: Int) -> [Item] {
        (1...Int64(count)).map { movie($0) }
    }

    @Test func sameDayIsStable() {
        let movies = makeLibrary(count: 30)
        let first = discoveryRows(movies: movies, shows: [], collections: [], recentlyPlayed: [], epochDay: 20_000)
        let second = discoveryRows(movies: movies, shows: [], collections: [], recentlyPlayed: [], epochDay: 20_000)
        #expect(first == second)
        #expect(!first.isEmpty)
    }

    @Test func differentDayReshuffles() {
        let movies = makeLibrary(count: 30)
        let today = discoveryRows(movies: movies, shows: [], collections: [], recentlyPlayed: [], epochDay: 20_000)
        let tomorrow = discoveryRows(movies: movies, shows: [], collections: [], recentlyPlayed: [], epochDay: 20_001)
        // Same candidates, different order/composition. With 30 items the odds
        // of an identical shuffle are negligible.
        #expect(today != tomorrow)
    }

    @Test func atMostThreeRowsOfTwelve() {
        let movies = makeLibrary(count: 50)
        let rows = discoveryRows(movies: movies, shows: [], collections: [], recentlyPlayed: movies, epochDay: 3)
        #expect(rows.count <= 3)
        #expect(rows.allSatisfy { $0.items.count <= 12 })
    }

    @Test func thinShelvesAreDropped() {
        // Three unstarted movies: below the four-item floor, so no shelf at
        // all can be built from them.
        let movies = (1...3).map { movie(Int64($0)) }
        let rows = discoveryRows(movies: movies, shows: [], collections: [], recentlyPlayed: [], epochDay: 5)
        #expect(rows.isEmpty)
    }

    @Test func watchItAgainKeepsServerOrder() {
        let movies = makeLibrary(count: 4)
        let recentlyPlayed = [movie(101), movie(102), movie(103), movie(104)]
        // Find a day where the row appears, then check its order.
        for day in Int64(0)..<40 {
            let rows = discoveryRows(movies: movies, shows: [], collections: [], recentlyPlayed: recentlyPlayed, epochDay: day)
            if let again = rows.first(where: { $0.key == "again" }) {
                #expect(again.items.map(\.id) == [101, 102, 103, 104])
                return
            }
        }
        Issue.record("Watch It Again never surfaced in 40 days")
    }

    @Test func quickWatchOnlyTakesShortUnstartedMovies() {
        let short = (1...6).map { movie(Int64($0), durationMs: 80 * 60 * 1000) }
        let long = (7...12).map { movie(Int64($0), durationMs: 150 * 60 * 1000) }
        let startedShort = (13...18).map { movie(Int64($0), started: true, durationMs: 70 * 60 * 1000) }
        for day in Int64(0)..<40 {
            let rows = discoveryRows(movies: short + long + startedShort, shows: [], collections: [], recentlyPlayed: [], epochDay: day)
            if let quick = rows.first(where: { $0.key == "quick" }) {
                #expect(quick.items.allSatisfy { $0.id <= 6 })
                return
            }
        }
        Issue.record("A Quick Watch never surfaced in 40 days")
    }

    @Test func highlyRatedFloorsAtSevenPointFive() {
        let rated = (1...6).map { movie(Int64($0), vote: 8.0) }
        let unrated = (7...12).map { movie(Int64($0), vote: 6.0) }
        for day in Int64(0)..<40 {
            let rows = discoveryRows(movies: rated + unrated, shows: [], collections: [], recentlyPlayed: [], epochDay: day)
            if let row = rows.first(where: { $0.key == "rated" }) {
                #expect(row.items.allSatisfy { ($0.voteAverage ?? 0) >= 7.5 })
                return
            }
        }
        Issue.record("Highly Rated never surfaced in 40 days")
    }

    @Test func showStartednessCountsWatchedEpisodes() {
        let untouched = makeItem(id: 1, kind: "show", episodeCount: 10, unwatchedCount: 10)
        let inProgress = makeItem(id: 2, kind: "show", episodeCount: 10, unwatchedCount: 4)
        #expect(!untouched.isStarted)
        #expect(inProgress.isStarted)
    }

    @Test func movieStartednessIsAnyPlaybackState() {
        #expect(!movie(1).isStarted)
        #expect(movie(2, started: true).isStarted)
    }

    @Test func pickLabelFollowsClock() {
        #expect(featuredPickLabel(hour: 6) == "Today's Pick")
        #expect(featuredPickLabel(hour: 17) == "Today's Pick")
        #expect(featuredPickLabel(hour: 18) == "Tonight's Pick")
        #expect(featuredPickLabel(hour: 2) == "Tonight's Pick")
    }
}
