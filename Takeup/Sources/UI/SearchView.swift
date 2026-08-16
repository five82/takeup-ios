import SwiftUI

struct SearchView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var query = ""
    @State private var results: [Item] = []
    @State private var fuzzy = false
    @State private var searched = false

    var body: some View {
        ScrollView {
            if fuzzy && !results.isEmpty {
                Text("Showing close matches")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 24) {
                ForEach(results) { item in
                    NavigationLink(value: item) {
                        VStack(alignment: .leading, spacing: 6) {
                            PosterCell(item: item)
                            if let series = item.seriesTitle {
                                Text(series)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Search")
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(itemId: item.id, fallbackTitle: item.title)
        }
        .searchable(text: $query, prompt: "Titles, episodes, cast, crew")
        .overlay {
            if searched && results.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .task(id: query) {
            // Small debounce so we don't hit the server on every keystroke.
            try? await Task.sleep(for: .milliseconds(300))
            await search()
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client = appEnvironment.client, !trimmed.isEmpty else {
            results = []
            searched = false
            return
        }
        guard let response = try? await client.search(query: trimmed) else { return }
        results = response.items
        fuzzy = response.fuzzy ?? false
        searched = true
    }
}
