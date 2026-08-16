import SwiftUI

/// Home, mirroring the Android app: gauze from the featured pick's backdrop,
/// a bias-cut hero with the logo lane, then Continue Watching, Next Up,
/// Recently Added, and the day's discovery shelves.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var featuredPick: Item?
    @State private var continueWatching: [Item] = []
    @State private var nextUp: [Item] = []
    @State private var recentlyAdded: [Item] = []
    @State private var discovery: [DiscoveryRow] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var playbackItem: Item?
    @State private var heroLogoAspect: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GauzeBackground(
                    url: gauzeURL,
                    scrimAlphaScale: heroBackdropURL != nil ? 0.9 : 1.0
                )
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let hero = featuredPick {
                            heroView(hero, width: proxy.size.width)
                        } else {
                            // No hero art to run under the status bar; keep
                            // the rows out of it.
                            Color.clear.frame(height: proxy.safeAreaInsets.top)
                        }
                        rows
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
            } else if !loaded, loadError == nil {
                LoadingState()
            } else if let loadError, isEmpty {
                ErrorState(message: loadError) { Task { await load() } }
            } else if loaded, isEmpty {
                EmptyState(message: "Play something and it will show up here.")
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var isEmpty: Bool {
        featuredPick == nil && continueWatching.isEmpty && nextUp.isEmpty
            && recentlyAdded.isEmpty && discovery.isEmpty
    }

    // MARK: - Hero

    private var heroBackdropURL: URL? {
        guard let hero = featuredPick else { return nil }
        return appEnvironment.client?.imageURL(id: hero.backdropImageId, tag: hero.backdropImageTag, width: 960)
            ?? appEnvironment.client?.imageURL(id: hero.thumbImageId, tag: hero.thumbImageTag, width: 960)
    }

    private var gauzeURL: URL? {
        guard let hero = featuredPick, let client = appEnvironment.client else { return nil }
        // The gauze is blurred past recognition; the 240 bucket is plenty.
        return client.imageURL(id: hero.backdropImageId, tag: hero.backdropImageTag, width: 240)
            ?? client.imageURL(id: hero.posterImageId, tag: hero.posterImageTag, width: 240)
    }

    private func heroView(_ hero: Item, width: CGFloat) -> some View {
        let logoURL = appEnvironment.client?.imageURL(id: hero.logoImageId, tag: hero.logoImageTag, width: 480)
        let lane = logoLaneHeight(aspect: heroLogoAspect)
        let solidLeft: CGFloat = logoURL != nil ? lane + 76 : 160
        return BiasCutBackdrop(url: heroBackdropURL, width: width, solidLeft: solidLeft) {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink(value: hero) {
                    heroIdentity(hero, logoURL: logoURL, lane: lane, width: width)
                }
                .buttonStyle(.plain)
                heroMeta(hero, width: width)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
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
        var parts = [featuredPickLabel(hour: hour)]
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
                            Button("Mark Watched", systemImage: "checkmark.circle") {
                                Task {
                                    try? await appEnvironment.client?.setPlayed(id: item.id, true)
                                    await load()
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

    private func posterRow(title: String, items: [Item], labelColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeRowLabel(text: title, color: labelColor)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            PosterCard(item: item)
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

    private func load() async {
        guard let client = appEnvironment.client else {
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
        } catch {
            if isEmpty { loadError = error.localizedDescription }
        }
        loaded = true
    }
}
