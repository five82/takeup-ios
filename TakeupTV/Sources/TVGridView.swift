import SwiftUI

/// Poster grid over /items: the full A-Z of a library, a genre, or a
/// collection's members. Loom returns no total count, so the end is detected
/// by a short page. Library tabs get their thread's house lights; pushed
/// genre/collection grids get the lead poster's shadow weave.
struct TVGridView: View {
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

    private static let pageSize = 60

    var body: some View {
        ZStack {
            background
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(title)
                        .font(.displaySmall)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, TVLayout.sideMargin)
                        .padding(.top, TVLayout.verticalMargin)
                    grid
                }
                .padding(.bottom, TVLayout.verticalMargin)
            }
        }
        .background(Color.stage)
        .navigationDestination(for: Item.self) { item in
            TVDetailView(itemId: item.id, fallbackTitle: item.title)
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
        .task { await reload() }
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: TVLayout.posterWidth), spacing: TVLayout.cardSpacing)],
            spacing: 48
        ) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    TVPosterCard(item: item, thread: thread)
                }
                .buttonStyle(.card)
                .onAppear {
                    if item.id == items.last?.id {
                        Task { await loadNextPage() }
                    }
                }
            }
        }
        .padding(.horizontal, TVLayout.sideMargin)
        .padding(.vertical, 30)
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
