import SwiftUI

private struct MPVPlayerView: UIViewControllerRepresentable {
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
    var audioTracks: [MPVTrack] = []
    var subtitleTracks: [MPVTrack] = []
    var selectedAudioId: Int?
    var selectedSubtitleId: Int?

    weak var controller: MPVPlayerController?

    func apply(_ state: MPVPlayerController.ObservedState) {
        timeSeconds = state.timeSeconds
        durationSeconds = state.durationSeconds
        paused = state.paused
        buffering = state.buffering
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

    func selectSubtitle(_ id: Int?) {
        controller?.setSubtitleTrack(id)
        selectedSubtitleId = id
    }
}

/// Full-screen playback with minimal overlay controls. Mirrors the Android
/// app's progress protocol: report every 10s while playing, on pause, and
/// once more on exit.
struct PlayerScreen: View {
    let item: Item

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.dismiss) private var dismiss

    @State private var model = PlayerModel()
    @State private var playbackURL: URL?
    @State private var startSeconds: Double = 0
    @State private var chapters: [Chapter] = []
    @State private var loadError: String?
    @State private var controlsVisible = true
    @State private var scrubbing = false
    @State private var scrubTarget: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let playbackURL {
                MPVPlayerView(
                    url: playbackURL,
                    startSeconds: startSeconds,
                    model: model
                )
                .ignoresSafeArea()
            } else if let loadError {
                ContentUnavailableView("Playback Failed", systemImage: "play.slash", description: Text(loadError))
                    .foregroundStyle(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }

            if controlsVisible {
                controls
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                controlsVisible.toggle()
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task { await start() }
        .task { await progressLoop() }
        .onDisappear {
            Task { await reportProgress() }
        }
    }

    private var controls: some View {
        VStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .padding(12)
                        .background(.black.opacity(0.5), in: Circle())
                }
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if model.buffering {
                    ProgressView().tint(.white)
                }
                if !model.audioTracks.isEmpty || !model.subtitleTracks.isEmpty {
                    trackMenu
                }
            }
            Spacer()
            VStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { scrubbing ? scrubTarget : model.timeSeconds },
                        set: { scrubTarget = $0 }
                    ),
                    in: 0...max(model.durationSeconds, 1)
                ) { editing in
                    if editing {
                        scrubTarget = model.timeSeconds
                        scrubbing = true
                    } else {
                        model.controller?.seek(to: scrubTarget)
                        scrubbing = false
                    }
                }
                HStack {
                    Text(formatTime(model.timeSeconds))
                    Spacer()
                    HStack(spacing: 36) {
                        if hasChapters {
                            Button {
                                model.controller?.stepChapter(-1)
                            } label: {
                                Image(systemName: "backward.end.alt.fill").font(.title2)
                            }
                        }
                        Button {
                            model.controller?.seek(by: -10)
                        } label: {
                            Image(systemName: "gobackward.10").font(.title2)
                        }
                        Button {
                            model.controller?.togglePause()
                        } label: {
                            Image(systemName: model.paused ? "play.fill" : "pause.fill")
                                .font(.system(size: 40))
                        }
                        Button {
                            model.controller?.seek(by: 10)
                        } label: {
                            Image(systemName: "goforward.10").font(.title2)
                        }
                        if hasChapters {
                            Button {
                                model.controller?.stepChapter(1)
                            } label: {
                                Image(systemName: "forward.end.alt.fill").font(.title2)
                            }
                        }
                    }
                    Spacer()
                    Text(formatTime(model.durationSeconds))
                }
                .font(.subheadline.monospacedDigit())
            }
            .padding(16)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
        .padding()
        .foregroundStyle(.white)
    }

    private var hasChapters: Bool {
        !chapters.isEmpty
    }

    private var trackMenu: some View {
        Menu {
            if !model.audioTracks.isEmpty {
                Section("Audio") {
                    ForEach(model.audioTracks, id: \.uid) { track in
                        Button {
                            model.selectAudio(track.id)
                        } label: {
                            if model.selectedAudioId == track.id {
                                Label(track.displayName, systemImage: "checkmark")
                            } else {
                                Text(track.displayName)
                            }
                        }
                    }
                }
            }
            if !model.subtitleTracks.isEmpty {
                Section("Subtitles") {
                    Button {
                        model.selectSubtitle(nil)
                    } label: {
                        if model.selectedSubtitleId == nil {
                            Label("Off", systemImage: "checkmark")
                        } else {
                            Text("Off")
                        }
                    }
                    ForEach(model.subtitleTracks, id: \.uid) { track in
                        Button {
                            model.selectSubtitle(track.id)
                        } label: {
                            if model.selectedSubtitleId == track.id {
                                Label(track.displayName, systemImage: "checkmark")
                            } else {
                                Text(track.displayName)
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "captions.bubble")
                .font(.title2)
                .padding(12)
                .background(.black.opacity(0.5), in: Circle())
        }
    }

    private func start() async {
        // Downloaded items play from disk even when the server is reachable;
        // the server (when up) still supplies the freshest resume position.
        if let entry = downloads.entry(for: item.id) {
            chapters = entry.item.media?.chapters ?? []
            var resumeMs = item.progress?.resumePositionMs ?? entry.item.progress?.resumePositionMs ?? 0
            // Refresh resume from the server, but never hold up local playback
            // for more than a moment when the server is unreachable.
            if let client = appEnvironment.client {
                let refresh = Task { try? await client.item(id: item.id) }
                let watchdog = Task {
                    try? await Task.sleep(for: .seconds(3))
                    refresh.cancel()
                }
                if let fresh = await refresh.value {
                    resumeMs = fresh.progress?.resumePositionMs ?? 0
                }
                watchdog.cancel()
            }
            startSeconds = Double(resumeMs) / 1000
            playbackURL = downloads.localURL(for: entry)
            return
        }
        guard let client = appEnvironment.client else {
            loadError = "No Loom server configured."
            return
        }
        do {
            let playback = try await client.playback(id: item.id)
            chapters = playback.media.chapters ?? []
            startSeconds = Double(item.progress?.resumePositionMs ?? 0) / 1000
            playbackURL = client.streamURL(for: playback)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func progressLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            await reportProgress()
        }
    }

    private func reportProgress() async {
        guard model.timeSeconds > 0, model.durationSeconds > 0 else { return }
        let positionMs = Int64(model.timeSeconds * 1000)
        let durationMs = Int64(model.durationSeconds * 1000)
        do {
            guard let client = appEnvironment.client else { throw URLError(.cannotConnectToHost) }
            try await client.reportProgress(id: item.id, positionMs: positionMs, durationMs: durationMs)
        } catch {
            // Server unreachable: keep the latest position for a later flush.
            downloads.queueProgress(itemId: item.id, positionMs: positionMs, durationMs: durationMs)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
