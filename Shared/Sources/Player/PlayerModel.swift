import SwiftUI

/// The SwiftUI bridge to MPVPlayerController, shared by the iPad and TV
/// players; each platform builds its own chrome around it.
struct MPVPlayerView: UIViewControllerRepresentable {
    let url: URL
    let startSeconds: Double
    let model: PlayerModel

    func makeUIViewController(context: Context) -> MPVPlayerController {
        let controller = MPVPlayerController()
        controller.playURL = url
        controller.startSeconds = startSeconds
        controller.onStateChange = { [weak model] state in
            model?.apply(state)
        }
        controller.onTracksChange = { [weak model] tracks in
            model?.applyTracks(tracks)
        }
        controller.onSubtitleTextChange = { [weak model] text in
            model?.applySubtitleText(text)
        }
        model.controller = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: MPVPlayerController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: MPVPlayerController, coordinator: ()) {
        uiViewController.shutdown()
    }
}

@Observable
@MainActor
final class PlayerModel {
    var timeSeconds: Double = 0
    var durationSeconds: Double = 0
    var paused = false
    var buffering = true
    var ended = false
    var audioTracks: [MPVTrack] = []
    var subtitleTracks: [MPVTrack] = []
    var selectedAudioId: Int?
    var selectedSubtitleId: Int?
    var hasMultipleAudioTracks: Bool { audioTracks.count > 1 }
    /// The cues on screen right now, drawn by SubtitleOverlay.
    var subtitleCues: [SubtitleCue] = []
    /// Display aspect of the picture, nil until the file loads.
    var videoAspect: Double?

    weak var controller: MPVPlayerController?

    func apply(_ state: MPVPlayerController.ObservedState) {
        timeSeconds = state.timeSeconds
        durationSeconds = state.durationSeconds
        paused = state.paused
        buffering = state.buffering
        ended = state.ended
        videoAspect = state.videoAspect
    }

    func applyTracks(_ tracks: [MPVTrack]) {
        audioTracks = tracks.filter { $0.type == "audio" }
        // SRT only, mirroring the Android app; image subs (PGS) are hidden.
        subtitleTracks = tracks.filter { $0.type == "sub" && $0.codec == "subrip" }
        selectedAudioId = audioTracks.first { $0.selected == true }?.id
        let selectedSub = tracks.first { $0.type == "sub" && $0.selected == true }
        if let selectedSub, selectedSub.codec != "subrip" {
            // mpv auto-picked an image-based track; turn it off.
            selectSubtitle(nil)
        } else {
            selectedSubtitleId = selectedSub?.id
        }
    }

    func selectAudio(_ id: Int) {
        controller?.setAudioTrack(id)
        selectedAudioId = id
    }

    func applySubtitleText(_ text: String?) {
        subtitleCues = SubtitleCue.parse(text)
    }

    func selectSubtitle(_ id: Int?) {
        controller?.setSubtitleTrack(id)
        selectedSubtitleId = id
        // The last cue of the old track would otherwise hang there until the
        // new one (or none at all) has something to say.
        subtitleCues = []
    }

    func replay() {
        controller?.seek(to: 0)
        controller?.setPaused(false)
    }
}
