import SwiftUI

/// Home at ten feet, the same weave as the iPad: gauze from the featured
/// pick's backdrop, a bias-cut hero with the logo lane, then Continue
/// Watching, Next Up, Recently Added, and the day's discovery shelves —
/// all focus-driven.
struct TVHomeView: View {
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
                GauzeBackground(url: gauzeURL, scrimAlphaScale: featuredPick != nil ? 0.9 : 1.0)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let hero = featuredPick {
                            heroView(hero, width: proxy.size.width)
                        }
                        rows(width: proxy.size.width)
                    }
                    .padding(.bottom, TVLayout.verticalMargin)
                    .frame(width: proxy.size.width, alignment: .leading)
                }
            }
        }
        // The screen owns its overscan margins (TVLayout); the system inset
        // would gutter the bias-cut hero off the screen edges. Ignoring it on
        // the GeometryReader makes proxy.size the full screen, so the hero is
        // cut to the true edge-to-edge width instead of the inset width.
        .ignoresSafeArea()
        .background(Color.stage)
        .navigationDestination(for: Item.self) { item in
            TVDetailView(itemId: item.id, fallbackTitle: item.title)
        }
        .navigationDestination(item: $heroPush) { hero in
            TVDetailView(itemId: hero.id, fallbackTitle: hero.title)
        }
        .fullScreenCover(item: $playbackItem, onDismiss: { Task { await load() } }) { playable in
            TVPlayerScreen(item: playable)
        }
        .overlay {
            if !loaded, loadError == nil {
                LoadingState()
            } else if let loadError, isEmpty {
                ErrorState(message: loadError) { Task { await load() } }
            } else if loaded, isEmpty {
                EmptyState(message: "Play something and it will show up here.")
            }
        }
        .onChange(of: focusedCard) { old, new in
            steerRowFocus(from: old, to: new)
        }
        .task { await load() }
    }

    private var isEmpty: Bool {
        featuredPick == nil && continueWatching.isEmpty && nextUp.isEmpty
            && recentlyAdded.isEmpty && discovery.isEmpty
    }

    // MARK: - Hero

    private var gauzeURL: URL? {
        guard let hero = featuredPick, let client = appEnvironment.client else { return nil }
        // The gauze is blurred past recognition; the 240 bucket is plenty.
        return client.imageURL(id: hero.backdropImageId, tag: hero.backdropImageTag, width: 240)
            ?? client.imageURL(id: hero.posterImageId, tag: hero.posterImageTag, width: 240)
    }

    private var heroBackdropURL: URL? {
        guard let hero = featuredPick, let client = appEnvironment.client else { return nil }
        return client.imageURL(id: hero.backdropImageId, tag: hero.backdropImageTag, width: 1440)
            ?? client.imageURL(id: hero.thumbImageId, tag: hero.thumbImageTag, width: 1440)
    }

    private func heroView(_ hero: Item, width: CGFloat) -> some View {
        let logoURL = appEnvironment.client?.imageURL(id: hero.logoImageId, tag: hero.logoImageTag, width: 480)
        let lane = logoLaneHeight(aspect: heroLogoAspect) * 1.5
        let solidLeft: CGFloat = logoURL != nil ? lane + 110 : 230
        // Only the identity block is focusable, not the full-width backdrop:
        // a down-press moves to the card nearest the focused frame, and the
        // full-width hero handed focus to whichever card sat under the
        // screen's center instead of the row's first card. Select still opens
        // the hero whenever it holds focus, and the focus treatment below
        // paints the whole backdrop, so from the couch the hero remains one
        // target. (A Button rather than a NavigationLink because a link
        // styled as the hero would fight the focus engine's card treatment;
        // it pushes through the item-binding destination below.)
        return BiasCutBackdrop(url: heroBackdropURL, width: width, solidLeft: solidLeft) {
            Button {
                heroPush = hero
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    heroIdentity(hero, logoURL: logoURL, lane: lane, width: width)
                    heroMeta(hero, width: width)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(TVHeroButtonStyle())
            .focused($heroFocused)
            .padding(.horizontal, TVLayout.sideMargin)
            .padding(.bottom, 26)
        }
        // The full-width section keeps the hero reachable: an up-press from a
        // card right of the identity block would otherwise find no candidate
        // (focus search wants horizontal overlap) and go nowhere.
        .focusSection()
        // The hero breathes rather than lifts — a bias-cut backdrop on a card
        // platter would break the seamless ground the cut depends on. The
        // ember glow bleeds out along the bias-cut edge, so a still frame
        // shows the hero holds focus.
        .scaleEffect(heroFocused ? 1.02 : 1, anchor: .bottom)
        .brightness(heroFocused ? 0.06 : 0)
        .shadow(color: Color.ember.opacity(heroFocused ? 0.45 : 0), radius: 30, y: 12)
        .animation(.easeOut(duration: 0.2), value: heroFocused)
    }

    @State private var heroPush: Item?
    @FocusState private var heroFocused: Bool

    @ViewBuilder
    private func heroIdentity(_ hero: Item, logoURL: URL?, lane: CGFloat, width: CGFloat) -> some View {
        if let logoURL {
            CachedImage(url: logoURL, contentMode: .fit, onLoad: { image in
                let aspect = Double(image.size.width / max(image.size.height, 1))
                if heroLogoAspect != aspect {
                    withAnimation(.spring) { heroLogoAspect = aspect }
                }
            }) { Color.clear }
                .frame(width: min(CGFloat(heroLogoAspect ?? 3) * lane, width * 0.4), height: lane)
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
                .padding(.top, 14)
                .padding(.bottom, 12)
            if let fraction = progressFraction(hero) {
                ThreadProgress(fraction: fraction, thread: RGB(hexValue: 0xFF4D55))
                    .frame(width: width * 0.35)
            }
        }
    }

    // MARK: - Rows

    /// A focused card, identified by row and item (the same item can sit in
    /// two rows, so the id alone is ambiguous).
    private struct RowFocus: Hashable {
        let row: String
        let id: Int64
    }

    @FocusState private var focusedCard: RowFocus?
    @State private var rowMemory: [String: Int64] = [:]

    private var rowTable: [String: [Item]] {
        var table = [
            "Continue Watching": continueWatching,
            "Next Up": nextUp,
            "Recently Added": recentlyAdded,
        ]
        for shelf in discovery { table[shelf.title] = shelf.items }
        return table
    }

    /// Rows remember their last-focused card, first card by default — the
    /// shelf behavior of UIKit's remembersLastFocusedIndexPath and the
    /// Android app's Compose rows. Geometry alone is not enough: a press
    /// that arrives while the previous move's scroll is still animating
    /// enters the next row from the row section's full-width frame, landing
    /// on whichever card sits near the screen's center.
    private func steerRowFocus(from old: RowFocus?, to new: RowFocus?) {
        guard let new else { return }
        if old?.row == new.row {
            rowMemory[new.row] = new.id
            return
        }
        let items = rowTable[new.row] ?? []
        let remembered = rowMemory[new.row].flatMap { id in
            items.contains { $0.id == id } ? id : nil
        }
        let target = remembered ?? items.first?.id
        if let target, target != new.id {
            focusedCard = RowFocus(row: new.row, id: target)
        } else {
            rowMemory[new.row] = new.id
        }
    }

    @ViewBuilder
    private func rows(width: CGFloat) -> some View {
        if !continueWatching.isEmpty {
            thumbRow(
                title: "Continue Watching",
                items: continueWatching,
                heading: { $0.seriesTitle },
                caption: { continueLine($0) }
            )
        }
        if !nextUp.isEmpty {
            thumbRow(
                title: "Next Up",
                items: nextUp,
                heading: { $0.seriesTitle },
                caption: { episodeLine($0) ?? $0.title }
            )
        }
        if !recentlyAdded.isEmpty {
            posterRow(title: "Recently Added", items: recentlyAdded, labelColor: .muted)
        }
        ForEach(discovery) { shelf in
            posterRow(title: shelf.title, items: shelf.items, labelColor: .violet)
        }
    }

    private func thumbRow(
        title: String,
        items: [Item],
        heading: @escaping (Item) -> String?,
        caption: @escaping (Item) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeRowLabel(text: title)
                .padding(.horizontal, TVLayout.sideMargin)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: TVLayout.cardSpacing) {
                    ForEach(items) { item in
                        TVThumbCell(
                            item: item,
                            heading: heading(item),
                            caption: caption(item)
                        ) {
                            playbackItem = item
                        }
                        .focused($focusedCard, equals: RowFocus(row: title, id: item.id))
                    }
                }
                .padding(.horizontal, TVLayout.sideMargin)
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
            // Each shelf is one focus section, so a vertical swipe lands in
            // the neighboring row even when it is scrolled past the column
            // the swipe started from.
            .focusSection()
        }
        .padding(.top, TVLayout.rowSpacing - 30)
    }

    private func posterRow(title: String, items: [Item], labelColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HomeRowLabel(text: title, color: labelColor)
                .padding(.horizontal, TVLayout.sideMargin)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: TVLayout.cardSpacing) {
                    ForEach(items) { item in
                        TVPosterCell(item: item, width: TVLayout.posterWidth)
                            .focused($focusedCard, equals: RowFocus(row: title, id: item.id))
                    }
                }
                .padding(.horizontal, TVLayout.sideMargin)
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
            .focusSection()
        }
        .padding(.top, TVLayout.rowSpacing - 30)
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
