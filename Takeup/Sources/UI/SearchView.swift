import SwiftUI

/// Search under ember house lights. Mixed-kind results read as rows: a small
/// poster, the title, its context line, and a kind tag.
struct SearchView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var query = ""
    @State private var results: [Item] = []
    @State private var fuzzy = false
    @State private var searched = false

    var body: some View {
        ZStack {
            HouseLights(thread: .ember)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if fuzzy && !results.isEmpty {
                        Text("Closest matches")
                            .font(.labelLarge)
                            .foregroundStyle(Color.muted)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                    ForEach(results) { item in
                        NavigationLink(value: item) {
                            resultRow(item)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color.stage)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(itemId: item.id, fallbackTitle: item.title)
        }
        .searchable(text: $query, prompt: "Titles and people")
        .overlay {
            if searched && results.isEmpty && !query.isEmpty {
                EmptyState(message: "Nothing in the library matches \"\(query)\".")
            }
        }
        .task(id: query) {
            // Small debounce so we don't hit the server on every keystroke.
            try? await Task.sleep(for: .milliseconds(300))
            await search()
        }
    }

    private func resultRow(_ item: Item) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Color.surface1
                if let url = appEnvironment.client?.imageURL(id: item.posterImageId, tag: item.posterImageTag, width: 240) {
                    CachedImage(url: url, contentMode: .fill)
                }
            }
            .frame(width: 52, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.titleMedium)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                if let context = contextLine(item) {
                    Text(context)
                        .font(.bodySmall)
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            KindTag(kind: item.kind)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func contextLine(_ item: Item) -> String? {
        if item.kind == "episode" {
            return [item.seriesTitle, episodeLabel(item)].compactMap { $0 }.joined(separator: " · ")
        }
        if let year = item.year, year > 0 { return String(year) }
        return nil
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
