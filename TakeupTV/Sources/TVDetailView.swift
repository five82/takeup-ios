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
    /// What to play and whether to ignore the resume point. A struct rather
    /// than a side flag: the cover's content closure can capture stale view
    /// state, but the presented item always arrives fresh.
    private struct PlaybackRequest: Identifiable {
        let item: Item
        var fromStart = false
        var id: Int64 { item.id }
    }

    @State private var playbackItem: PlaybackRequest?
    @State private var accent = WovenAccent.neutral
    @State private var threads: [RGB] = []
    /// The first content frame lands already dressed: rendering waits for the
    /// woven threads or a 300ms grace, whichever comes first.
    @State private var dressed = false
    /// The show's name for the episode eyebrow, resolved via the season.
    @State private var seriesName: String?
    @FocusState private var playFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GauzeBackground(url: detailArtURL(width: 240), seed: threads.first)
                if let item, dressed {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            head(for: item, size: proxy.size)
                            belowBand(for: item)
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
        }
        // The screen owns its overscan margins (TVLayout); the system inset
        // would gutter the bias-cut head off the screen edges. Ignoring it on
        // the GeometryReader makes proxy.size the full screen, so the head is
        // cut to the true edge-to-edge width instead of the inset width.
        .ignoresSafeArea()
        .background(Color.stage)
        .animation(.easeInOut(duration: 0.45), value: accent)
        .defaultFocus($playFocused, true)
        .navigationDestination(for: Item.self) { child in
            TVDetailView(itemId: child.id, fallbackTitle: child.title)
        }
        .navigationDestination(for: TVPersonSearch.self) { person in
            TVSearchView(initialQuery: person.name)
        }
        .fullScreenCover(item: $playbackItem, onDismiss: { Task { await load() } }) { request in
            TVPlayerScreen(item: request.item, fromStart: request.fromStart)
        }
        .task(id: itemId) { await load() }
    }

    // MARK: - Head

    /// The band fraction per kind: movies take the working column with its
    /// tagline and gate lines; shows and episodes wear the short band —
    /// shows so the episode strip is fully on screen at rest, episodes
    /// because their columns are lean and the screencap is a composed film
    /// frame that deserves the widest reveal.
    private func bandFraction(for item: Item) -> CGFloat {
        item.kind == "movie" ? TVLayout.movieBand : TVLayout.showBand
    }

    private func head(for item: Item, size: CGSize) -> some View {
        let band = size.height * bandFraction(for: item)
        return SelvedgeBackdrop(
            url: detailArtURL(width: 1440),
            width: size.width,
            height: band,
            seam: TVLayout.detailSeam
        ) {
            column(for: item, width: size.width)
                .padding(.leading, TVLayout.sideMargin)
                // Centered on the band's height, like the home hero: the
                // column's slack splits above and below instead of pooling
                // under the chapters line. The top reserve keeps the tallest
                // columns (a gated title's two pill rows and reason) clear
                // of the screen edge; any spill goes harmlessly downward.
                .frame(height: band - 44, alignment: .leading)
                .padding(.top, 44)
        }
        // The full-width section keeps the controls reachable: an up-press
        // from a card right of the column would otherwise find no candidate
        // (focus search wants horizontal overlap) and go nowhere.
        .focusSection()
    }

    /// The identity column on the seam's open ground: everything that used to
    /// stack under the head, one press closer to the couch.
    private func column(for item: Item, width: CGFloat) -> some View {
        let columnWidth = width * TVLayout.detailSeam - TVLayout.sideMargin - 44
        return VStack(alignment: .leading, spacing: 0) {
            if item.kind == "episode" {
                episodeIdentity(for: item, columnWidth: columnWidth)
                Text(item.title)
                    .font(.displaySmall)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .padding(.top, 10)
            } else {
                identity(for: item, columnWidth: columnWidth)
            }
            metaLine(for: item)
                .padding(.top, 20)
            if item.kind != "episode", let tagline = item.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.bodyLarge)
                    .italic()
                    .foregroundStyle(Color.ink.opacity(0.92))
                    .lineLimit(2)
                    // Claims its two lines even when the band runs tight, so
                    // the voice line never ellipsizes against the gate text.
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            if item.isPlayable {
                playControls(for: item)
                    .padding(.top, 26)
                if let reason = blockReason(for: item) {
                    statusLine(icon: "tv.slash", text: reason)
                }
                if let fraction = progressFraction(item) {
                    ThreadProgress(fraction: fraction, color: accent.tint)
                        .frame(width: columnWidth * 0.75)
                        .padding(.top, 18)
                }
                badgeStrip(for: item)
                    .padding(.top, 22)
                if let chapters = item.media?.chapters, chapters.count > 1 {
                    Text("\(chapters.count) chapters")
                        .font(.labelMedium)
                        .foregroundStyle(Color.muted)
                        .padding(.top, 12)
                }
            } else if item.kind == "show" {
                showControls(for: item)
                    .padding(.top, 24)
            }
            // Shows carry no overview — the column beside the art is too
            // tight for prose, and the screen belongs to the episodes.
            // Movies and episodes tell the story below the band instead.
        }
        .frame(width: columnWidth, alignment: .leading)
    }

    @ViewBuilder
    private func identity(for item: Item, columnWidth: CGFloat) -> some View {
        let logoURL = appEnvironment.client?.imageURL(id: item.logoImageId, tag: item.logoImageTag, width: 480)
        if let logoURL {
            LogoBox(url: logoURL, width: columnWidth, height: logoBoxHeight)
        } else {
            Text(item.title)
                .font(.displayMedium)
                .foregroundStyle(Color.ink)
                .lineLimit(2)
        }
    }

    /// The series voice above the episode's name: the show's logo when the
    /// episode inherits one, at a leaner lane than a show page's identity —
    /// the episode title owns this screen. The "S1 E1" eyebrow sits between
    /// them, iPad-style; without a logo the eyebrow speaks the series name.
    @ViewBuilder
    private func episodeIdentity(for item: Item, columnWidth: CGFloat) -> some View {
        let logoURL = appEnvironment.client?.imageURL(id: item.logoImageId, tag: item.logoImageTag, width: 480)
        if let logoURL {
            // A leaner box than the show page's: the episode title owns this
            // screen, the series logo only introduces it.
            LogoBox(url: logoURL, width: columnWidth, height: 130)
            if let label = episodeLabel(item) {
                RowLabel(text: label, color: accent.tint)
                    .padding(.top, 16)
            }
        } else if let eyebrow = episodeEyebrow(item) {
            RowLabel(text: eyebrow, color: accent.tint)
        }
    }

    /// "BREAKING BAD · S1 E1" — the series voice above the episode's name.
    private func episodeEyebrow(_ item: Item) -> String? {
        var parts: [String] = []
        if let series = item.seriesTitle ?? seriesName, !series.isEmpty { parts.append(series) }
        if let label = episodeLabel(item) { parts.append(label) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Below the band

    @ViewBuilder
    private func belowBand(for item: Item) -> some View {
        if item.kind == "show" {
            seasonSection()
        } else {
            overviewBlock(for: item)
        }
        billingGrid(for: item)
    }

    /// The story at reading size, on the open ground under the column. The
    /// band holds the working controls; the prose gets the room it needs.
    @ViewBuilder
    private func overviewBlock(for item: Item) -> some View {
        if let overview = item.overview, !overview.isEmpty {
            Text(overview)
                .font(.bodyLarge)
                .foregroundStyle(Color.ink.opacity(0.92))
                .lineSpacing(5)
                .frame(maxWidth: 1240, alignment: .leading)
                .padding(.top, 30)
        }
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
            .font(.bodyLarge)
            .foregroundStyle(Color.ink)
    }

    // MARK: - Play controls

    /// The 4K AV1 verdict for this title on this hardware; nil when playable.
    private func blockReason(for item: Item) -> String? {
        PlaybackGate.blockReason(for: item.media)
    }

    private func playControls(for item: Item) -> some View {
        let blocked = blockReason(for: item) != nil
        // A wrapping flow, not an HStack: pills keep their natural size and a
        // long Resume label pushes the toggle to a second row instead of
        // compressing labels or spilling across the seam onto the art.
        return TVFlowLayout {
            Button {
                playbackItem = PlaybackRequest(item: item)
            } label: {
                Label(playLabel(for: item), systemImage: "play.fill")
            }
            .buttonStyle(TVPillButtonStyle(fill: accent.fill, onFill: accent.onFill, idleFill: accent.fill.opacity(0.28)))
            .focused($playFocused)
            .disabled(blocked)
            .opacity(blocked ? 0.45 : 1)

            // From the couch, "start over" deserves its own button; the iPad
            // reaches the same result through scrubbing.
            if (item.progress?.resumePositionMs ?? 0) > 0 {
                Button {
                    playbackItem = PlaybackRequest(item: item, fromStart: true)
                } label: {
                    Label("Restart", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(TVPillButtonStyle())
                .disabled(blocked)
                .opacity(blocked ? 0.45 : 1)
            }

            // Default focus must land on a focusable control: aiming it at
            // the disabled Play of a gated title leaves the toggle wearing a
            // stale focus appearance.
            if blocked {
                watchedToggle(for: item)
                    .focused($playFocused)
            } else {
                watchedToggle(for: item)
            }
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
        return TVFlowLayout {
            Button {
                if let next { playbackItem = PlaybackRequest(item: next) }
            } label: {
                Label(showPlayLabel(next: next), systemImage: "play.fill")
            }
            .buttonStyle(TVPillButtonStyle(fill: accent.fill, onFill: accent.onFill, idleFill: accent.fill.opacity(0.28)))
            .focused($playFocused)
            .disabled(next == nil)

            // Same trap as the gated Play: default focus needs a focusable
            // target when everything is watched and Play is disabled.
            if next == nil {
                watchedToggle(for: item)
                    .focused($playFocused)
            } else {
                watchedToggle(for: item)
            }
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
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: TypeScale.bodyMedium))
            Text(text)
                .font(.bodyMedium)
                // The gate's reason must never ellipsize: it wraps at its
                // full length even when the band's height runs tight.
                .fixedSize(horizontal: false, vertical: true)
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
            .tvFocusHalo(accent.tint)

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

    /// Loom stores no people photos, so the cast is billing, not headshots:
    /// columns of content-sized type cards, the way a one-sheet credits its
    /// cast. The director leads with the accent role label.
    ///
    /// A non-lazy grid, deliberately: on show pages the whole grid sits below
    /// the fold, and a LazyVGrid down there never instantiates its cards — the
    /// focus engine sees an empty section and a down-press from the episode
    /// strip goes nowhere. The cast is small enough to build eagerly.
    @ViewBuilder
    private func billingGrid(for item: Item) -> some View {
        if let credits = item.credits, !credits.isEmpty {
            let ordered = credits.sorted { a, b in
                (a.role == "Director" ? 0 : 1) < (b.role == "Director" ? 0 : 1)
            }
            let columns = 4
            VStack(alignment: .leading, spacing: 8) {
                RowLabel(text: "Cast")
                VStack(alignment: .leading, spacing: 30) {
                    ForEach(Array(stride(from: 0, to: ordered.count, by: columns)), id: \.self) { start in
                        let row = ordered[start..<min(start + columns, ordered.count)]
                        HStack(alignment: .top, spacing: 44) {
                            ForEach(row, id: \.self) { credit in
                                TVBillingCard(credit: credit, accent: accent.tint)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            // Fillers keep a short last row's columns the same
                            // width as the full rows above, so names align.
                            ForEach(0..<(columns - row.count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                            }
                        }
                    }
                }
                .padding(.vertical, 18)
                .focusSection()
            }
            .padding(.top, 34)
        }
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
            } else if loaded.kind == "episode", let seasonId = loaded.parentId {
                // The item endpoint omits series_title; the eyebrow needs the
                // show's name, two parent hops away (episode → season → show).
                if loaded.seriesTitle == nil,
                   let season = try? await client.item(id: seasonId),
                   let showId = season.parentId,
                   let show = try? await client.item(id: showId) {
                    seriesName = show.title
                }
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
