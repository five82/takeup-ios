import Testing
@testable import Takeup

private func makeOption(
    path: String,
    width: Int = 1000,
    height: Int = 1500,
    voteAverage: Double? = nil,
    voteCount: Int? = nil,
    selected: Bool = false
) -> ImageOption {
    ImageOption(
        provider: "tmdb", providerPath: path, language: nil,
        width: width, height: height, aspectRatio: nil,
        voteAverage: voteAverage, voteCount: voteCount,
        thumbnailUrl: "https://image.tmdb.org/t/p/w342\(path)", selected: selected
    )
}

@Suite struct ArtworkSortTests {
    @Test func sortsByResolutionFirst() {
        let small = makeOption(path: "/small.jpg", width: 500, height: 750, voteAverage: 9.9)
        let large = makeOption(path: "/large.jpg", width: 2000, height: 3000, voteAverage: 1.0)
        #expect(sortedArtworkOptions([small, large]).map(\.providerPath) == ["/large.jpg", "/small.jpg"])
    }

    @Test func breaksResolutionTiesByVoteAverageThenCount() {
        let low = makeOption(path: "/low.jpg", voteAverage: 5.0, voteCount: 900)
        let high = makeOption(path: "/high.jpg", voteAverage: 7.5, voteCount: 10)
        let popular = makeOption(path: "/popular.jpg", voteAverage: 5.0, voteCount: 2000)
        let sorted = sortedArtworkOptions([low, high, popular])
        #expect(sorted.map(\.providerPath) == ["/high.jpg", "/popular.jpg", "/low.jpg"])
    }

    @Test func missingVotesSortLast() {
        let unrated = makeOption(path: "/unrated.jpg")
        let rated = makeOption(path: "/rated.jpg", voteAverage: 3.0)
        #expect(sortedArtworkOptions([unrated, rated]).map(\.providerPath) == ["/rated.jpg", "/unrated.jpg"])
    }
}

@Suite struct ArtworkSelectionTests {
    @Test func marksOnlyTheChosenOptionSelected() {
        let options = [
            makeOption(path: "/a.jpg", selected: true),
            makeOption(path: "/b.jpg"),
            makeOption(path: "/c.jpg"),
        ]
        let updated = selectingArtworkOption(options, chosen: options[2])
        #expect(updated.map(\.selected) == [false, false, true])
    }

    @Test func keepsOrderAndFields() {
        let options = [
            makeOption(path: "/a.jpg", width: 100, height: 200),
            makeOption(path: "/b.jpg", width: 300, height: 400),
        ]
        let updated = selectingArtworkOption(options, chosen: options[0])
        #expect(updated.map(\.providerPath) == ["/a.jpg", "/b.jpg"])
        #expect(updated[1].width == 300)
    }
}
