import Foundation
import Testing
@testable import Takeup

/// Loom is a Go server: empty lists arrive as `"items": null`, and field
/// names are snake_case.
struct LoomDecodingTests {
    @Test func itemsPageDecodesNullItemsAsEmpty() throws {
        let json = Data(#"{"items":null,"limit":50,"offset":0}"#.utf8)
        let page = try loomDecoder().decode(ItemsPage.self, from: json)
        #expect(page.items.isEmpty)
        #expect(page.limit == 50)
    }

    @Test func searchResponseDecodesNullItemsAsEmpty() throws {
        let json = Data(#"{"items":null,"fuzzy":true}"#.utf8)
        let response = try loomDecoder().decode(SearchResponse.self, from: json)
        #expect(response.items.isEmpty)
        #expect(response.fuzzy == true)
    }

    @Test func itemDecodesSnakeCaseFields() throws {
        let json = Data("""
        {
            "items": [{
                "id": 523,
                "parent_id": 502,
                "kind": "episode",
                "title": "Crying",
                "season_number": 8,
                "episode_number": 2,
                "duration_ms": 498079,
                "progress": {
                    "position_ms": 440000,
                    "duration_ms": 498079,
                    "played": false,
                    "resume_position_ms": 440000
                }
            }]
        }
        """.utf8)
        let page = try loomDecoder().decode(ItemsPage.self, from: json)
        let item = try #require(page.items.first)
        #expect(item.id == 523)
        #expect(item.parentId == 502)
        #expect(item.seasonNumber == 8)
        #expect(item.episodeNumber == 2)
        #expect(item.progress?.resumePositionMs == 440000)
        #expect(item.isPlayable)
    }

    @Test func streamDecodesServerResolution() throws {
        let json = Data("""
        {
            "index": 0,
            "kind": "video",
            "codec": "hevc",
            "width": 2880,
            "height": 2160,
            "resolution": "4k"
        }
        """.utf8)
        let stream = try loomDecoder().decode(Stream.self, from: json)
        #expect(stream.width == 2880)
        #expect(stream.height == 2160)
        #expect(stream.resolution == "4k")
    }

    @Test func imageOptionDecodesSnakeCaseFields() throws {
        let json = Data("""
        {
            "provider": "tmdb",
            "provider_path": "/abc123.jpg",
            "language": "en",
            "width": 2000,
            "height": 3000,
            "aspect_ratio": 0.6667,
            "vote_average": 8.1,
            "vote_count": 42,
            "thumbnail_url": "https://image.tmdb.org/t/p/w300/abc123.jpg",
            "selected": true
        }
        """.utf8)
        let option = try loomDecoder().decode(ImageOption.self, from: json)
        #expect(option.provider == "tmdb")
        #expect(option.providerPath == "/abc123.jpg")
        #expect(option.language == "en")
        #expect(option.width == 2000)
        #expect(option.height == 3000)
        #expect(option.aspectRatio == 0.6667)
        #expect(option.voteAverage == 8.1)
        #expect(option.voteCount == 42)
        #expect(option.thumbnailUrl == "https://image.tmdb.org/t/p/w300/abc123.jpg")
        #expect(option.selected)
    }

    @Test func imageOptionDecodesMissingOmitemptyFieldsAsNil() throws {
        let json = Data("""
        {
            "provider": "local",
            "provider_path": "/data/posters/x.jpg",
            "width": 1000,
            "height": 1500,
            "thumbnail_url": "https://image.tmdb.org/t/p/w300/x.jpg",
            "selected": false
        }
        """.utf8)
        let option = try loomDecoder().decode(ImageOption.self, from: json)
        #expect(option.language == nil)
        #expect(option.aspectRatio == nil)
        #expect(option.voteAverage == nil)
        #expect(option.voteCount == nil)
    }
}
