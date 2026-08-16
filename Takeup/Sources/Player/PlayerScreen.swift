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
    var ended = false
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
        ended = state.ended
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

    func replay() {
        controller?.seek(to: 0)
        controller?.setPaused(false)
    }
}

/// Presents one playback session at a time; picking "Up next" at the end of
/// an episode swaps the item, and the `.id` change rebuilds the session (a
/// fresh mpv instance), which also final-reports the finished episode.
struct PlayerScreen: View {
    let item: Item

    @State private var chained: Item?

    var body: some View {
        let active = chained ?? item
        PlayerSessionView(item: active) { next in
            chained = next
        }
        .id(active.id)
    }
}

/// Full-screen playback with minimal overlay controls. Mirrors the Android
/// app's progress protocol: report every 10s while playing, on pause, and
/// once more on exit.
private struct PlayerSessionView: View {
    let item: Item
    let playNext: (Item) -> Void

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.dismiss) private var dismiss

    @State private var model = PlayerModel()
    @State private var playbackURL: URL?
    @State private var startSeconds: Double = 0
    @State private var chapters: [Chapter] = []
    @State private var nextEpisode: Item?
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

            if controlsVisible && !model.ended {
                controls
            }

            if model.ended {
                endOverlay
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
        // CLI-driven check for the session swap (see AGENTS.md): chain into
        // the next episode as soon as the end overlay would offer it.
        .onChange(of: model.ended) { _, ended in
            guard ended, ProcessInfo.processInfo.arguments.contains("-autochain"),
                  let next = nextEpisode else { return }
            playNext(next)
        }
        .task {
            await start()
            await loadNextEpisode()
        }
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

    /// Shown when playback reaches the end: a tappable "Up next" card for
    /// episodes with a successor, otherwise replay/exit. No auto-advance
    /// countdown, mirroring the Android app.
    private var endOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 12) {
                if let next = nextEpisode {
                    Text("Up next")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                    Button {
                        playNext(next)
                    } label: {
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.white.opacity(0.1))
                                if let url = thumbURL(for: next) {
                                    AsyncImage(url: url) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.clear
                                    }
                                }
                            }
                            .frame(width: 320, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text("\(episodeLabel(next)) · \(next.title)")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Play Again") {
                        model.replay()
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                }
                Button("Done") {
                    dismiss()
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 8)
            }
        }
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

    /// Loom's Next Up cannot say what follows this specific episode, so the
    /// successor is computed locally from the show's own episode list — or,
    /// when the server is unreachable, from the downloaded episodes of the
    /// same season (the download catalog does not capture show ancestry).
    private func loadNextEpisode() async {
        guard item.kind == "episode" else { return }
        if let client = appEnvironment.client,
           let next = try? await onlineNextEpisode(client) {
            nextEpisode = next
            return
        }
        let siblings = downloads.completed.map(\.item).filter { $0.parentId == item.parentId }
        nextEpisode = nextEpisodeAfter(item.id, in: siblings)
    }

    private func onlineNextEpisode(_ client: LoomClient) async throws -> Item? {
        guard let seasonId = item.parentId else { return nil }
        let season = try await client.item(id: seasonId)
        let episodes: [Item]
        if let showId = season.parentId {
            let seasons = try await client.children(of: showId).items.filter { $0.kind == "season" }
            episodes = try await withThrowingTaskGroup(of: [Item].self) { group in
                for season in seasons {
                    group.addTask { try await client.children(of: season.id).items }
                }
                return try await group.reduce(into: []) { $0 += $1 }
            }
        } else {
            episodes = try await client.children(of: seasonId).items
        }
        return nextEpisodeAfter(item.id, in: episodes)
    }

    private func thumbURL(for item: Item) -> URL? {
        appEnvironment.client?.imageURL(id: item.thumbImageId, tag: item.thumbImageTag, width: 480)
    }

    private func episodeLabel(_ item: Item) -> String {
        guard let season = item.seasonNumber, let episode = item.episodeNumber else {
            return "Episode"
        }
        return "S\(season) E\(episode)"
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
