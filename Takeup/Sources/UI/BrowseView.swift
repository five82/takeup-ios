import SwiftUI

/// Browse: two rooms, Collections and Genres, under the violet thread.
struct BrowseView: View {
    private enum Room: String, CaseIterable {
        case collections = "Collections"
        case genres = "Genres"
    }

    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var room: Room = .collections
    @State private var collections: [MediaCollection] = []
    @State private var genres: [Genre] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var leadSwatches: [RGB] = []

    var body: some View {
        ZStack {
            ShadowWeave(swatches: leadSwatches, fallback: RGB(hexValue: 0xA78BFA))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Browse")
                        .font(.displaySmall)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    HStack(spacing: 8) {
                        ForEach(Room.allCases, id: \.self) { candidate in
                            roomPill(candidate)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                    switch room {
                    case .collections: collectionsGrid
                    case .genres: genresGrid
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
        .navigationDestination(for: Genre.self) { genre in
            ItemGridView(source: .genre(genre), title: genre.name)
        }
        .navigationDestination(for: MediaCollection.self) { collection in
            ItemGridView(source: .collection(collection), title: collection.title)
        }
        .overlay {
            if let loadError, collections.isEmpty && genres.isEmpty {
                ErrorState(message: loadError) { Task { await load() } }
            } else if !loaded {
                LoadingState()
            }
        }
        .task { await load() }
    }

    private func roomPill(_ candidate: Room) -> some View {
        let active = room == candidate
        return Button {
            room = candidate
        } label: {
            Text(candidate.rawValue)
                .font(.labelLarge)
                .foregroundStyle(active ? Color.stage : Color.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    if active {
                        Capsule().fill(Color.violet)
                    } else {
                        Capsule().stroke(Color.line, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    // MARK: - Collections

    private var collectionsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
            ForEach(collections) { collection in
                NavigationLink(value: collection) {
                    collectionCard(collection)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private func collectionCard(_ collection: MediaCollection) -> some View {
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

    // MARK: - Genres

    private var genresGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
            ForEach(genres) { genre in
                NavigationLink(value: genre) {
                    genreTile(genre)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private func genreTile(_ genre: Genre) -> some View {
        let field = genreField(genre.id)
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [field.color, field.darkened(0.55).color],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: genreSymbol(genre.id))
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Color.ink.opacity(0.30))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(8)
            HStack(alignment: .firstTextBaseline) {
                Text(genre.name)
                    .font(.labelLarge)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let count = genre.itemCount {
                    Text(String(count))
                        .font(.labelSmall)
                        .foregroundStyle(Color.ink.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .aspectRatio(2.05, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .hoverEffect(.lift)
    }

    private func genreSymbol(_ id: Int64) -> String {
        switch id {
        case 28: "bolt.fill"                              // Action
        case 12: "mountain.2.fill"                        // Adventure
        case 16: "sparkles"                               // Animation
        case 35: "theatermasks.fill"                      // Comedy
        case 80: "touchid"                                // Crime
        case 99: "video.fill"                             // Documentary
        case 18: "film.fill"                              // Drama
        case 10751: "figure.2.and.child.holdinghands"     // Family
        case 14: "wand.and.stars"                         // Fantasy
        case 36: "building.columns.fill"                  // History
        case 27: "moon.fill"                              // Horror
        case 10402: "music.note"                          // Music
        case 9648: "magnifyingglass"                      // Mystery
        case 10749: "heart.fill"                          // Romance
        case 878: "atom"                                  // Science Fiction
        case 53: "eye.fill"                               // Thriller
        case 10770: "tv.fill"                             // TV Movie
        case 10752: "medal.fill"                          // War
        case 37: "tent.fill"                              // Western
        default: "square.grid.2x2"
        }
    }

    // MARK: - Data

    private func load() async {
        guard let client = appEnvironment.client else { return }
        loadError = nil
        async let collectionsResult = client.collections()
        async let genresResult = client.genres()
        do {
            collections = try await collectionsResult
            genres = try await genresResult
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
