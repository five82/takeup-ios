import SwiftUI

/// Collections and genres, mirroring the Android app's Browse screen.
struct BrowseView: View {
    private enum Mode: String, CaseIterable {
        case collections = "Collections"
        case genres = "Genres"
    }

    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var mode: Mode = .collections
    @State private var collections: [MediaCollection] = []
    @State private var genres: [Genre] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                switch mode {
                case .collections:
                    ForEach(collections) { collection in
                        MediaRow(title: collection.title, items: collection.items, style: .poster, onPlay: nil)
                    }
                case .genres:
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(genres) { genre in
                            NavigationLink(value: genre) {
                                HStack {
                                    Text(genre.name)
                                        .font(.body.weight(.medium))
                                    Spacer()
                                    if let count = genre.itemCount {
                                        Text(String(count))
                                            .foregroundStyle(.secondary)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding()
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Browse")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
        }
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(itemId: item.id, fallbackTitle: item.title)
        }
        .navigationDestination(for: Genre.self) { genre in
            ItemGridView(source: .genre(genre), title: genre.name)
        }
        .overlay {
            if !loaded {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let client = appEnvironment.client else { return }
        async let collectionsResult = client.collections()
        async let genresResult = client.genres()
        collections = (try? await collectionsResult) ?? []
        genres = (try? await genresResult) ?? []
        loaded = true
    }
}
