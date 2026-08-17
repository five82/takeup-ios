import SwiftUI

/// Genres: the jewel-tile grid, its ambience woven from its own jewel
/// palette rather than any one artwork.
struct GenresView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(NetworkPolicy.self) private var network
    @State private var genres: [Genre] = []
    @State private var loaded = false
    @State private var loadError: String?
    @State private var offline = false

    var body: some View {
        ZStack {
            ShadowWeave(
                swatches: Array(genres.prefix(2).map { genreField($0.id) }),
                fallback: RGB(hexValue: 0xA78BFA)
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Genres")
                        .font(.displaySmall)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                    if offline {
                        // A genre is a Loom query; there is nothing on the
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
        .navigationDestination(for: Genre.self) { genre in
            ItemGridView(source: .genre(genre), title: genre.name)
        }
        .overlay {
            if offline {
                EmptyView()
            } else if let loadError, genres.isEmpty {
                ErrorState(message: loadError) { Task { await load() } }
            } else if !loaded {
                LoadingState()
            }
        }
        .task(id: network.reach) { await load() }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
            ForEach(genres) { genre in
                NavigationLink(value: genre) {
                    tile(genre)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private func tile(_ genre: Genre) -> some View {
        let field = genreField(genre.id)
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [field.color, field.darkened(0.55).color],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: symbol(genre.id))
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

    private func symbol(_ id: Int64) -> String {
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
            genres = try await client.genres()
            offline = false
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
