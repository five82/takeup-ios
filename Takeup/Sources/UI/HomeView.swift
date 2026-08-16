import SwiftUI

/// Discovery rows mirroring the Android app's home screen:
/// Continue Watching, Next Up, Recently Added, Recently Played.
struct HomeView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var continueWatching: [Item] = []
    @State private var nextUp: [Item] = []
    @State private var recentlyAdded: [Item] = []
    @State private var recentlyPlayed: [Item] = []
    @State private var loaded = false
    @State private var playbackItem: Item?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if !continueWatching.isEmpty {
                    MediaRow(title: "Continue Watching", items: continueWatching, style: .thumb) { playbackItem = $0 }
                }
                if !nextUp.isEmpty {
                    MediaRow(title: "Next Up", items: nextUp, style: .thumb) { playbackItem = $0 }
                }
                if !recentlyAdded.isEmpty {
                    MediaRow(title: "Recently Added", items: recentlyAdded, style: .poster, onPlay: nil)
                }
                if !recentlyPlayed.isEmpty {
                    MediaRow(title: "Recently Played", items: recentlyPlayed, style: .poster, onPlay: nil)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Home")
        .navigationDestination(for: Item.self) { item in
            ItemDetailView(itemId: item.id, fallbackTitle: item.title)
        }
        .fullScreenCover(item: $playbackItem, onDismiss: { Task { await load() } }) { playable in
            PlayerScreen(item: playable)
        }
        .overlay {
            if !loaded {
                ProgressView()
            } else if continueWatching.isEmpty && nextUp.isEmpty && recentlyAdded.isEmpty && recentlyPlayed.isEmpty {
                ContentUnavailableView("Nothing Here Yet", systemImage: "popcorn", description: Text("Play something and it will show up here."))
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let client = appEnvironment.client else { return }
        async let continueWatchingPage = client.continueWatching()
        async let nextUpPage = client.nextUp()
        async let recentlyAddedPage = client.recentlyAdded()
        async let recentlyPlayedPage = client.recentlyPlayed()
        continueWatching = (try? await continueWatchingPage.items) ?? []
        nextUp = (try? await nextUpPage.items) ?? []
        recentlyAdded = (try? await recentlyAddedPage.items) ?? []
        recentlyPlayed = (try? await recentlyPlayedPage.items) ?? []
        loaded = true
    }
}

struct MediaRow: View {
    enum Style {
        case poster, thumb
    }

    let title: String
    let items: [Item]
    let style: Style
    let onPlay: ((Item) -> Void)?

    init(title: String, items: [Item], style: Style, onPlay: ((Item) -> Void)?) {
        self.title = title
        self.items = items
        self.style = style
        self.onPlay = onPlay
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.semibold))
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        if style == .thumb, let onPlay {
                            Button {
                                onPlay(item)
                            } label: {
                                ThumbCard(item: item)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(value: item) {
                                PosterCell(item: item)
                                    .frame(width: 150)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

/// Landscape card with playback progress, used for Continue Watching / Next Up.
struct ThumbCard: View {
    let item: Item

    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: appEnvironment.client?.imageURL(id: item.thumbImageId, tag: item.thumbImageTag, width: 480)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "play.rectangle")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 280, height: 157)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottom) {
                if let progress = item.progress,
                   let position = progress.resumePositionMs, position > 0,
                   let duration = progress.durationMs, duration > 0 {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(.tint)
                            .frame(width: proxy.size.width * CGFloat(position) / CGFloat(duration))
                    }
                    .frame(height: 4)
                    .background(.white.opacity(0.3))
                    .clipShape(Capsule())
                    .padding(8)
                }
            }
            .overlay {
                Image(systemName: "play.fill")
                    .font(.title)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
                    .opacity(0.9)
            }

            Text(item.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 280)
    }

    private var subtitle: String {
        if item.kind == "episode", let season = item.seasonNumber, let episode = item.episodeNumber {
            return "S\(season) E\(episode)"
        }
        if let year = item.year, year > 0 {
            return String(year)
        }
        return " "
    }
}
