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
    @State private var items: [Item] = []
    @State private var reachedEnd = false
    @State private var loading = false
    @State private var loadError: String?
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                PosterCard(item: item, thread: thread)
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: item.id, in: zoom)
                            .contextMenu {
                                if item.isPlayable {
                                    Button("Play", systemImage: "play.fill") { playbackItem = item }
                                }
                                Button("Mark Watched", systemImage: "checkmark.circle") {
                                    Task {
                                        try? await appEnvironment.client?.setPlayed(id: item.id, true)
                                        await reload()
                                    }
                                }
                            }
                            .onAppear {
                                if item.id == items.last?.id {
                                    Task { await loadNextPage() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
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
            if let loadError, items.isEmpty {
                ErrorState(message: loadError) {
                    Task { await loadNextPage() }
                }
            } else if loading && items.isEmpty {
                LoadingState()
            }
        }
        .task { await loadNextPage() }
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

    private func reload() async {
        items = []
        reachedEnd = false
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard !loading, !reachedEnd, let client = appEnvironment.client else { return }
        loading = true
        loadError = nil
        do {
            let page: [Item]
            switch source {
            case .library(let kind):
                page = try await client.items(library: kind, limit: Self.pageSize, offset: items.count).items
                reachedEnd = page.count < Self.pageSize
            case .genre(let genre):
                page = try await client.items(genreId: genre.id, limit: Self.pageSize, offset: items.count).items
                reachedEnd = page.count < Self.pageSize
            case .collection(let collection):
                page = collection.items
                reachedEnd = true
            }
            items.append(contentsOf: page)
            await loadLeadSwatches()
        } catch {
            loadError = error.localizedDescription
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
