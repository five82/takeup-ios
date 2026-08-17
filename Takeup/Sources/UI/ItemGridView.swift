import SwiftUI

/// Poster grid over /items: the full A-Z of a library, a genre, or a
/// collection's members. Loom returns no total count, so the end is detected
/// by a short page. Library tabs get their thread's house lights; pushed
/// genre/collection grids get the lead poster's shadow weave.
struct ItemGridView: View {
    enum Source: Hashable {
        case library(kind: String)
        case genre(Genre)
        case collection(MediaCollection)
    }

    let source: Source
    let title: String

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(DownloadManager.self) private var downloads
    @Environment(NetworkPolicy.self) private var network
    @State private var items: [Item] = []
    @State private var reachedEnd = false
    @State private var loading = false
    @State private var loadError: String?
    @State private var offline = false
    @State private var leadSwatches: [RGB] = []
    @State private var playbackItem: Item?
    @Namespace private var zoom

    private static let pageSize = 60

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.displaySmall)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    if offline {
                        offlineContent
                    } else {
                        grid(items) { _ in nil }
                    }
                }
            }
        }
        .paneConstrained()
        .background(Color.stage)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(itemId: item.id, fallbackTitle: item.title)
                .navigationTransition(.zoom(sourceID: item.id, in: zoom))
        }
        .fullScreenCover(item: $playbackItem) { playable in
            PlayerScreen(item: playable)
        }
        .overlay {
            if offline {
                EmptyView()
            } else if let loadError, items.isEmpty {
                ErrorState(message: loadError) {
                    Task { await loadNextPage() }
                }
            } else if loading && items.isEmpty {
                LoadingState()
            }
        }
        // Keyed on reach so walking back onto the LAN refills the grid from
        // Loom on its own.
        .task(id: network.reach) { await reload() }
    }

    /// The grid proper, shared by the online pages and the offline shelf.
    private func grid(_ items: [Item], badge: @escaping (Item) -> Int?) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    PosterCard(item: item, thread: thread, badgeCount: badge(item))
                }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: item.id, in: zoom)
                .contextMenu {
                    if item.isPlayable {
                        Button("Play", systemImage: "play.fill") { playbackItem = item }
                    }
                    // A write to Loom, which offline would only fail.
                    if !offline {
                        Button("Mark Watched", systemImage: "checkmark.circle") {
                            Task {
                                try? await appEnvironment.client?.setPlayed(id: item.id, true)
                                await reload()
                            }
                        }
                    }
                }
                .onAppear {
                    if !offline, item.id == items.last?.id {
                        Task { await loadNextPage() }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    /// Offline a library tab is the A-Z of what is on the device; a genre or a
    /// collection is a Loom query with nothing standing in for it.
    @ViewBuilder
    private var offlineContent: some View {
        switch source {
        case .library(let kind):
            let catalog = downloads.offlineCatalog
            let downloaded = catalog.library(kind)
            if downloaded.isEmpty {
                OfflineNotice(
                    reason: network.reason + " Nothing from here is downloaded to this device.",
                    onRetry: retry
                )
                .padding(.horizontal, 20)
            } else {
                OfflineBanner(reason: network.reason, onRetry: retry)
                    .padding(.horizontal, 20)
                grid(downloaded) { item in
                    // A show's snapshot counts episodes that are not on this
                    // device; what is left comes from the list itself.
                    item.kind == "show"
                        ? catalog.episodes(showId: item.id).filter { !($0.progress?.played ?? false) }.count
                        : nil
                }
            }
        case .genre, .collection:
            OfflineNotice(
                reason: network.reason + " Collections and genres come from Loom.",
                onRetry: retry
            )
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var background: some View {
        switch source {
        case .library:
            HouseLights(thread: thread)
        case .genre(let genre):
            ShadowWeave(swatches: leadSwatches, fallback: genreThread(genre.id))
        case .collection:
            ShadowWeave(swatches: leadSwatches, fallback: RGB(hexValue: 0xA78BFA))
        }
    }

    private var thread: Color {
        switch source {
        case .library(let kind): libraryThread(kind)
        case .genre(let genre): genreThread(genre.id).color
        case .collection: .violet
        }
    }

    private func retry() {
        network.recheck()
        Task { await reload() }
    }

    private func reload() async {
        items = []
        reachedEnd = false
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard !loading, !reachedEnd, let client = appEnvironment.client else { return }
        // A settled offline verdict is answered from the downloads without
        // spending a request that has nowhere to go.
        if network.reach == .offline {
            offline = true
            return
        }
        loading = true
        loadError = nil
        do {
            let page: [Item]
            switch source {
            case .library(let kind):
                page = try await client.items(library: kind, limit: Self.pageSize, offset: items.count).items
                reachedEnd = page.count < Self.pageSize
                // An item only carries its library's id, so this is the app's
                // one chance to learn which tab a download belongs in later.
                if items.isEmpty, let libraries = try? await client.libraries() {
                    downloads.updateLibraryKinds(libraries)
                }
            case .genre(let genre):
                page = try await client.items(genreId: genre.id, limit: Self.pageSize, offset: items.count).items
                reachedEnd = page.count < Self.pageSize
            case .collection(let collection):
                page = collection.items
                reachedEnd = true
            }
            items.append(contentsOf: page)
            offline = false
            await loadLeadSwatches()
        } catch {
            if isOfflineError(error) {
                network.markUnreachable()
                offline = true
            } else {
                loadError = error.localizedDescription
            }
        }
        loading = false
    }

    /// The lead poster's swatches drive the shadow weave on pushed grids.
    private func loadLeadSwatches() async {
        if case .library = source { return }
        guard leadSwatches.isEmpty, let lead = items.first,
              let url = appEnvironment.client?.imageURL(id: lead.posterImageId, tag: lead.posterImageTag, width: 240)
        else { return }
        leadSwatches = await WovenExtractor.threads(for: url)
    }
}
