import SwiftUI

/// Collections: backdrop-fronted cards under the violet thread.
struct TVCollectionsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var collections: [MediaCollection] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var leadSwatches: [RGB] = []

    var body: some View {
        ZStack {
            ShadowWeave(swatches: leadSwatches, fallback: RGB(hexValue: 0xA78BFA))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Collections")
                        .font(.displaySmall)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, TVLayout.sideMargin)
                        .padding(.top, TVLayout.verticalMargin)
                    grid
                }
                .padding(.bottom, TVLayout.verticalMargin)
            }
        }
        // sideMargin is the overscan gutter measured from the screen edge;
        // stacked on the system inset it would double to ~160pt.
        .ignoresSafeArea(.container, edges: .horizontal)
        .background(Color.stage)
        .navigationDestination(for: Item.self) { item in
            TVDetailView(itemId: item.id, fallbackTitle: item.title)
        }
        .navigationDestination(for: MediaCollection.self) { collection in
            TVGridView(source: .collection(collection), title: collection.title)
        }
        .overlay {
            if let loadError, collections.isEmpty {
                ErrorState(message: loadError) { Task { await load() } }
            } else if !loaded {
                LoadingState()
            }
        }
        .task { await load() }
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 420), spacing: TVLayout.cardSpacing)],
            spacing: 48
        ) {
            ForEach(collections) { collection in
                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink(value: collection) {
                        card(collection)
                    }
                    .buttonStyle(.card)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(collection.title)
                            .font(.titleSmall)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                        Text("\(collection.items.count) films")
                            .font(.labelSmall)
                            .foregroundStyle(Color.muted)
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .padding(.horizontal, TVLayout.sideMargin)
        .padding(.vertical, 30)
    }

    private func card(_ collection: MediaCollection) -> some View {
        ZStack {
            if let url = coverURL(for: collection) {
                CachedImage(url: url, contentMode: .fill)
            } else {
                MissingArt(title: collection.title, tint: .violet)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
    }

    /// A member's backdrop fronts each collection, deduped so collections
    /// sharing an opening chapter (Spielberg and Indiana Jones both start
    /// with Raiders) don't show the same frame.
    private func coverURL(for collection: MediaCollection) -> URL? {
        var used = Set<Int64>()
        for other in collections {
            if other.slug == collection.slug { break }
            if let face = collectionFace(other, excluding: []) {
                used.insert(face)
            }
        }
        guard let face = collectionFace(collection, excluding: used) else { return nil }
        return appEnvironment.client?.imageURL(id: face, tag: nil, width: 480)
    }

    private func collectionFace(_ collection: MediaCollection, excluding used: Set<Int64>) -> Int64? {
        let backdrops = collection.items.compactMap(\.backdropImageId)
        return backdrops.first { !used.contains($0) } ?? backdrops.first
    }

    private func load() async {
        guard let client = appEnvironment.client else { return }
        loadError = nil
        do {
            collections = try await client.collections()
            if let lead = collections.first?.items.first,
               let url = client.imageURL(id: lead.posterImageId, tag: lead.posterImageTag, width: 240) {
                leadSwatches = await WovenExtractor.threads(for: url)
            }
        } catch {
            loadError = error.localizedDescription
        }
        loaded = true
    }
}
