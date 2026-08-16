import Testing
@testable import Takeup

struct NextEpisodeTests {
    // A three-season show with specials, deliberately out of order.
    private let show = [
        makeItem(id: 21, season: 2, episode: 1),
        makeItem(id: 12, season: 1, episode: 2),
        makeItem(id: 11, season: 1, episode: 1),
        makeItem(id: 22, season: 2, episode: 2),
        makeItem(id: 91, season: 0, episode: 1),
        makeItem(id: 92, season: 0, episode: 2),
    ]

    @Test func nextWithinSeason() {
        #expect(nextEpisodeAfter(11, in: show)?.id == 12)
    }

    @Test func crossesSeasonBoundary() {
        #expect(nextEpisodeAfter(12, in: show)?.id == 21)
    }

    @Test func lastEpisodeHasNoSuccessor() {
        #expect(nextEpisodeAfter(22, in: show) == nil)
    }

    @Test func specialsChainOnlyWithinSpecials() {
        #expect(nextEpisodeAfter(91, in: show)?.id == 92)
        #expect(nextEpisodeAfter(92, in: show) == nil)
    }

    @Test func regularEpisodesSkipSpecials() {
        // S2E2 is the last regular episode; specials must not follow it.
        #expect(nextEpisodeAfter(22, in: show) == nil)
    }

    @Test func unknownEpisodeYieldsNil() {
        #expect(nextEpisodeAfter(999, in: show) == nil)
    }

    @Test func nonEpisodesAreIgnored() {
        let mixed = show + [makeItem(id: 50, kind: "season", season: 1, episode: 3)]
        #expect(nextEpisodeAfter(12, in: mixed)?.id == 21)
    }

    @Test func missingNumbersSortAsZero() {
        let episodes = [
            makeItem(id: 1, season: 1, episode: nil),
            makeItem(id: 2, season: 1, episode: 1),
        ]
        #expect(nextEpisodeAfter(1, in: episodes)?.id == 2)
    }
}
