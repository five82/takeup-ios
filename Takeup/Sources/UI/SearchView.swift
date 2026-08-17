import SwiftUI

/// Search under ember house lights. Mixed-kind results read as rows: a small
/// poster, the title, its context line, and a kind tag.
struct SearchView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(DownloadManager.self) private var downloads
    @Environment(NetworkPolicy.self) private var network
    @State private var query: String
    @State private var results: [Item] = []
    @State private var fuzzy = false
    @State private var searched = false
    @State private var offline = false

    /// A non-empty initial query makes this a pushed person search (from a
    /// cast card) rather than the sidebar's blank search root.
    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        ZStack {
            HouseLights(thread: .ember)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if offline {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.amber)
                                .frame(width: 6, height: 6)
                            Text("Offline · searching what is downloaded on this device")
                                .font(.labelLarge)
                                .foregroundStyle(Color.muted)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    }
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
        .paneConstrained()
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
                EmptyState(
                    message: offline
                        ? "Nothing downloaded to this device matches \"\(query)\"."
                        : "Nothing in the library matches \"\(query)\"."
                )
            }
        }
        .task(id: query) {
            // Small debounce so we don't hit the server on every keystroke.
            try? await Task.sleep(for: .milliseconds(300))
            await search()
        }
        // Walking back onto the LAN re-runs the same query against Loom.
        .task(id: network.reach) { await search() }
    }

    private func resultRow(_ item: Item) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Color.surface1
                if let url = posterURL(item) {
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

    private func posterURL(_ item: Item) -> URL? {
        if offline { return downloads.posterURL(for: item.id) }
        return appEnvironment.client?.imageURL(id: item.posterImageId, tag: item.posterImageTag, width: 240)
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client = appEnvironment.client, !trimmed.isEmpty else {
            results = []
            searched = false
            offline = network.reach == .offline
            return
        }
        // A settled offline verdict searches the downloads rather than
        // spending a request that has nowhere to go.
        if network.reach == .offline {
            searchOffline(trimmed)
            return
        }
        do {
            let response = try await client.search(query: trimmed)
            results = response.items
            fuzzy = response.fuzzy ?? false
            offline = false
            searched = true
        } catch {
            if isOfflineError(error) {
                network.markUnreachable()
                searchOffline(trimmed)
            }
        }
    }

    private func searchOffline(_ trimmed: String) {
        offline = true
        fuzzy = false
        results = downloads.offlineCatalog.search(trimmed)
        searched = true
    }
}
