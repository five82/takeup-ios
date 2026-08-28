import Testing
@testable import Takeup

struct FeaturedPickLabelTests {
    @Test func pickLabelFollowsClock() {
        #expect(featuredPickLabel(hour: 6) == "Today's Pick")
        #expect(featuredPickLabel(hour: 17) == "Today's Pick")
        #expect(featuredPickLabel(hour: 18) == "Tonight's Pick")
        #expect(featuredPickLabel(hour: 2) == "Tonight's Pick")
    }
}
