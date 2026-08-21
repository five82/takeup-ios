import SwiftUI

/// Navigation value for a cast card: pushes a search for the person.
struct TVPersonSearch: Hashable {
    let name: String
}

/// Detail for any item kind, dressed in accents woven from its own artwork.
/// The whole screen is one click from playback: Play takes default focus.
/// Episodes are a focusable horizontal strip under the season chips — the
/// shape a focus engine handles best.
struct TVDetailView: View {
    let itemId: Int64
    let fallbackTitle: String

    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var item: Item?
    @State private var seasons: [Item] = []
    @State private var selectedSeasonId: Int64?
    @State private var episodes: [Item] = []
    @State private var loadError: String?
    @State private var playbackItem: Item?
    @State private var accent = WovenAccent.neutral
    @State private var threads: [RGB] = []
    /// The first content frame lands already dressed: rendering waits for the
    /// woven threads or a 300ms grace, whichever comes first.
    @State private var dressed = false
    @State private var logoAspect: Double?
    @State private var castExpanded = false
    @FocusState private var playFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GauzeBackground(url: detailArtURL(width: 240), seed: threads.first)
                if let item, dressed {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            head(for: item, width: proxy.size.width)
                            detailBody(for: item)
                                .padding(.horizontal, TVLayout.sideMargin)
                        }
                        .padding(.bottom, TVLayout.verticalMargin)
                        .frame(width: proxy.size.width, alignment: .leading)
                    }
                } else if let loadError {
                    ErrorState(message: loadError) { Task { await load() } }
                } else {
                    LoadingState()
                }
            }
            // The screen owns its overscan margins (TVLayout); the system
            // inset would gutter the bias-cut head off the screen edges.
            .ignoresSafeArea()
        }
        .background(Color.stage)
        .animation(.easeInOut(duration: 0.45), value: accent)
        .defaultFocus($playFocused, true)
        .navigationDestination(for: Item.self) { child in
            TVDetailView(itemId: child.id, fallbackTitle: child.title)
        }
        .navigationDestination(for: TVPersonSearch.self) { person in
            TVSearchView(initialQuery: person.name)
        }
        .fullScreenCover(item: $playbackItem, onDismiss: { Task { await load() } }) { playable in
            TVPlayerScreen(item: playable)
        }
        .task(id: itemId) { await load() }
    }

    // MARK: - Head

    private func head(for item: Item, width: CGFloat) -> some View {
        let logoURL = appEnvironment.client?.imageURL(id: item.logoImageId, tag: item.logoImageTag, width: 480)
        let lane = logoLaneHeight(aspect: logoAspect) * 1.5
        let solidLeft: CGFloat = logoURL != nil ? lane + 34 : 170
        return BiasCutBackdrop(url: detailArtURL(width: 1440), width: width, solidLeft: solidLeft) {
            Group {
                if let logoURL {
                    CachedImage(url: logoURL, contentMode: .fit, onLoad: { image in
                        let aspect = Double(image.size.width / max(image.size.height, 1))
                        if logoAspect != aspect {
                            withAnimation(.spring) { logoAspect = aspect }
                        }
                    }) { Color.clear }
                        .frame(width: min(CGFloat(logoAspect ?? 3) * lane, width * 0.4), height: lane)
                } else {
                    Text(item.title)
                        .font(.displayMedium)
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, TVLayout.sideMargin)
            .padding(.bottom, 18)
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func detailBody(for item: Item) -> some View {
        if item.kind == "episode", let label = episodeLabel(item) {
            RowLabel(text: label, color: accent.tint)
                .padding(.top, 20)
            Text(item.title)
                .font(.headlineMedium)
                .foregroundStyle(Color.ink)
                .padding(.top, 4)
        }
        metaLine(for: item)
            .padding(.top, item.kind == "episode" ? 12 : 20)
        if let tagline = item.tagline, !tagline.isEmpty {
            Text(tagline)
                .font(.bodyMedium)
                .italic()
                .foregroundStyle(Color.ink)
                .padding(.top, 8)
        }
        if item.isPlayable {
            playControls(for: item)
                .padding(.top, 22)
            if let reason = blockReason(for: item) {
                statusLine(icon: "tv.slash", text: reason)
            }
            if let fraction = progressFraction(item) {
                ThreadProgress(fraction: fraction, color: accent.tint)
                    .frame(maxWidth: 540)
                    .padding(.top, 16)
            }
            badgeStrip(for: item)
                .padding(.top, 22)
        } else if item.kind == "show" {
            showControls(for: item)
                .padding(.top, 22)
        }
        if let overview = item.overview, !overview.isEmpty {
            Text(overview)
                .font(.bodyLarge)
                .foregroundStyle(Color.ink.opacity(0.92))
                .lineLimit(item.kind == "show" ? 4 : nil)
                .frame(maxWidth: 1100, alignment: .leading)
                .padding(.top, 26)
        }
        if let chapters = item.media?.chapters, chapters.count > 1 {
            Text("\(chapters.count) chapters")
                .font(.labelSmall)
                .foregroundStyle(Color.muted)
                .padding(.top, 14)
        }
        if item.kind == "show" {
            seasonSection()
        }
        creditsSection(for: item)
    }

    private func metaLine(for item: Item) -> some View {
        var parts: [String] = []
        if let year = item.year, year > 0 { parts.append(String(year)) }
        if let duration = item.durationMs, duration > 0 { parts.append(formatRuntime(duration)) }
        if let rating = item.contentRating { parts.append(rating) }
        if let vote = item.voteAverage, vote > 0 { parts.append("★ " + String(format: "%.1f", vote)) }
        if item.kind == "show" {
            if let seasonCount = item.totalSeasons, seasonCount > 0 {
                parts.append(seasonCount == 1 ? "1 season" : "\(seasonCount) seasons")
            }
            if let unwatched = item.unwatchedCount, unwatched > 0 {
                parts.append("\(unwatched) unwatched")
            }
        }
        for genre in (item.genres ?? []).prefix(3) { parts.append(genre.name) }
        return Text(parts.joined(separator: " · "))
            .font(.bodySmall)
            .foregroundStyle(Color.ink)
    }

    // MARK: - Play controls

    /// The 4K AV1 verdict for this title on this hardware; nil when playable.
    private func blockReason(for item: Item) -> String? {
        PlaybackGate.blockReason(for: item.media)
    }

    private func playControls(for item: Item) -> some View {
        let blocked = blockReason(for: item) != nil
        return HStack(spacing: 16) {
            Button {
                playbackItem = item
            } label: {
                Label(playLabel(for: item), systemImage: "play.fill")
            }
            .buttonStyle(TVPillButtonStyle(fill: accent.fill, onFill: accent.onFill, idleFill: accent.fill.opacity(0.28)))
            .focused($playFocused)
            .disabled(blocked)
            .opacity(blocked ? 0.45 : 1)

            watchedToggle(for: item)
        }
    }

    private func playLabel(for item: Item) -> String {
        guard let progress = item.progress else { return "Play" }
        if progress.played ?? false, (progress.resumePositionMs ?? 0) == 0 { return "Play again" }
        if let remaining = remainingLabel(item) { return "Resume · \(remaining)" }
        return "Play"
    }

    private func showControls(for item: Item) -> some View {
        let next = episodes.first { !($0.progress?.played ?? false) }
        return HStack(spacing: 16) {
            Button {
                if let next { playbackItem = next }
            } label: {
                Label(showPlayLabel(next: next), systemImage: "play.fill")
            }
            .buttonStyle(TVPillButtonStyle(fill: accent.fill, onFill: accent.onFill, idleFill: accent.fill.opacity(0.28)))
            .focused($playFocused)
            .disabled(next == nil)

            watchedToggle(for: item)
        }
    }

    private func showPlayLabel(next: Item?) -> String {
        guard let next else { return "Play" }
        var parts: [String] = [(next.progress?.resumePositionMs ?? 0) > 0 ? "Resume" : "Play"]
        if let label = episodeLabel(next) { parts.append(label) }
        parts.append(next.title)
        return parts.joined(separator: " · ")
    }

    /// Marks the whole item watched or unwatched; for shows this cascades on
    /// the server. A pill beside Play, since tvOS has no toolbar menu.
    private func watchedToggle(for item: Item) -> some View {
        let played = item.progress?.played ?? false
        let allWatched = item.isPlayable ? played : (item.unwatchedCount ?? 0) == 0 && (item.episodeCount ?? 0) > 0
        let watched = item.isPlayable ? played : allWatched
        return Button {
            Task {
                guard let client = appEnvironment.client else { return }
                try? await client.setPlayed(id: item.id, !watched)
                await load()
            }
        } label: {
            Label(
                watched ? "Watched" : "Mark Watched",
                systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle"
            )
        }
        .buttonStyle(TVPillButtonStyle())
    }

    private func statusLine(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: TypeScale.bodySmall))
            Text(text)
                .font(.bodySmall)
        }
        .foregroundStyle(Color.muted)
        .padding(.top, 14)
    }

    // MARK: - Badges

    private func badgeStrip(for item: Item) -> some View {
        var badges: [String] = []
        let streams = item.media?.streams ?? []
        if let video = streams.first(where: { $0.kind == "video" }) {
            if let resolution = resolutionBadge(video.resolution) {
                badges.append(resolution)
            }
            if let range = video.dynamicRange, !range.isEmpty, range.lowercased() != "sdr" {
                badges.append(range)
            }
            if let codec = video.codec {
                badges.append(displayCodec(codec))
            }
        }
        if let audio = streams.first(where: { $0.kind == "audio" }) {
            var label = displayCodec(audio.codec ?? "")
            if let channels = audio.channels {
                label += " " + channelLabel(channels)
            }
            if !label.trimmingCharacters(in: .whitespaces).isEmpty { badges.append(label) }
        }
        if let size = item.media?.size, size > 0 {
            badges.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return HStack(spacing: 10) {
            ForEach(badges, id: \.self) { badge in
                TechBadge(text: badge)
            }
        }
    }

    private func displayCodec(_ codec: String) -> String {
        switch codec.lowercased() {
        case "hevc", "h265": "HEVC"
        case "h264", "avc": "H.264"
        case "av1": "AV1"
        case "opus": "Opus"
        case "aac": "AAC"
        case "ac3": "DD"
        case "eac3": "DD+"
        case "truehd": "TrueHD"
        case "dts": "DTS"
        case "flac": "FLAC"
        default: codec.uppercased()
        }
    }

    private func channelLabel(_ channels: Int) -> String {
        switch channels {
        case 1: "1.0"
        case 2: "2.0"
        case 6: "5.1"
        case 8: "7.1"
        default: "\(channels)ch"
        }
    }

    // MARK: - Seasons and episodes

    @ViewBuilder
    private func seasonSection() -> some View {
        if !seasons.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(seasons) { season in
                        seasonChip(season)
                    }
                }
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()
            .padding(.top, 26)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: TVLayout.cardSpacing) {
                    ForEach(episodes) { episode in
                        episodeCell(episode)
                    }
                }
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
        }
    }

    private func seasonChip(_ season: Item) -> some View {
        let selected = season.id == selectedSeasonId
        let left = season.unwatchedCount ?? 0
        return Button {
            selectedSeasonId = season.id
            Task { await loadEpisodes(of: season.id) }
        } label: {
            HStack(spacing: 10) {
                Text(season.title)
                if left > 0 {
                    // Inherits the style's focus-flipped color, just quieter.
                    Text("\(left) left")
                        .font(.labelSmall)
                        .opacity(0.75)
                }
            }
        }
        .buttonStyle(TVPillButtonStyle(
            fill: accent.tint,
            onFill: accent.onFill,
            idleFill: selected ? accent.tint.opacity(0.24) : Color.ink.opacity(0.06)
        ))
    }

    /// An episode card pushes the episode's own page — the full overview and
    /// its watched toggle live there, one click from its Play.
    private func episodeCell(_ episode: Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: episode) {
                ZStack {
                    Color.surface1
                    if let url = appEnvironment.client?.imageURL(id: episode.thumbImageId, tag: episode.thumbImageTag, width: 480) {
                        CachedImage(url: url, contentMode: .fill)
                    } else {
                        MissingArt(title: episode.title, tint: accent.tint)
                    }
                }
                .frame(width: TVLayout.thumbWidth, height: TVLayout.thumbWidth * 9 / 16)
                .overlay(alignment: .bottom) {
                    if let fraction = progressFraction(episode) {
                        ThreadProgress(fraction: fraction, color: accent.tint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
            }
            .buttonStyle(.card)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(episodeCellTitle(episode))
                        .font(.titleSmall)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    if episode.progress?.played ?? false {
                        Image(systemName: "checkmark")
                            .font(.system(size: TypeScale.labelSmall, weight: .semibold))
                            .foregroundStyle(accent.tint)
                    }
                }
                if let context = episodeContext(episode) {
                    Text(context)
                        .font(.labelSmall)
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 4)
        }
        .frame(width: TVLayout.thumbWidth, alignment: .leading)
    }

    private func episodeCellTitle(_ episode: Item) -> String {
        if let number = episode.episodeNumber, number > 0 {
            return "\(number) · \(episode.title)"
        }
        return episode.title
    }

    private func episodeContext(_ episode: Item) -> String? {
        var parts: [String] = []
        if let duration = episode.durationMs, duration > 0 { parts.append(formatRuntime(duration)) }
        if let remaining = remainingLabel(episode) { parts.append(remaining) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Credits

    /// Loom stores no people photos, so the credits are billing, not
    /// headshots: frosted ink cards that let the gauze show through.
    @ViewBuilder
    private func creditsSection(for item: Item) -> some View {
        if let credits = item.credits, !credits.isEmpty {
            let ordered = credits.sorted { a, b in
                (a.role == "Director" ? 0 : 1) < (b.role == "Director" ? 0 : 1)
            }
            let visible = castExpanded ? ordered : Array(ordered.prefix(6))
            VStack(alignment: .leading, spacing: 12) {
                RowLabel(text: "Cast")
                    .padding(.bottom, 4)
                ForEach(visible, id: \.self) { credit in
                    creditCard(credit)
                }
                if !castExpanded && ordered.count > 6 {
                    Button {
                        castExpanded = true
                    } label: {
                        Text("All \(ordered.count) cast members")
                            .font(.titleSmall)
                            .foregroundStyle(Color.muted)
                    }
                    .buttonStyle(TVPillButtonStyle())
                }
            }
            .frame(maxWidth: 900, alignment: .leading)
            .padding(.top, 36)
        }
    }

    /// Selecting a card searches the person, matching the Android bill.
    private func creditCard(_ credit: Credit) -> some View {
        NavigationLink(value: TVPersonSearch(name: credit.name)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(credit.name)
                    .font(.system(size: TypeScale.titleSmall + 2))
                    .foregroundStyle(Color.ink)
                Text(credit.character ?? credit.role)
                    .font(.system(size: TypeScale.labelSmall, weight: .medium))
                    .foregroundStyle(Color.muted)
            }
        }
        .buttonStyle(TVRowButtonStyle())
    }

    // MARK: - Data

    private func detailArtURL(width: Int) -> URL? {
        guard let item, let client = appEnvironment.client else { return nil }
        return tvDetailArtURL(for: item, client: client, width: width)
    }

    private func load() async {
        guard let client = appEnvironment.client else { return }
        loadError = nil
        do {
            let loaded = try await client.item(id: itemId)
            item = loaded
            if loaded.kind == "show" {
                let children = try await client.children(of: itemId).items
                seasons = children.filter { $0.kind == "season" }
                // Land on the season holding the next unwatched episode;
                // specials never stand in front of a pilot. Loom omits zero
                // fields, so season 0 arrives with no season number at all.
                let regular = seasons.filter { ($0.seasonNumber ?? 0) != 0 }
                let target = regular.first { ($0.unwatchedCount ?? 0) > 0 } ?? regular.first ?? seasons.first
                if selectedSeasonId == nil || !seasons.contains(where: { $0.id == selectedSeasonId }) {
                    selectedSeasonId = target?.id
                }
                if let selectedSeasonId {
                    await loadEpisodes(of: selectedSeasonId)
                }
            } else if loaded.kind == "season" {
                episodes = try await client.children(of: itemId).items
            }
            await resolveThreads()
        } catch {
            loadError = error.localizedDescription
        }
        dressed = true
    }

    private func loadEpisodes(of seasonId: Int64) async {
        guard let client = appEnvironment.client else { return }
        episodes = (try? await client.children(of: seasonId).items) ?? []
    }

    private func resolveThreads() async {
        guard let url = detailArtURL(width: 240) else { return }
        // The 300ms grace: dress the first frame if the threads are quick,
        // show content anyway if they are not.
        let extraction = Task { await WovenExtractor.threads(for: url) }
        let grace = Task { try? await Task.sleep(for: .milliseconds(300)) }
        if let cached = WovenExtractor.cachedThreads(for: url) {
            apply(threads: cached)
            grace.cancel()
            return
        }
        _ = await grace.value
        dressed = true
        apply(threads: await extraction.value)
    }

    private func apply(threads: [RGB]) {
        self.threads = threads
        if let seed = threads.first {
            accent = .from(seed: seed)
        }
    }
}
