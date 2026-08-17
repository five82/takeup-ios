import SwiftUI

/// Home, mirroring the Android app: gauze from the featured pick's backdrop,
/// a bias-cut hero with the logo lane, then Continue Watching, Next Up,
/// Recently Added, and the day's discovery shelves.
///
/// With no Loom the same shapes are drawn over the downloads instead: the hero
/// is what is half-watched (else what landed most recently), and the two rows
/// are Continue Watching and Downloaded.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(DownloadManager.self) private var downloads
    @Environment(NetworkPolicy.self) private var network
    @State private var featuredPick: Item?
    @State private var continueWatching: [Item] = []
    @State private var nextUp: [Item] = []
    @State private var recentlyAdded: [Item] = []
    @State private var discovery: [DiscoveryRow] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var offline = false
    @State private var playbackItem: Item?
    @State private var heroLogoAspect: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GauzeBackground(
                    url: gauzeURL,
                    scrimAlphaScale: heroItem != nil ? 0.9 : 1.0
                )
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let hero = heroItem {
                            heroView(hero, width: proxy.size.width)
                        } else {
                            // No hero art to run under the status bar; keep
                            // the rows out of it.
                            Color.clear.frame(height: proxy.safeAreaInsets.top)
                        }
                        if offline {
                            offlineRows(width: proxy.size.width)
                        } else {
                            rows
                        }
                    }
                    .padding(.bottom, 32)
                }
                // The hero backdrop runs seamlessly to the screen's top edge,
                // matching the Android app; the art's own wash keeps the
                // status bar legible, so the system's grey edge haze must
                // stay out of it.
                .ignoresSafeArea(edges: .top)
                .scrollEdgeEffectHidden(true, for: .top)
            }
        }
        .background(Color.stage)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(itemId: item.id, fallbackTitle: item.title)
        }
        .fullScreenCover(item: $playbackItem, onDismiss: { Task { await load() } }) { playable in
            PlayerScreen(item: playable)
        }
        .overlay {
            if appEnvironment.client == nil {
                ErrorState(message: "Enter your Loom server address in Settings.", retry: nil)
            } else if offline {
                // The offline rows (or the notice standing in for them) are
                // part of the page, not an overlay over it.
                EmptyView()
            } else if !loaded, loadError == nil {
                LoadingState()
            } else if let loadError, isEmpty {
                ErrorState(message: loadError) { Task { await load() } }
            } else if loaded, isEmpty {
                EmptyState(message: "Play something and it will show up here.")
            }
        }
        // Keyed on reach so walking back onto the LAN recovers on its own,
        // rather than leaving the offline page up until something asks.
        .task(id: network.reach) { await load() }
        .refreshable { await load() }
    }

    private var isEmpty: Bool {
        featuredPick == nil && continueWatching.isEmpty && nextUp.isEmpty
            && recentlyAdded.isEmpty && discovery.isEmpty
    }

    // MARK: - Hero

    /// Offline the hero is a download; online it is Loom's featured pick.
    private var heroItem: Item? {
        guard offline else { return featuredPick }
        let catalog = downloads.offlineCatalog
        return catalog.continueWatching().first ?? catalog.recent().first
    }

    private var heroBackdropURL: URL? {
        guard let hero = heroItem else { return nil }
        if offline {
            return downloads.artworkURL(for: hero.id, kind: .backdrop)
                ?? downloads.artworkURL(for: hero.id, kind: .thumb)
                ?? downloads.posterURL(for: hero.id)
        }
        return appEnvironment.client?.imageURL(id: hero.backdropImageId, tag: hero.backdropImageTag, width: 960)
            ?? appEnvironment.client?.imageURL(id: hero.thumbImageId, tag: hero.thumbImageTag, width: 960)
    }

    private var gauzeURL: URL? {
        guard let hero = heroItem else { return nil }
        if offline {
            // The saved backdrop is the 1440 bucket, but a blur has no detail
            // to lose either way.
            return downloads.artworkURL(for: hero.id, kind: .backdrop)
                ?? downloads.posterURL(for: hero.id)
        }
        guard let client = appEnvironment.client else { return nil }
        // The gauze is blurred past recognition; the 240 bucket is plenty.
        return client.imageURL(id: hero.backdropImageId, tag: hero.backdropImageTag, width: 240)
            ?? client.imageURL(id: hero.posterImageId, tag: hero.posterImageTag, width: 240)
    }

    private func heroLogoURL(_ hero: Item) -> URL? {
        if offline {
            return downloads.artworkURL(for: hero.id, kind: .logo)
        }
        return appEnvironment.client?.imageURL(id: hero.logoImageId, tag: hero.logoImageTag, width: 480)
    }

    private func heroView(_ hero: Item, width: CGFloat) -> some View {
        let logoURL = heroLogoURL(hero)
        let lane = logoLaneHeight(aspect: heroLogoAspect)
        let solidLeft: CGFloat = logoURL != nil ? lane + 76 : 160
        // The whole hero is one tap target, matching the Android app.
        return NavigationLink(value: hero) {
            BiasCutBackdrop(url: heroBackdropURL, width: width, solidLeft: solidLeft) {
                VStack(alignment: .leading, spacing: 0) {
                    heroIdentity(hero, logoURL: logoURL, lane: lane, width: width)
                    heroMeta(hero, width: width)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            // The ground below the bias cut is transparent, so without an
            // explicit content shape taps there fall through; Android's
            // clickable Box covers the hero's full rect.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func heroIdentity(_ hero: Item, logoURL: URL?, lane: CGFloat, width: CGFloat) -> some View {
        if let logoURL {
            CachedImage(url: logoURL, contentMode: .fit, onLoad: { image in
                let aspect = Double(image.size.width / max(image.size.height, 1))
                if heroLogoAspect != aspect {
                    withAnimation(.spring) { heroLogoAspect = aspect }
                }
            }) { Color.clear }
                .frame(width: min(CGFloat(heroLogoAspect ?? 3) * lane, width * 0.5), height: lane)
        } else {
            Text(hero.title)
                .font(.displayMedium)
                .foregroundStyle(Color.ink)
                .lineLimit(2)
        }
    }

    private func heroMeta(_ hero: Item, width: CGFloat) -> some View {
        let hour = Calendar.current.component(.hour, from: Date())
        var parts = [offline ? offlineHeroLabel(hero) : featuredPickLabel(hour: hour)]
        if let year = hero.year, year > 0 { parts.append(String(year)) }
        if let genre = hero.genres?.first?.name { parts.append(genre) }
        return VStack(alignment: .leading, spacing: 0) {
            Text(parts.joined(separator: " · "))
                .font(.bodyMedium)
                .foregroundStyle(Color.ink.opacity(0.85))
                .padding(.top, 10)
                .padding(.bottom, 8)
            if let fraction = progressFraction(hero) {
                ThreadProgress(fraction: fraction, thread: RGB(hexValue: 0xFF4D55))
                    .frame(width: width * 0.6)
            }
        }
    }

    /// Offline there is no pick of the day to name, so the hero says why it is
    /// the one standing there.
    private func offlineHeroLabel(_ hero: Item) -> String {
        progressFraction(hero) != nil ? "Continue watching" : "Downloaded"
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        if !continueWatching.isEmpty {
            thumbRow(
                title: "Continue Watching",
                items: continueWatching,
                caption: { item in
                    [episodeLabel(item), item.kind == "episode" ? item.title : nil, remainingLabel(item)]
                        .compactMap { $0 }.joined(separator: " · ")
                }
            )
        }
        if !nextUp.isEmpty {
            thumbRow(
                title: "Next Up",
                items: nextUp,
                caption: { item in
                    [episodeLabel(item), item.title].compactMap { $0 }.joined(separator: " · ")
                }
            )
        }
        if !recentlyAdded.isEmpty {
            posterRow(title: "Recently Added", items: recentlyAdded, labelColor: .muted)
        }
        ForEach(discovery) { shelf in
            posterRow(title: shelf.title, items: shelf.items, labelColor: .violet)
        }
    }

    // The width is passed in rather than left to `maxWidth: .infinity`: Home's
    // rows are horizontal scrollers, so the column they sit in is proposed no
    // width of its own and a full-width row would size to its ideal instead.
    @ViewBuilder
    private func offlineRows(width: CGFloat) -> some View {
        let catalog = downloads.offlineCatalog
        let started = catalog.continueWatching()
        let downloaded = catalog.recent()
        let lineWidth = max(width - 40, 0)
        if started.isEmpty && downloaded.isEmpty {
            OfflineNotice(
                reason: network.reason + " Nothing is downloaded to this device yet.",
                onRetry: retry
            )
            .frame(width: lineWidth)
            .padding(.horizontal, 20)
            .padding(.top, 24)
        } else {
            OfflineBanner(reason: network.reason, onRetry: retry)
                .frame(width: lineWidth)
                .padding(.horizontal, 20)
                .padding(.top, 16)
            if !started.isEmpty {
                thumbRow(
                    title: "Continue Watching",
                    items: started,
                    caption: { offlineCaption($0, catalog: catalog) }
                )
            }
            if !downloaded.isEmpty {
                posterRow(
                    title: "Downloaded",
                    items: downloaded,
                    labelColor: .violet,
                    badge: { item in
                        item.kind == "show"
                            ? catalog.episodes(showId: item.id).filter { !($0.progress?.played ?? false) }.count
                            : nil
                    }
                )
            }
        }
    }

    /// Like the online caption, but naming the show as well: offline nothing
    /// else on the row does.
    private func offlineCaption(_ item: Item, catalog: OfflineCatalog) -> String {
        [
            catalog.show(forEpisode: item.id)?.title,
            episodeLabel(item),
            item.kind == "episode" ? item.title : nil,
            remainingLabel(item),
        ]
        .compactMap { $0 }.joined(separator: " · ")
    }

    private func thumbRow(title: String, items: [Item], caption: @escaping (Item) -> String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeRowLabel(text: title)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            playbackItem = item
                        } label: {
                            ThumbCard(item: item, caption: caption(item))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Play", systemImage: "play.fill") { playbackItem = item }
                            NavigationLink(value: item) {
                                Label("Go to Details", systemImage: "info.circle")
                            }
                            // A write to Loom, which offline would only fail.
                            if !offline {
                                Button("Mark Watched", systemImage: "checkmark.circle") {
                                    Task {
                                        try? await appEnvironment.client?.setPlayed(id: item.id, true)
                                        await load()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 22)
    }

    private func posterRow(
        title: String,
        items: [Item],
        labelColor: Color,
        badge: ((Item) -> Int?)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeRowLabel(text: title, color: labelColor)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            PosterCard(item: item, badgeCount: badge?(item))
                                .frame(width: 150)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 22)
    }

    // MARK: - Data

    private func retry() {
        network.recheck()
        Task { await load() }
    }

    private func load() async {
        guard let client = appEnvironment.client else {
            loaded = true
            return
        }
        // A settled offline verdict is answered from the downloads without
        // spending a request that has nowhere to go.
        if network.reach == .offline {
            offline = true
            loaded = true
            return
        }
        loadError = nil
        async let featuredResult = client.featuredPick()
        async let continueWatchingPage = client.continueWatching()
        async let nextUpPage = client.nextUp()
        async let recentlyAddedPage = client.recentlyAdded()
        async let moviesResult = client.allItems(library: "movies")
        async let showsResult = client.allItems(library: "tv")
        async let collectionsResult = client.collections()
        async let recentlyPlayedPage = client.recentlyPlayed()
        do {
            featuredPick = try await featuredResult.item
            continueWatching = try await continueWatchingPage.items
            nextUp = try await nextUpPage.items
            recentlyAdded = try await recentlyAddedPage.items
            let epochDay = Int64(Date().timeIntervalSince1970 / 86_400)
            discovery = discoveryRows(
                movies: try await moviesResult,
                shows: try await showsResult,
                collections: try await collectionsResult,
                recentlyPlayed: try await recentlyPlayedPage.items,
                epochDay: epochDay
            )
            offline = false
            // The server answered, so anything queued while offline can land.
            await downloads.flushPendingProgress(client: client)
        } catch {
            if isOfflineError(error) {
                network.markUnreachable()
                offline = true
            } else if isEmpty {
                loadError = error.localizedDescription
            }
        }
        loaded = true
    }
}
