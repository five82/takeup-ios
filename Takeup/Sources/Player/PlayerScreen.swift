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

// The video renders on a surface that can't be blurred behind, so a deep
// translucent fill does the work a material would otherwise share.
private let chipFill = Color(hexValue: 0x0A0E17).opacity(0.62)
private let chipStroke = Color.ink.opacity(0.14)
private let consoleFill = Color(hexValue: 0x0B0F1A).opacity(0.75)

/// Full-screen playback with the Takeup console: the chapter scrub thread,
/// a dead-centered transport, and accents woven from the poster. Mirrors the
/// Android app's progress protocol: report every 10s while playing, on
/// pause, and once more on exit.
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
    @State private var cropped = false
    @State private var chaptersPresented = false
    @State private var accent = WovenAccent.neutral
    @State private var threads: [RGB] = []
    /// Any interaction bumps this; the auto-hide countdown restarts.
    @State private var interactionTick = 0

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
                ErrorState(message: loadError) { Task { await start() } }
            } else {
                ProgressView()
                    .tint(.white)
            }

            // The tap catcher sits above the mpv view: the UIKit video view
            // swallows touches, so a gesture on the enclosing ZStack alone
            // never fires.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        controlsVisible.toggle()
                    }
                    interactionTick += 1
                }
                .onContinuousHover { phase in
                    // A pointer sweep reveals the chrome without pausing
                    // anything.
                    if case .active = phase, !controlsVisible, !model.ended {
                        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true }
                        interactionTick += 1
                    }
                }

            if controlsVisible && !model.ended {
                chrome
                    .transition(.opacity)
            }

            if model.ended {
                endOverlay
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .background {
            keyboardShortcuts
        }
        // Chrome auto-hides while playing; every interaction restarts the
        // countdown.
        .task(id: interactionTick) {
            try? await Task.sleep(for: .milliseconds(3500))
            guard !Task.isCancelled, !model.paused, !scrubbing, !model.ended,
                  !chaptersPresented else { return }
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
        }
        // Closing the chapter popover restarts the auto-hide countdown, which
        // may have fired (and been ignored) while the popover was up.
        .onChange(of: chaptersPresented) { _, presented in
            if !presented { interactionTick += 1 }
        }
        // CLI-driven check for the session swap (see AGENTS.md): chain into
        // the next episode as soon as the end overlay would offer it.
        .onChange(of: model.ended) { _, ended in
            guard ended, ProcessInfo.processInfo.arguments.contains("-autochain"),
                  let next = nextEpisode else { return }
            playNext(next)
        }
        .task {
            await start()
            // CLI-driven check (see AGENTS.md): open the chapter popover so a
            // screenshot can verify it without a tap.
            if ProcessInfo.processInfo.arguments.contains("-chapters"), !chapters.isEmpty {
                try? await Task.sleep(for: .seconds(2))
                chaptersPresented = true
            }
            await loadNextEpisode()
            await loadThreads()
        }
        .task { await progressLoop() }
        .onDisappear {
            Task { await reportProgress() }
        }
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack {
            topBar
            Spacer()
            console
        }
        .padding(14)
        .foregroundStyle(Color.ink)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            chromeChip(systemImage: "xmark", size: 56) {
                dismiss()
            }
            Spacer()
            VStack(spacing: 3) {
                Text(item.title)
                    .font(.titleMedium)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                if let chapterName = currentChapterName {
                    Text(chapterName)
                        .font(.labelMedium)
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .background(chipFill, in: Capsule())
            .overlay(Capsule().stroke(chipStroke, lineWidth: 1))
            Spacer()
            if model.buffering {
                ProgressView()
                    .tint(.white)
                    .padding(.trailing, 8)
            }
            chromeChip(systemImage: cropped ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", size: 56) {
                cropped.toggle()
                model.controller?.setCropToFill(cropped)
                interactionTick += 1
            }
        }
    }

    private func chromeChip(systemImage: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.ink)
                .frame(width: size, height: size)
                .background(chipFill, in: Circle())
                .overlay(Circle().stroke(chipStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    private var console: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Text(formatClock(scrubbing ? scrubTarget : model.timeSeconds))
                    .font(.labelLarge.monospacedDigit())
                    .foregroundStyle(Color.ink)
                ChapterScrubBar(
                    time: scrubbing ? scrubTarget : model.timeSeconds,
                    duration: max(model.durationSeconds, 1),
                    chapters: chapters,
                    accent: accent.tint,
                    onScrub: { target in
                        scrubbing = true
                        scrubTarget = target
                        interactionTick += 1
                    },
                    onCommit: { target in
                        model.controller?.seek(to: target)
                        scrubbing = false
                        interactionTick += 1
                    }
                )
                Text(formatClock(model.durationSeconds))
                    .font(.labelLarge.monospacedDigit())
                    .foregroundStyle(Color.muted)
            }

            // Three zones so the play button stays dead-center regardless of
            // what the side zones show.
            HStack(spacing: 0) {
                HStack {
                    if !chapters.isEmpty {
                        chaptersButton
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 26) {
                    transportChip(systemImage: "gobackward.10", size: 64) {
                        model.controller?.seek(by: -10)
                        interactionTick += 1
                    }
                    Button {
                        model.controller?.togglePause()
                        interactionTick += 1
                    } label: {
                        Image(systemName: model.paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(Color.ink)
                            .frame(width: 80, height: 80)
                            .background(Color.ink.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.lift)
                    transportChip(systemImage: "goforward.10", size: 64) {
                        model.controller?.seek(by: 10)
                        interactionTick += 1
                    }
                }

                HStack(spacing: 8) {
                    if !model.audioTracks.isEmpty {
                        audioMenu
                    }
                    if !model.subtitleTracks.isEmpty {
                        subtitleMenu
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(consoleFill, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(chipStroke, lineWidth: 1))
    }

    private func transportChip(systemImage: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.ink)
                .frame(width: size, height: size)
                .background(Color.ink.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    private func consolePillLabel(_ text: String) -> some View {
        Text(text)
            .font(.labelLarge)
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 20)
            .frame(minWidth: 64, minHeight: 44)
            .background(Color.ink.opacity(0.08), in: Capsule())
    }

    private var currentChapter: Chapter? {
        let positionMs = Int64((scrubbing ? scrubTarget : model.timeSeconds) * 1000)
        return chapters.last { ($0.startMs ?? 0) <= positionMs }
    }

    private var currentChapterName: String? {
        currentChapter?.title
    }

    // A system Menu clips long chapter lists at the screen edge with no way
    // to scroll, so the pill opens a scrollable popover instead.
    private var chaptersButton: some View {
        Button {
            chaptersPresented = true
            interactionTick += 1
        } label: {
            consolePillLabel("Chapters")
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .popover(isPresented: $chaptersPresented) {
            ChapterList(
                chapters: chapters,
                currentIndex: currentChapter?.index,
                accent: accent.tint
            ) { chapter in
                model.controller?.seek(to: Double(chapter.startMs ?? 0) / 1000)
                chaptersPresented = false
            }
            .presentationCompactAdaptation(.popover)
            .presentationBackground(consoleFill)
        }
    }

    private var audioMenu: some View {
        Menu {
            ForEach(model.audioTracks, id: \.uid) { track in
                Button {
                    model.selectAudio(track.id)
                    interactionTick += 1
                } label: {
                    if model.selectedAudioId == track.id {
                        Label(track.displayName, systemImage: "checkmark")
                    } else {
                        Text(track.displayName)
                    }
                }
            }
        } label: {
            consolePillLabel("Audio")
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    private var subtitleMenu: some View {
        Menu {
            Button {
                model.selectSubtitle(nil)
                interactionTick += 1
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
                    interactionTick += 1
                } label: {
                    if model.selectedSubtitleId == track.id {
                        Label(track.displayName, systemImage: "checkmark")
                    } else {
                        Text(track.displayName)
                    }
                }
            }
        } label: {
            consolePillLabel("CC")
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    /// Space toggles pause, arrows seek, shift-arrows step chapters.
    private var keyboardShortcuts: some View {
        Group {
            Button("") { model.controller?.togglePause(); interactionTick += 1 }
                .keyboardShortcut(.space, modifiers: [])
            Button("") { model.controller?.seek(by: -10); interactionTick += 1 }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { model.controller?.seek(by: 10); interactionTick += 1 }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { model.controller?.stepChapter(-1); interactionTick += 1 }
                .keyboardShortcut(.leftArrow, modifiers: .shift)
            Button("") { model.controller?.stepChapter(1); interactionTick += 1 }
                .keyboardShortcut(.rightArrow, modifiers: .shift)
            Button("") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .hidden()
    }

    /// Shown when playback reaches the end: the finished title's colors
    /// linger as drifting threads while up-next appears. No auto-advance
    /// countdown, mirroring the Android app.
    private var endOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            ThreeThreads(colors: threads, drifting: true)
                .opacity(0.8)
            VStack(spacing: 12) {
                if let next = nextEpisode {
                    RowLabel(text: "Up next")
                    Button {
                        playNext(next)
                    } label: {
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.white.opacity(0.1))
                                if let url = thumbURL(for: next) {
                                    CachedImage(url: url, contentMode: .fill) { Color.clear }
                                }
                            }
                            .frame(width: 320, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text([episodeLabel(next), next.title].compactMap { $0 }.joined(separator: " · "))
                                .font(.titleMedium)
                                .foregroundStyle(Color.ink)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.lift)
                } else {
                    Button("Play again") {
                        model.replay()
                    }
                    .font(.titleMedium)
                    .foregroundStyle(Color.ink)
                    .buttonStyle(.plain)
                }
                Button("Done") {
                    dismiss()
                }
                .font(.bodyMedium)
                .foregroundStyle(Color.muted)
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Session plumbing

    private func start() async {
        loadError = nil
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

    /// The scrub thread and end overlay take their color from the poster.
    private func loadThreads() async {
        guard let url = appEnvironment.client?.imageURL(id: item.posterImageId, tag: item.posterImageTag, width: 240)
        else { return }
        let extracted = await WovenExtractor.threads(for: url)
        withAnimation(.easeInOut(duration: 0.45)) {
            threads = extracted
            if let seed = extracted.first {
                accent = .from(seed: seed)
            }
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
}

/// The chapter picker behind the Chapters pill: a scrollable list with start
/// times, opened scrolled to the playing chapter.
private struct ChapterList: View {
    var chapters: [Chapter]
    var currentIndex: Int?
    var accent: Color
    var onSelect: (Chapter) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(chapters, id: \.index) { chapter in
                        let current = chapter.index == currentIndex
                        Button {
                            onSelect(chapter)
                        } label: {
                            HStack(spacing: 14) {
                                Text(chapter.title ?? "Chapter \(chapter.index + 1)")
                                    .font(.labelLarge)
                                    .foregroundStyle(current ? accent : Color.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 14)
                                Text(formatClock(Double(chapter.startMs ?? 0) / 1000))
                                    .font(.labelMedium.monospacedDigit())
                                    .foregroundStyle(current ? accent.opacity(0.8) : Color.muted)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                current ? accent.opacity(0.14) : .clear,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                        .id(chapter.index)
                    }
                }
                .padding(10)
            }
            .frame(width: 360)
            .frame(maxHeight: 440)
            .onAppear {
                if let currentIndex {
                    proxy.scrollTo(currentIndex, anchor: .center)
                }
            }
        }
    }
}

/// The progress thread grown up: a thin woven line with chapter marks as
/// warp ticks and a glowing thumb. The whole 44pt-tall band is grabbable.
private struct ChapterScrubBar: View {
    var time: Double
    var duration: Double
    var chapters: [Chapter]
    var accent: Color
    var onScrub: (Double) -> Void
    var onCommit: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = min(max(time / duration, 0), 1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accent.opacity(0.22))
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(accent)
                    .frame(width: width * fraction, height: 3)
                ForEach(chapters, id: \.index) { chapter in
                    let chapterFraction = Double(chapter.startMs ?? 0) / (duration * 1000)
                    if chapterFraction > 0, chapterFraction < 1 {
                        RoundedRectangle(cornerRadius: 0.75)
                            .fill(Color.ink.opacity(0.45))
                            .frame(width: 1.5, height: 9)
                            .offset(x: width * chapterFraction)
                    }
                }
                Circle()
                    .fill(accent.opacity(0.25))
                    .frame(width: 26, height: 26)
                    .offset(x: width * fraction - 13)
                Circle()
                    .fill(accent)
                    .frame(width: 16, height: 16)
                    .offset(x: width * fraction - 8)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onScrub(target(for: value.location.x, width: width))
                    }
                    .onEnded { value in
                        onCommit(target(for: value.location.x, width: width))
                    }
            )
        }
        .frame(height: 44)
    }

    private func target(for x: CGFloat, width: CGFloat) -> Double {
        duration * min(max(Double(x / width), 0), 1)
    }
}
