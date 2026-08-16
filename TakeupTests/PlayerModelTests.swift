import Testing
@testable import Takeup

@MainActor
struct PlayerModelTests {
    @Test func onlySubripSubtitlesAreOffered() {
        let model = PlayerModel()
        model.applyTracks([
            makeTrack(id: 1, type: "audio", lang: "eng", codec: "opus", selected: true),
            makeTrack(id: 1, type: "sub", lang: "eng", codec: "subrip", selected: true),
            makeTrack(id: 2, type: "sub", lang: "eng", codec: "hdmv_pgs_subtitle"),
        ])
        #expect(model.subtitleTracks.map(\.id) == [1])
        #expect(model.selectedAudioId == 1)
        #expect(model.selectedSubtitleId == 1)
    }

    @Test func autoPickedImageSubtitleIsDeselected() {
        let model = PlayerModel()
        model.applyTracks([
            makeTrack(id: 1, type: "sub", lang: "eng", codec: "subrip"),
            makeTrack(id: 2, type: "sub", lang: "eng", codec: "hdmv_pgs_subtitle", selected: true),
        ])
        #expect(model.selectedSubtitleId == nil)
    }

    @Test func trackUidDisambiguatesTypes() {
        // Audio and subtitle tracks share numeric ids in mpv's track-list.
        let audio = makeTrack(id: 1, type: "audio")
        let sub = makeTrack(id: 1, type: "sub")
        #expect(audio.uid != sub.uid)
    }

    @Test func displayNamePrefersTitleAndLanguage() {
        #expect(makeTrack(id: 1, type: "sub", lang: "eng", title: "Full").displayName == "Full · ENG")
        #expect(makeTrack(id: 2, type: "sub", codec: "subrip").displayName == "subrip")
        #expect(makeTrack(id: 3, type: "sub").displayName == "Track 3")
    }
}
