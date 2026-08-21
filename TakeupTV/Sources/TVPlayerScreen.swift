import SwiftUI

/// Presents one playback session at a time; picking "Up next" at the end of
/// an episode swaps the item, and the `.id` change rebuilds the session (a
/// fresh mpv instance), which also final-reports the finished episode.
struct TVPlayerScreen: View {
    let item: Item

    @State private var chained: Item?

    var body: some View {
        let active = chained ?? item
        TVPlayerSessionView(item: active) { next in
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

/// Which picker panel stands in for the console.
private enum ConsolePanel: String {
    case chapters, audio, subtitles
}

/// Full-screen playback driven by the Siri Remote.
///
/// The remote grammar: play/pause always toggles playback. With the chrome
/// hidden, left/right seek ±10s and click (or up/down) reveals the console.
/// With it visible, focus moves between the transport and pills; Menu hides
/// the console, then closes the player. Progress mirrors the shared protocol —
/// every 10s while playing, on pause, once more on exit — with failed reports
/// simply dropped: the LAN self-heals on the next tick.
private struct TVPlayerSessionView: View {
    let item: Item
    let playNext: (Item) -> Void

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var model = PlayerModel()
    @State private var playbackURL: URL?
    @State private var startSeconds: Double = 0
    @State private var chapters: [Chapter] = []
    @State private var nextEpisode: Item?
    @State private var loadError: String?
    @State private var controlsVisible = true
    @State private var panel: ConsolePanel?
    @State private var accent = WovenAccent.neutral
    @State private var threads: [RGB] = []
    /// Any interaction bumps this; the auto-hide countdown restarts.
    @State private var interactionTick = 0
    @FocusState private var playPauseFocused: Bool

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

            SubtitleOverlay(
                cues: model.subtitleCues,
                aspect: model.videoAspect,
                lift: subtitleLift
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.2), value: subtitleLift)

            if !controlsVisible, !model.ended, playbackURL != nil {
                remoteCatcher
            }

            if controlsVisible && !model.ended {
                chrome
                    .transition(.opacity)
            }

            if model.ended {
                endOverlay
            }
        }
        .onPlayPauseCommand {
            model.controller?.togglePause()
            interactionTick += 1
        }
        .onExitCommand {
            if panel != nil {
                panel = nil
                interactionTick += 1
            } else if controlsVisible && !model.ended && playbackURL != nil {
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
            } else {
                dismiss()
            }
        }
        // Pausing surfaces the chrome so the paused frame is never ambiguous.
        .onChange(of: model.paused) { _, paused in
            if paused {
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true }
            }
            interactionTick += 1
        }
        // Chrome auto-hides while playing; every interaction restarts the
        // countdown.
        .task(id: interactionTick) {
            try? await Task.sleep(for: .milliseconds(3500))
            guard !Task.isCancelled, !model.paused, !model.ended, panel == nil else { return }
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
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
            // CLI-driven check (see AGENTS.md): open a console panel so a
            // screenshot can verify it without remote input.
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "-popover"), flag + 1 < arguments.count {
                try? await Task.sleep(for: .seconds(2))
                switch arguments[flag + 1] {
                case "chapters": panel = chapters.isEmpty ? nil : .chapters
                case "audio": panel = model.hasMultipleAudioTracks ? .audio : nil
                case "cc": panel = model.subtitleTracks.isEmpty ? nil : .subtitles
                default: break
                }
            }
            await loadNextEpisode()
            await loadThreads()
        }
        .task { await progressLoop() }
        .onDisappear {
            Task { await reportProgress() }
        }
    }

    // MARK: - Remote catcher

    /// With the chrome hidden this invisible button is the only focusable
    /// thing on screen: click reveals the console, left/right seek, up/down
    /// also reveal. It exists because the mpv view is not focusable and the
    /// focus engine needs somewhere to stand.
    private var remoteCatcher: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true }
            interactionTick += 1
        } label: {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onMoveCommand { direction in
            switch direction {
            case .left:
                model.controller?.seek(by: -10)
            case .right:
                model.controller?.seek(by: 10)
            default:
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true }
                interactionTick += 1
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Chrome

    /// How far above the surface's bottom edge a bottom cue must sit to clear
    /// the console while it is up.
    private var subtitleLift: CGFloat {
        controlsVisible && !model.ended ? 280 : 0
    }

    private var chrome: some View {
        VStack {
            topBar
            Spacer()
            if let panel {
                panelView(panel)
            } else {
                console
            }
        }
        .padding(.horizontal, TVLayout.sideMargin)
        .padding(.vertical, TVLayout.verticalMargin)
        .foregroundStyle(Color.ink)
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Spacer()
            VStack(spacing: 4) {
                Text(sessionTitle)
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
            .padding(.horizontal, 38)
            .padding(.vertical, 18)
            .background(chipFill, in: Capsule())
            .overlay(Capsule().stroke(chipStroke, lineWidth: 1))
            Spacer()
        }
        .overlay(alignment: .trailing) {
            if model.buffering {
                ProgressView()
                    .tint(.white)
            }
        }
    }

    private var sessionTitle: String {
        [episodeLabel(item), item.title].compactMap { $0 }.joined(separator: " · ")
    }

    private var console: some View {
        VStack(spacing: 18) {
            HStack(spacing: 20) {
                Text(formatClock(model.timeSeconds))
                    .font(.labelLarge.monospacedDigit())
                    .foregroundStyle(Color.ink)
                TVScrubThread(
                    time: model.timeSeconds,
                    duration: max(model.durationSeconds, 1),
                    chapters: chapters,
                    accent: accent.tint
                )
                Text(formatClock(model.durationSeconds))
                    .font(.labelLarge.monospacedDigit())
                    .foregroundStyle(Color.muted)
            }

            // Three zones so the play button stays dead-center regardless of
            // what the side zones show.
            HStack(spacing: 0) {
                HStack(spacing: 12) {
                    if !chapters.isEmpty {
                        consolePill("Chapters") { panel = .chapters }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 30) {
                    transportChip(systemImage: "gobackward.10") {
                        model.controller?.seek(by: -10)
                    }
                    Button {
                        model.controller?.togglePause()
                        interactionTick += 1
                    } label: {
                        Image(systemName: model.paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 44))
                    }
                    .buttonStyle(TVCircleButtonStyle(size: 100, prominent: true))
                    .focused($playPauseFocused)

                    transportChip(systemImage: "goforward.10") {
                        model.controller?.seek(by: 10)
                    }
                }

                // No crop-to-fill on TV: the panel is always a standard 16:9,
                // and non-16:9 films letterbox as the filmmaker intended.
                HStack(spacing: 12) {
                    if model.hasMultipleAudioTracks {
                        consolePill("Audio") { panel = .audio }
                    }
                    if !model.subtitleTracks.isEmpty {
                        consolePill("CC") { panel = .subtitles }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 24)
        .background(consoleFill, in: RoundedRectangle(cornerRadius: 32))
        .overlay(RoundedRectangle(cornerRadius: 32).stroke(chipStroke, lineWidth: 1))
        .defaultFocus($playPauseFocused, true)
    }

    private func consolePill(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            interactionTick += 1
        } label: {
            Text(title)
        }
        .buttonStyle(TVPillButtonStyle())
    }

    private func transportChip(systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            interactionTick += 1
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .medium))
        }
        .buttonStyle(TVCircleButtonStyle(size: 80))
    }

    private var currentChapter: Chapter? {
        let positionMs = Int64(model.timeSeconds * 1000)
        return chapters.last { ($0.startMs ?? 0) <= positionMs }
    }

    private var currentChapterName: String? {
        currentChapter?.title
    }

    // MARK: - Panels

    /// The picker standing in for the console: chapters, audio, or subtitles
    /// as a focus-navigable list, Menu to come back.
    private func panelView(_ panel: ConsolePanel) -> some View {
        let rows: [TVConsoleRow]
        let onSelect: (Int) -> Void
        switch panel {
        case .chapters:
            rows = chapters.map { chapter in
                TVConsoleRow(
                    id: chapter.index,
                    title: chapter.title ?? "Chapter \(chapter.index + 1)",
                    detail: formatClock(Double(chapter.startMs ?? 0) / 1000),
                    current: chapter.index == currentChapter?.index
                )
            }
            onSelect = { index in
                if let chapter = chapters.first(where: { $0.index == index }) {
                    model.controller?.seek(to: Double(chapter.startMs ?? 0) / 1000)
                }
            }
        case .audio:
            rows = model.audioTracks.map { track in
                TVConsoleRow(id: track.id, title: track.displayName, current: track.id == model.selectedAudioId)
            }
            onSelect = { id in model.selectAudio(id) }
        case .subtitles:
            // mpv track ids start at 1, so -1 stands in for "Off".
            rows = [TVConsoleRow(id: -1, title: "Off", current: model.selectedSubtitleId == nil)]
                + model.subtitleTracks.map { track in
                    TVConsoleRow(id: track.id, title: track.displayName, current: track.id == model.selectedSubtitleId)
                }
            onSelect = { id in model.selectSubtitle(id == -1 ? nil : id) }
        }
        return HStack {
            Spacer()
            TVConsoleList(rows: rows, accent: accent.tint) { id in
                onSelect(id)
                self.panel = nil
                interactionTick += 1
            }
            Spacer()
        }
    }

    // MARK: - End overlay

    /// Shown when playback reaches the end: the finished title's colors
    /// linger as drifting threads while up-next appears. No auto-advance
    /// countdown, mirroring the iPad and Android apps.
    private var endOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            ThreeThreads(colors: threads, drifting: true)
                .opacity(0.8)
            VStack(spacing: 20) {
                if let next = nextEpisode {
                    RowLabel(text: "Up next")
                    Button {
                        playNext(next)
                    } label: {
                        ZStack {
                            Color.surface1
                            if let url = thumbURL(for: next) {
                                CachedImage(url: url, contentMode: .fill) { Color.clear }
                            }
                        }
                        .frame(width: 480, height: 270)
                    }
                    .buttonStyle(.card)
                    Text([episodeLabel(next), next.title].compactMap { $0 }.joined(separator: " · "))
                        .font(.titleMedium)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                } else {
                    Button("Play again") {
                        model.replay()
                    }
                    .buttonStyle(TVPillButtonStyle())
                }
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(TVPillButtonStyle())
                .padding(.top, 10)
            }
        }
    }

    // MARK: - Session plumbing

    private func start() async {
        loadError = nil
        guard let client = appEnvironment.client else {
            loadError = "No Loom server configured."
            return
        }
        do {
            let playback = try await client.playback(id: item.id)
            // The 4K AV1 gate: refuse rather than stutter through software
            // decode. Checked against the playback manifest so every entry
            // point (detail, home rows, -autoplay) hits it.
            if let reason = PlaybackGate.blockReason(for: playback.media) {
                loadError = reason
                return
            }
            chapters = playback.media.chapters ?? []
            startSeconds = Double(item.progress?.resumePositionMs ?? 0) / 1000
            playbackURL = client.streamURL(for: playback)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// The scrub thread and end overlay take their color from the poster.
    private func loadThreads() async {
        guard let url = appEnvironment.client?.imageURL(id: item.posterImageId, tag: item.posterImageTag, width: 240) else { return }
        let extracted = await WovenExtractor.threads(for: url)
        withAnimation(.easeInOut(duration: 0.45)) {
            threads = extracted
            if let seed = extracted.first {
                accent = .from(seed: seed)
            }
        }
    }

    /// Loom's Next Up cannot say what follows this specific episode, so the
    /// successor is computed locally from the show's own episode list.
    private func loadNextEpisode() async {
        guard item.kind == "episode", let client = appEnvironment.client,
              let seasonId = item.parentId else { return }
        do {
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
            nextEpisode = nextEpisodeAfter(item.id, in: episodes)
        } catch {
            nextEpisode = nil
        }
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
        guard model.timeSeconds > 0, model.durationSeconds > 0,
              let client = appEnvironment.client else { return }
        // A failed report is dropped, not queued: the TV lives on the Loom
        // LAN, and the next 10-second tick re-reports the fresher position.
        try? await client.reportProgress(
            id: item.id,
            positionMs: Int64(model.timeSeconds * 1000),
            durationMs: Int64(model.durationSeconds * 1000)
        )
    }
}

// MARK: - Console pieces

/// Focus-aware circle for the transport: the play button and the ±10 chips.
struct TVCircleButtonStyle: ButtonStyle {
    var size: CGFloat
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        CircleLabel(configuration: configuration, size: size, prominent: prominent)
    }

    private struct CircleLabel: View {
        @Environment(\.isFocused) private var focused
        let configuration: Configuration
        let size: CGFloat
        let prominent: Bool

        var body: some View {
            configuration.label
                .foregroundStyle(focused ? Color(hexValue: 0x171B26) : Color.ink)
                .frame(width: size, height: size)
                .background(
                    focused ? Color.ink : Color.ink.opacity(prominent ? 0.14 : 0.08),
                    in: Circle()
                )
                .scaleEffect(focused ? 1.08 : 1)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 16, y: 8)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// The progress thread grown up, display-only on TV: seeking happens through
/// the ±10 chips and left/right presses, so the thread never traps focus.
private struct TVScrubThread: View {
    var time: Double
    var duration: Double
    var chapters: [Chapter]
    var accent: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = min(max(time / duration, 0), 1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent.opacity(0.22))
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: width * fraction, height: 4)
                ForEach(chapters, id: \.index) { chapter in
                    let chapterFraction = Double(chapter.startMs ?? 0) / (duration * 1000)
                    if chapterFraction > 0, chapterFraction < 1 {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.ink.opacity(0.45))
                            .frame(width: 2, height: 13)
                            .offset(x: width * chapterFraction)
                    }
                }
                Circle()
                    .fill(accent.opacity(0.25))
                    .frame(width: 32, height: 32)
                    .offset(x: width * fraction - 16)
                Circle()
                    .fill(accent)
                    .frame(width: 18, height: 18)
                    .offset(x: width * fraction - 9)
            }
            .frame(height: 32, alignment: .center)
        }
        .frame(height: 32)
    }
}

