import SwiftUI
import UIKit

/// Navigation value for tapping a cast card: pushes a search for the person.
struct PersonSearch: Hashable {
    let name: String
}

/// What a detail reload keys on: a different item, or a changed verdict about
/// the network — each means the screen is drawn from a different source.
private struct DetailLoad: Equatable {
    let itemId: Int64
    let offline: Bool
}

/// Episodes show their own screencap; everything else leads with the
/// backdrop (the poster only as a last resort). Shared with RootView's
/// `-artwork` debug push, which has no detail screen to ask.
func detailArtURL(for item: Item, client: LoomClient, width: Int) -> URL? {
    if item.kind == "episode",
       let url = client.imageURL(id: item.thumbImageId, tag: item.thumbImageTag, width: width) {
        return url
    }
    return client.imageURL(id: item.backdropImageId, tag: item.backdropImageTag, width: width)
        ?? client.imageURL(id: item.thumbImageId, tag: item.thumbImageTag, width: width)
        ?? client.imageURL(id: item.posterImageId, tag: item.posterImageTag, width: width)
}

/// Detail for any item kind, dressed in accents woven from its own artwork:
/// gauze from the detail art, a bias-cut head with the logo lane, and a body
/// that goes two-pane in wide panes (story left, people/season right).
struct ItemDetailView: View {
    let itemId: Int64
    let fallbackTitle: String

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(DownloadManager.self) private var downloads
    @Environment(NetworkPolicy.self) private var network
    @State private var item: Item?
    @State private var seasons: [Item] = []
    @State private var selectedSeasonId: Int64?
    @State private var episodes: [Item] = []
    @State private var loadError: String?
    @State private var offline = false
    /// Season id -> episodes on this device still unwatched. Offline a
    /// season's own tally counts episodes that are not here at all.
    @State private var offlineUnwatched: [Int64: Int] = [:]
    @State private var playbackItem: Item?
    @State private var accent = WovenAccent.neutral
    @State private var threads: [RGB] = []
    /// The first content frame lands already dressed: rendering waits for the
    /// woven threads or a 300ms grace, whichever comes first.
    @State private var dressed = false
    @State private var castExpanded = false
    @State private var artworkPick: ArtworkPick?
    @State private var removalEntry: DownloadEntry?
    @State private var showRemovalConfirmation = false
    @Environment(\.paneWidth) private var paneWidth

