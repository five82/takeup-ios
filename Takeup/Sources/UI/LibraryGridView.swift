import SwiftUI

/// Paged poster grid for one Loom library. Loom returns no total count,
/// so the end of the library is detected by a short page.
struct LibraryGridView: View {
    let libraryKind: String
    let title: String

    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var items: [Item] = []
    @State private var reachedEnd = false
    @State private var loading = false
    @State private var loadError: String?

    private static let pageSize = 60

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 24) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        PosterCell(item: item)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if item.id == items.last?.id {
                            Task { await loadNextPage() }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(itemId: item.id, fallbackTitle: item.title)
        }
        .overlay {
            if let loadError, items.isEmpty {
                ContentUnavailableView {
                    Label("Can't Reach Loom", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Retry") {
                        Task { await loadNextPage() }
                    }
                }
            } else if loading && items.isEmpty {
                ProgressView()
            }
        }
        .task { await loadNextPage() }
    }

    private func loadNextPage() async {
        guard !loading, !reachedEnd, let client = appEnvironment.client else { return }
        loading = true
        loadError = nil
        do {
            let page = try await client.items(library: libraryKind, limit: Self.pageSize, offset: items.count)
            items.append(contentsOf: page.items)
            reachedEnd = page.items.count < Self.pageSize
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }
}

struct PosterCell: View {
    let item: Item

    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: appEnvironment.client?.imageURL(id: item.posterImageId, tag: item.posterImageTag, width: 480)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                }
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(item.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            if let year = item.year, year > 0 {
                Text(String(year))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