struct TVConsoleRow: Identifiable {
    let id: Int
    let title: String
    var detail: String? = nil
    var current = false
}

/// The picker behind the console pills: a focus-navigable list with the
/// current row accented, opened scrolled to it.
private struct TVConsoleList: View {
    var rows: [TVConsoleRow]
    var accent: Color
    var onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(rows) { row in
                        Button {
                            onSelect(row.id)
                        } label: {
                            HStack(spacing: 20) {
                                Text(row.title)
                                    .font(.labelLarge)
                                    .foregroundStyle(row.current ? accent : Color.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 20)
                                if let detail = row.detail {
                                    Text(detail)
                                        .font(.labelMedium.monospacedDigit())
                                        .foregroundStyle(row.current ? accent.opacity(0.8) : Color.muted)
                                }
                            }
                        }
                        .buttonStyle(TVRowButtonStyle())
                        .id(row.id)
                    }
                }
                .padding(16)
            }
            .frame(width: 640)
            .frame(maxHeight: 620)
            .background(consoleFill, in: RoundedRectangle(cornerRadius: 32))
            .overlay(RoundedRectangle(cornerRadius: 32).stroke(chipStroke, lineWidth: 1))
            .onAppear {
                if let current = rows.first(where: { $0.current }) {
                    proxy.scrollTo(current.id, anchor: .center)
                }
            }
        }
    }
}