    var body: some View {
        ZStack {
            GauzeBackground(url: detailArtURL(width: 240), seed: threads.first)
            if let item, dressed, paneWidth > 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        head(for: item, width: paneWidth)
                        if paneWidth >= 900 {
                            twoPaneBody(for: item, width: paneWidth)
                        } else {
                            singleColumnBody(for: item)
                        }
                    }
                    .padding(.bottom, 32)
                    .frame(width: paneWidth, alignment: .leading)
                }
                // The head's backdrop runs seamlessly to the screen's top
                // edge, matching the Android app; the art's own wash keeps
                // the status bar and back button legible, so the system's
                // grey edge haze must stay out of it.
                .ignoresSafeArea(edges: .top)
                .scrollEdgeEffectHidden(true, for: .top)
            } else if offline {
                // Nothing downloaded and no Loom: there is no version of this
                // title to show, so say why rather than blame the server.
                OfflineNotice(
                    reason: network.reason + " This title is not downloaded to this device.",
                    onRetry: { network.recheck(); Task { await load(force: true) } }
                )
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 24)
            } else if let loadError {
                ErrorState(message: loadError) { Task { await load() } }
            } else {
                LoadingState()
            }
        }
        .paneConstrained()
        .background(Color.stage)
        .animation(.easeInOut(duration: 0.45), value: accent)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Item.self) { child in
            ItemDetailView(itemId: child.id, fallbackTitle: child.title)
        }
        .navigationDestination(for: PersonSearch.self) { person in
            SearchView(initialQuery: person.name)
        }
        .navigationDestination(for: ArtworkPick.self) { pick in
            ArtworkView(pick: pick)
        }
        // The menu entry pushes through this binding: a NavigationLink
        // inside a Menu does not reliably fire.
        .navigationDestination(item: $artworkPick) { pick in
            ArtworkView(pick: pick)
        }
        .fullScreenCover(item: $playbackItem, onDismiss: { Task { await load() } }) { playable in
            PlayerScreen(item: playable)
        }
        .alert("Remove \(removalEntry?.item.title ?? "download")?", isPresented: $showRemovalConfirmation) {
            Button("Remove", role: .destructive) {
                if let removalEntry { downloads.remove(removalEntry.item.id) }
                removalEntry = nil
            }
            Button("Keep", role: .cancel) { removalEntry = nil }
        } message: {
            if let removalEntry {
                Text("Remove \(ByteCountFormatter.string(fromByteCount: removalEntry.size, countStyle: .file)) from this iPad? It will no longer play offline.")
            }
        }
        .toolbar {
            if let item {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        // Artwork above the watched toggle, matching the
                        // Android app's menu order.
                        // Episodes inherit their show's artwork; no picker.
                        // The picker is a Loom browser and a Loom write, so
                        // offline there is nothing behind it.
                        if item.kind != "episode", !offline {
                            Button {
                                artworkPick = ArtworkPick(
                                    itemId: item.id, title: item.title,
                                    ambienceURL: detailArtURL(width: 240)
                                )
                            } label: {
                                Label("Artwork", systemImage: "photo.on.rectangle.angled")
                            }
                        }
                        watchedToggle(for: item)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        // Keyed on the verdict as well as the item: walking back onto the LAN
        // redraws this screen from Loom instead of from the snapshot, while a
        // probe merely settling home-versus-remote leaves a load in flight
        // alone.
        .task(id: DetailLoad(itemId: itemId, offline: network.reach == .offline)) { await load() }
        // Refresh on the trip back from a pushed screen — the artwork picker
        // changes image tags, and tags drive every artwork URL. The initial
        // load stays with .task (item is still nil on first appearance).
        .onAppear {
            guard item != nil else { return }
            Task { await load() }
        }
    }

    // MARK: - Head

    private func head(for item: Item, width: CGFloat) -> some View {
        let logoURL = offline
            ? downloads.artworkURL(for: item.id, kind: .logo)
            : appEnvironment.client?.imageURL(id: item.logoImageId, tag: item.logoImageTag, width: 480)
        let solidLeft: CGFloat = logoURL != nil ? logoBoxHeight + 22 : 116
        return BiasCutBackdrop(url: detailArtURL(width: 960), width: width, solidLeft: solidLeft) {
            Group {
                if let logoURL {
                    LogoBox(url: logoURL, width: width * 0.5, height: logoBoxHeight)
                } else {
                    Text(item.title)
                        .font(.displayMedium)
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Body layouts

    @ViewBuilder
    private func singleColumnBody(for item: Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            storyColumn(for: item)
            if item.kind == "show" {
                seasonSection(width: paneWidth - 40)
            }
            creditsSection(for: item)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func twoPaneBody(for item: Item, width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 0) {
                storyColumn(for: item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                if item.kind == "show" {
                    seasonSection(width: width * 0.42)
                    creditsSection(for: item)
                } else {
                    creditsPane(for: item)
                }
            }
            .frame(width: width * 0.42, alignment: .leading)
        }
        .padding(.horizontal, 20)
    }

    /// Meta, tagline, play controls, badges, overview — the left-hand story.
    @ViewBuilder
    private func storyColumn(for item: Item) -> some View {
        if item.kind == "episode", let label = episodeLabel(item) {
            Text(label)
                .font(.labelMedium)
                .tracking(12 * 0.14)
                .foregroundStyle(accent.tint)
                .padding(.top, 14)
            Text(item.title)
                .font(.headlineMedium)
                .foregroundStyle(Color.ink)
                .padding(.top, 2)
        }
        metaLine(for: item)
            .padding(.top, item.kind == "episode" ? 8 : 14)
        if let tagline = item.tagline, !tagline.isEmpty {
            Text(tagline)
                .font(.bodyMedium)
                .italic()
                .foregroundStyle(Color.ink)
                .padding(.top, 6)
        }
        if item.isPlayable {
            playControls(for: item)
                .padding(.top, 14)
            if let fraction = progressFraction(item) {
                ThreadProgress(fraction: fraction, color: accent.tint)
                    .frame(maxWidth: 360)
                    .padding(.top, 10)
            }
            downloadStatusLine(for: item)
            badgeStrip(for: item)
                .padding(.top, 16)
        } else if item.kind == "show" {
            showPlayButton(for: item)
                .padding(.top, 14)
        }
        if let overview = item.overview, !overview.isEmpty {
            Text(overview)
                .font(.bodyLarge)
                .foregroundStyle(Color.ink.opacity(0.92))
                .lineLimit(item.kind == "show" ? 4 : nil)
                .padding(.top, 18)
        }
        if let chapters = item.media?.chapters, chapters.count > 1 {
            Text("\(chapters.count) chapters")
                .font(.labelSmall)
                .foregroundStyle(Color.muted)
                .padding(.top, 10)
        }
    }

    private func metaLine(for item: Item) -> some View {
        var parts: [String] = []
        if let year = item.year, year > 0 { parts.append(String(year)) }
        if let duration = item.durationMs, duration > 0 { parts.append(formatRuntime(duration)) }
        if let rating = item.contentRating { parts.append(rating) }
        if let vote = item.voteAverage, vote > 0 { parts.append("★ " + String(format: "%.1f", vote)) }
        if item.kind == "show" {
            if let seasons = item.totalSeasons, seasons > 0 {
                parts.append(seasons == 1 ? "1 season" : "\(seasons) seasons")
            }
            // Offline this counts episodes that are not on the device, so the
            // line leaves it out rather than promising titles that cannot play.
            if !offline, let unwatched = item.unwatchedCount, unwatched > 0 {
                parts.append("\(unwatched) unwatched")
            }
        }
        for genre in (item.genres ?? []).prefix(3) { parts.append(genre.name) }
        return Text(parts.joined(separator: " · "))
            .font(.bodySmall)
            .foregroundStyle(Color.ink)
    }

    // MARK: - Play controls

    /// The split pill: play and download read as one control cut into
    /// segments.
    private func playControls(for item: Item) -> some View {
        HStack(spacing: 3) {
            Button {
                playbackItem = item
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text(playLabel(for: item))
                }
                .font(.labelLarge)
                .foregroundStyle(accent.onFill)
                .padding(.horizontal, 22)
                .frame(height: 48)
                .background(
                    accent.fill,
                    in: UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 24, bottomTrailingRadius: 6, topTrailingRadius: 6)
                )
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)

            downloadSegment(for: item)
        }
    }

    private func playLabel(for item: Item) -> String {
        guard let progress = item.progress else { return "Play" }
        if progress.played ?? false, (progress.resumePositionMs ?? 0) == 0 { return "Play again" }
        if let remaining = remainingLabel(item) { return "Resume · \(remaining)" }
        return "Play"
    }

    @ViewBuilder
    private func downloadSegment(for item: Item) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 6, bottomTrailingRadius: 24, topTrailingRadius: 24)
        if let entry = downloads.entry(for: item.id) {
            if !offline, downloadedMediaIsStale(storedMediaTag: entry.item.mediaTag, liveMediaTag: item.mediaTag) {
                Button {
                    guard let client = appEnvironment.client else { return }
                    downloads.remove(item.id)
                    Task { await downloads.start(item: item, client: client) }
                } label: {
                    Label("Update", systemImage: "arrow.down.circle")
                        .font(.labelLarge)
                        .foregroundStyle(accent.fill)
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(accent.fill.opacity(0.22), in: shape)
                }
                .buttonStyle(.plain)
                .hoverEffect(.lift)
            } else {
                Button {
                    removalEntry = entry
                    showRemovalConfirmation = true
                } label: {
                    Label("Downloaded", systemImage: "checkmark")
                        .font(.labelLarge)
                        .foregroundStyle(accent.fill)
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(accent.fill.opacity(0.22), in: shape)
                }
                .buttonStyle(.plain)
            }
        } else if let fraction = downloads.activeProgress[item.id] {
            Button {
                downloads.cancel(item.id)
            } label: {
                HStack(spacing: 7) {
                    ZStack {
                        Circle().stroke(accent.fill.opacity(0.25), lineWidth: 2.5)
                        Circle()
                            .trim(from: 0, to: max(fraction, 0.02))
                            .stroke(accent.fill, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 18, height: 18)
                    Text("Cancel")
                }
                .font(.labelLarge)
                .foregroundStyle(accent.fill)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(accent.fill.opacity(0.22), in: shape)
            }
            .buttonStyle(.plain)
        } else if downloads.failedItems[item.id] != nil {
            Button {
                guard let client = appEnvironment.client else { return }
                Task { await downloads.start(item: item, client: client) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.labelLarge)
                    .foregroundStyle(accent.fill.opacity(offline ? 0.4 : 1))
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(accent.fill.opacity(offline ? 0.10 : 0.22), in: shape)
            }
            .buttonStyle(.plain)
            .disabled(offline)
        } else {
            // Starting a download needs Loom to hand over a stream URL;
            // removing bytes that are already here does not.
            Button {
                guard let client = appEnvironment.client else { return }
                Task { await downloads.start(item: item, client: client) }
            } label: {
                Label("Download", systemImage: "arrow.down")
                    .font(.labelLarge)
                    .foregroundStyle(accent.fill.opacity(offline ? 0.4 : 1))
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(accent.fill.opacity(offline ? 0.10 : 0.22), in: shape)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            .disabled(offline)
        }
    }

    @ViewBuilder
    private func downloadStatusLine(for item: Item) -> some View {
        // Never color alone: the accent is woven from the artwork, so shape
        // and words carry state; color is reserved for failure.
        if let entry = downloads.entry(for: item.id) {
            if !offline, downloadedMediaIsStale(storedMediaTag: entry.item.mediaTag, liveMediaTag: item.mediaTag) {
                statusLine(icon: "arrow.triangle.2.circlepath", text: "New version available")
            } else {
                statusLine(icon: "checkmark.circle", text: "Downloaded")
            }
        } else if let fraction = downloads.activeProgress[item.id] {
            statusLine(icon: "arrow.down.circle", text: fraction == 0 ? "Queued" : "Downloading · \(Int(fraction * 100))%")
        } else if downloads.failedItems[item.id] != nil {
            statusLine(icon: "exclamationmark.circle", text: "Download failed")
        }
    }

    private func statusLine(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13))
            Text(text)
                .font(.bodySmall)
        }
        .foregroundStyle(Color.muted)
        .padding(.top, 8)
    }

    private func showPlayButton(for item: Item) -> some View {
        let next = episodes.first { !($0.progress?.played ?? false) }
        return Button {
            if let next {
                playbackItem = next
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text(showPlayLabel(next: next))
            }
            .font(.labelLarge)
            .foregroundStyle(accent.onFill)
            .padding(.horizontal, 22)
            .frame(height: 48)
            .background(accent.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .disabled(next == nil)
    }

    private func showPlayLabel(next: Item?) -> String {
        guard let next else { return "Play" }
        var parts: [String] = [(next.progress?.resumePositionMs ?? 0) > 0 ? "Resume" : "Play"]
        if let label = episodeLabel(next) { parts.append(label) }
        parts.append(next.title)
        return parts.joined(separator: " · ")
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
        return HStack(spacing: 6) {
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
    private func seasonSection(width: CGFloat) -> some View {
        if !seasons.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(seasons) { season in
                        seasonChip(season)
                    }
                }
            }
            // Explicit width: on the iOS 26 beta a ScrollView takes its
            // content's ideal width instead of clamping to the proposal,
            // leaving a long season strip with no scrollable range.
            .frame(width: width, alignment: .leading)
            .padding(.top, 20)
            .padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(episodes) { episode in
                    episodeRow(episode)
                }
            }
        }
    }

    private func seasonChip(_ season: Item) -> some View {
        let selected = season.id == selectedSeasonId
        let left = offline ? (offlineUnwatched[season.id] ?? 0) : (season.unwatchedCount ?? 0)
        return Button {
            selectedSeasonId = season.id
            Task { await loadEpisodes(of: season.id) }
        } label: {
            VStack(spacing: 1) {
                Text(season.title)
                    .font(.labelLarge)
                    .foregroundStyle(Color.ink)
                if left > 0 {
                    Text("\(left) left")
                        .font(.labelSmall)
                        .foregroundStyle(Color.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .background(selected ? accent.tint.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? accent.tint : Color.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    private func episodeRow(_ episode: Item) -> some View {
        NavigationLink(value: episode) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Color.surface1
                    if let url = episodeThumbURL(episode) {
                        CachedImage(url: url, contentMode: .fill)
                    }
                }
                .frame(width: 136, height: 136 * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottom) {
                    if let fraction = progressFraction(episode) {
                        ThreadProgress(fraction: fraction, color: accent.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(episodeRowTitle(episode))
                            .font(.titleSmall)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        if episode.progress?.played ?? false {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(accent.tint)
                        }
                    }
                    if let context = episodeContext(episode) {
                        Text(context)
                            .font(.labelSmall)
                            .foregroundStyle(Color.muted)
                    }
                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.bodySmall)
                            .foregroundStyle(Color.muted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .contextMenu {
            Button("Play", systemImage: "play.fill") { playbackItem = episode }
            watchedToggle(for: episode)
        }
    }

    private func episodeThumbURL(_ episode: Item) -> URL? {
        if offline {
            return downloads.artworkURL(for: episode.id, kind: .thumb)
                ?? downloads.posterURL(for: episode.id)
        }
        return appEnvironment.client?.imageURL(id: episode.thumbImageId, tag: episode.thumbImageTag, width: 480)
    }

    private func episodeRowTitle(_ episode: Item) -> String {
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
            creditsList(credits)
                .padding(.top, 24)
        }
    }

    @ViewBuilder
    private func creditsPane(for item: Item) -> some View {
        if let credits = item.credits, !credits.isEmpty {
            creditsList(credits)
                .padding(.top, 14)
        }
    }

    private func creditsList(_ credits: [Credit]) -> some View {
        let ordered = credits.sorted { a, b in
            (a.role == "Director" ? 0 : 1) < (b.role == "Director" ? 0 : 1)
        }
        let visible = castExpanded ? ordered : Array(ordered.prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            RowLabel(text: "Cast")
                .padding(.bottom, 2)
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
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Tapping a card searches the person, matching the Android bill.
    private func creditCard(_ credit: Credit) -> some View {
        NavigationLink(value: PersonSearch(name: credit.name)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(credit.name)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.ink)
                Text(credit.character ?? credit.role)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.ink.opacity(0.10), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        // The search behind this card can only reach Loom's credits index.
        .disabled(offline)
    }

    // MARK: - Watched toggle

    private func watchedToggle(for item: Item) -> some View {
        let played = item.progress?.played ?? false
        // For shows/seasons "watched" means no unwatched episodes remain.
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
                watched ? "Mark as Unwatched" : "Mark as Watched",
                systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle"
            )
        }
        // A write to Loom, which offline would only fail.
        .disabled(offline)
    }

    // MARK: - Data

    private func detailArtURL(width: Int) -> URL? {
        guard let item else { return nil }
        if offline {
            if item.kind == "episode", let thumb = downloads.artworkURL(for: item.id, kind: .thumb) {
                return thumb
            }
            return downloads.artworkURL(for: item.id, kind: .backdrop)
                ?? downloads.artworkURL(for: item.id, kind: .thumb)
                ?? downloads.posterURL(for: item.id)
        }
        guard let client = appEnvironment.client else { return nil }
        return Takeup.detailArtURL(for: item, client: client, width: width)
    }

    /// `force` is the Try again button: the user is asking for the attempt
    /// itself, so a stale offline verdict must not answer for the server.
    private func load(force: Bool = false) async {
        guard let client = appEnvironment.client else { return }
        // A settled offline verdict is answered from the snapshots without
        // spending a request that has nowhere to go.
        if !force, network.reach == .offline {
            await loadOffline()
            return
        }
        loadError = nil
        do {
            let loaded = try await client.item(id: itemId)
            item = loaded
            offline = false
            network.markReachable()
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
            if isOfflineError(error) {
                network.markUnreachable()
                await loadOffline()
                return
            }
            loadError = error.localizedDescription
        }
        dressed = true
    }

    /// The same screen over the offline catalog. A show is browsable with no
    /// Loom because its seasons were captured with the episodes beneath it;
    /// what is missing is only what was never downloaded.
    private func loadOffline() async {
        let catalog = downloads.offlineCatalog
        let snapshot = catalog.item(itemId)
        item = snapshot
        loadError = nil
        offline = true
        if let snapshot, snapshot.kind == "show" {
            seasons = catalog.children(snapshot.id)
            offlineUnwatched = Dictionary(uniqueKeysWithValues: seasons.map { season in
                (season.id, catalog.children(season.id).filter { !($0.progress?.played ?? false) }.count)
            })
            // Land on the season holding the next unwatched episode on this
            // device; specials never stand in front of a pilot.
            let regular = seasons.filter { ($0.seasonNumber ?? 0) != 0 }
            let target = regular.first { (offlineUnwatched[$0.id] ?? 0) > 0 }
                ?? regular.first ?? seasons.first
            if selectedSeasonId == nil || !seasons.contains(where: { $0.id == selectedSeasonId }) {
                selectedSeasonId = target?.id
            }
            episodes = selectedSeasonId.map { catalog.children($0) } ?? []
        } else if let snapshot, snapshot.kind == "season" {
            seasons = []
            episodes = catalog.children(snapshot.id)
        } else {
            seasons = []
            episodes = []
        }
        if snapshot != nil {
            await resolveThreads()
        }
        dressed = true
    }

    private func loadEpisodes(of seasonId: Int64) async {
        if offline {
            episodes = downloads.offlineCatalog.children(seasonId)
            return
        }
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
