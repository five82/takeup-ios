import SwiftUI

/// Home at ten feet, the same weave as the iPad: gauze from the featured
/// pick's backdrop, a bias-cut hero with the logo lane, then Continue
/// Watching, Next Up, Recently Added, and the day's discovery shelves —
/// all focus-driven.
struct TVHomeView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @State private var featuredPick: Item?
    @State private var continueWatching: [Item] = []
    @State private var nextUp: [Item] = []
    @State private var recentlyAdded: [Item] = []
    @State private var discovery: [DiscoveryRow] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var playbackItem: Item?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GauzeBackground(url: gauzeURL, scrimAlphaScale: featuredPick != nil ? 0.9 : 1.0)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let hero = featuredPick {
                            heroView(hero, size: proxy.size)
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
        // Waking the box catches home up: artwork tags, progress, new items.
        // The app can sit resident for days, and stale rows meant blank
        // posters after an artwork change. Skipped at launch (`loaded` is
        // still false) — the initial .task load is already running.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, loaded else { return }
            Task { await load() }
        }
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

    private func heroView(_ hero: Item, size: CGSize) -> some View {
        // Only the identity column is focusable, not the full-width backdrop:
        // a down-press moves to the card nearest the focused frame, and the
        // full-width hero handed focus to whichever card sat under the
        // screen's center instead of the row's first card. Select still opens
        // the hero whenever it holds focus, and the focus treatment below
        // paints the whole backdrop, so from the couch the hero remains one
        // target. (A Button rather than a NavigationLink because a link
        // styled as the hero would fight the focus engine's card treatment;
        // it pushes through the item-binding destination below.)
        SelvedgeBackdrop(
            url: heroBackdropURL,
            width: size.width,
            height: size.height * TVLayout.heroBand,
            seam: TVLayout.heroSeam
        ) {
            Button {
                heroPush = hero
            } label: {
                heroColumn(hero, width: size.width)
                    .contentShape(Rectangle())
            }
            .buttonStyle(TVHeroButtonStyle())
            .focused($heroFocused)
            .padding(.leading, TVLayout.sideMargin)
            // alignment .leading centers the column on the band's height.
            .frame(height: size.height * TVLayout.heroBand, alignment: .leading)
        }
        // The full-width section keeps the hero reachable: an up-press from a
        // card right of the identity column would otherwise find no candidate
        // (focus search wants horizontal overlap) and go nowhere.
        .focusSection()
        // The hero breathes rather than lifts — a selvedge backdrop on a card
        // platter would break the seamless ground the seam depends on. The
        // ember glow bleeds out along the seam, so a still frame shows the
        // hero holds focus.
        .scaleEffect(heroFocused ? 1.02 : 1, anchor: .bottom)
        .brightness(heroFocused ? 0.06 : 0)
        .shadow(color: Color.ember.opacity(heroFocused ? 0.45 : 0), radius: 30, y: 12)
        .animation(.easeOut(duration: 0.2), value: heroFocused)
    }

    @State private var heroPush: Item?
    @FocusState private var heroFocused: Bool

    /// The invitation, not a detail screen: five short elements — pick label,
    /// logo, the selvedge stripe, year · genres, tagline — plus the thread
    /// when the pick is resumable. The overview never renders at home
    /// altitude; a select answers anything past "what is this?".
    private func heroColumn(_ hero: Item, width: CGFloat) -> some View {
        let columnWidth = width * TVLayout.heroSeam - TVLayout.sideMargin - 44
        let logoURL = appEnvironment.client?.imageURL(id: hero.logoImageId, tag: hero.logoImageTag, width: 480)
        let hour = Calendar.current.component(.hour, from: Date())
        var meta: [String] = []
        if let year = hero.year, year > 0 { meta.append(String(year)) }
        for genre in (hero.genres ?? []).prefix(2) { meta.append(genre.name) }
        return VStack(alignment: .leading, spacing: 0) {
            RowLabel(text: featuredPickLabel(hour: hour), color: .violet)
            heroIdentity(hero, logoURL: logoURL, columnWidth: columnWidth)
                .padding(.top, 20)
            Selvedge(height: 5)
                .frame(width: 170)
                .padding(.top, 22)
            if !meta.isEmpty {
                Text(meta.joined(separator: " · "))
                    .font(.bodyMedium)
                    .foregroundStyle(Color.ink.opacity(0.85))
                    .padding(.top, 20)
            }
            if let tagline = hero.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.bodyMedium)
                    .italic()
                    .foregroundStyle(Color.ink.opacity(0.92))
                    .padding(.top, 14)
            }
            if let fraction = progressFraction(hero) {
                ThreadProgress(fraction: fraction, thread: RGB(hexValue: 0xFF4D55))
                    .frame(width: columnWidth * 0.7)
                    .padding(.top, 26)
            }
        }
        .frame(width: columnWidth, alignment: .leading)
    }

    @ViewBuilder
    private func heroIdentity(_ hero: Item, logoURL: URL?, columnWidth: CGFloat) -> some View {
        if let logoURL {
            LogoBox(url: logoURL, width: columnWidth, height: logoBoxHeight)
        } else {
            Text(hero.title)
                .font(.displaySmall)
                .foregroundStyle(Color.ink)
                .lineLimit(3)
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
    @State private var rowOffsets: [String: CGFloat] = [:]
    /// Upward row entry surfaces as two focus changes — card to nil, then nil
    /// to the landing card — so the origin of a move has to be remembered, not
    /// read from the change's `old`.
    @State private var lastFocus: RowFocus?

    private var rowGeometry: [String: (items: [Item], cardWidth: CGFloat)] {
        var table: [String: (items: [Item], cardWidth: CGFloat)] = [
            "Continue Watching": (continueWatching, TVLayout.thumbWidth),
            "Next Up": (nextUp, TVLayout.thumbWidth),
            "Recently Added": (recentlyAdded, TVLayout.posterWidth),
        ]
        for shelf in discovery { table[shelf.title] = (shelf.items, TVLayout.posterWidth) }
        return table
    }

    /// The screen-space center X of a row's card: leading margin, minus how
    /// far the row is scrolled, plus the fixed card pitch.
    private func cardCenterX(in row: (items: [Item], cardWidth: CGFloat), title: String, index: Int) -> CGFloat {
        TVLayout.sideMargin - (rowOffsets[title] ?? 0)
            + CGFloat(index) * (row.cardWidth + TVLayout.cardSpacing) + row.cardWidth / 2
    }

    /// A vertical press should land on the card straight below or above the
    /// one it left — the line the focus engine promises but does not reliably
    /// deliver here: entering a row that has scrolled off screen lands a card
    /// to the right of the straight line, and a press that arrives while the
    /// previous move's scroll is still animating enters through the row
    /// section's full-width frame and lands near the screen's center. The
    /// steering recomputes the target from the rows' known layout — fixed
    /// card widths and spacing plus tracked scroll offsets — and corrects the
    /// engine's landing. No history: the target is always the on-screen card
    /// in line with where focus came from, so the corrected card is realized
    /// and the reassignment cannot be dropped by the lazy stack.
    private func steerRowFocus(from old: RowFocus?, to new: RowFocus?) {
        guard let new else { return }
        let origin = old ?? lastFocus
        lastFocus = new
        guard let origin, origin.row != new.row,
              let originRow = rowGeometry[origin.row], let newRow = rowGeometry[new.row],
              !newRow.items.isEmpty,
              let originIndex = originRow.items.firstIndex(where: { $0.id == origin.id })
        else { return }
        let x = cardCenterX(in: originRow, title: origin.row, index: originIndex)
        let lead = TVLayout.sideMargin - (rowOffsets[new.row] ?? 0)
        let slot = (x - lead - newRow.cardWidth / 2) / (newRow.cardWidth + TVLayout.cardSpacing)
        let target = min(max(Int(slot.rounded()), 0), newRow.items.count - 1)
        let targetID = newRow.items[target].id
        if targetID != new.id {
            focusedCard = RowFocus(row: new.row, id: targetID)
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
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x
            } action: { _, offset in
                rowOffsets[title] = offset
            }
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
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x
            } action: { _, offset in
                rowOffsets[title] = offset
            }
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
