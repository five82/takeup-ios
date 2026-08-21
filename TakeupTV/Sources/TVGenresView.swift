import SwiftUI

/// Genres: the jewel-tile grid, its ambience woven from its own jewel
/// palette rather than any one artwork.
struct TVGenresView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var genres: [Genre] = []
    @State private var loaded = false
    @State private var loadError: String?

    var body: some View {
        ZStack {
            ShadowWeave(
                swatches: Array(genres.prefix(2).map { genreField($0.id) }),
                fallback: RGB(hexValue: 0xA78BFA)
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Genres")
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
        .navigationDestination(for: Genre.self) { genre in
            TVGridView(source: .genre(genre), title: genre.name)
        }
        .overlay {
            if let loadError, genres.isEmpty {
                ErrorState(message: loadError) { Task { await load() } }
            } else if !loaded {
                LoadingState()
            }
        }
        .task { await load() }
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 400), spacing: TVLayout.cardSpacing)],
            spacing: TVLayout.cardSpacing
        ) {
            ForEach(genres) { genre in
                NavigationLink(value: genre) {
                    tile(genre)
                }
                .buttonStyle(.card)
            }
        }
        .padding(.horizontal, TVLayout.sideMargin)
        .padding(.vertical, 30)
    }

    private func tile(_ genre: Genre) -> some View {
        let field = genreField(genre.id)
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [field.color, field.darkened(0.55).color],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: symbol(genre.id))
                .font(.system(size: 64, weight: .medium))
                .foregroundStyle(Color.ink.opacity(0.30))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(16)
            HStack(alignment: .firstTextBaseline) {
                Text(genre.name)
                    .font(.labelLarge)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if let count = genre.itemCount {
                    Text(String(count))
                        .font(.labelSmall)
                        .foregroundStyle(Color.ink.opacity(0.7))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .aspectRatio(2.05, contentMode: .fit)
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

    private func load() async {
        guard let client = appEnvironment.client else { return }
        loadError = nil
        do {
            genres = try await client.genres()
        } catch {
            loadError = error.localizedDescription
        }
        loaded = true
    }
}
