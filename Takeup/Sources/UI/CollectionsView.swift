import SwiftUI

/// Collections: backdrop-fronted cards under the violet thread.
struct CollectionsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(NetworkPolicy.self) private var network
    @State private var collections: [MediaCollection] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var offline = false
    @State private var leadSwatches: [RGB] = []

    var body: some View {
        ZStack {
            ShadowWeave(swatches: leadSwatches, fallback: RGB(hexValue: 0xA78BFA))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Collections")
                        .font(.displaySmall)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                    if offline {
                        // A collection is a Loom query; there is nothing on the
                        // device standing in for one.
                        OfflineNotice(
                            reason: network.reason + " Collections and genres come from Loom.",
                            onRetry: retry
                        )
                        .padding(.horizontal, 20)
                    } else {
                        grid
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color.stage)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(itemId: item.id, fallbackTitle: item.title)
        }
        .navigationDestination(for: MediaCollection.self) { collection in
            ItemGridView(source: .collection(collection), title: collection.title)
        }
        .overlay {
            if offline {
                EmptyView()
            } else if let loadError, collections.isEmpty {
                ErrorState(message: loadError) { Task { await load() } }
            } else if !loaded {
                LoadingState()
            }
        }
        .task(id: network.reach) { await load() }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
            ForEach(collections) { collection in
                NavigationLink(value: collection) {
                    card(collection)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private func card(_ collection: MediaCollection) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let url = coverURL(for: collection) {
                CachedImage(url: url, contentMode: .fill)
            } else {
                MissingArt(title: collection.title, tint: .violet)
            }
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: .stage.opacity(0.92), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.title)
                    .font(.labelLarge)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text("\(collection.items.count) films")
                    .font(.labelSmall)
                    .foregroundStyle(Color.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .hoverEffect(.lift)
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

    private func retry() {
        network.recheck()
        Task { await load() }
    }

    private func load() async {
        guard let client = appEnvironment.client else { return }
        if network.reach == .offline {
            offline = true
            loaded = true
            return
        }
        loadError = nil
        do {
            collections = try await client.collections()
            offline = false
            if let lead = collections.first?.items.first,
               let url = client.imageURL(id: lead.posterImageId, tag: lead.posterImageTag, width: 240) {
                leadSwatches = await WovenExtractor.threads(for: url)
            }
        } catch {
            if isOfflineError(error) {
                network.markUnreachable()
                offline = true
            } else {
                loadError = error.localizedDescription
            }
        }
        loaded = true
    }
}
