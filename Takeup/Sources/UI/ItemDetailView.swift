import SwiftUI

/// Detail screen for any item kind. Movies and episodes get a play button;
/// shows and seasons list their children and navigate deeper.
struct ItemDetailView: View {
    let itemId: Int64
    let fallbackTitle: String

    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var item: Item?
    @State private var childItems: [Item] = []
    @State private var loadError: String?
    @State private var playbackItem: Item?

    var body: some View {
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: 16) {
                    header(for: item)
                    if item.isPlayable {
                        playButton(for: item)
                    }
                    metadata(for: item)
                    if let overview = item.overview {
                        Text(overview)
                            .font(.body)
                    }
                    if !childItems.isEmpty {
                        childList(for: item)
                    }
                }
                .padding()
            } else if let loadError {
                ContentUnavailableView("Couldn't Load", systemImage: "exclamationmark.triangle", description: Text(loadError))
                    .padding(.top, 120)
            } else {
                ProgressView()
                    .padding(.top, 120)
            }
        }
        .navigationTitle(item?.title ?? fallbackTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Item.self) { child in
            ItemDetailView(itemId: child.id, fallbackTitle: child.title)
        }
        .fullScreenCover(item: $playbackItem) { playable in
            PlayerScreen(item: playable)
        }
        .task(id: itemId) { await load() }
    }

    private func load() async {
        guard let client = appEnvironment.client else { return }
        do {
            let loaded = try await client.item(id: itemId)
            item = loaded
            if loaded.kind == "show" || loaded.kind == "season" {
                childItems = try await client.children(of: itemId).items
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func header(for item: Item) -> some View {
        AsyncImage(url: appEnvironment.client?.imageURL(id: item.backdropImageId, tag: item.backdropImageTag, width: 1440)) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(.quaternary)
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func playButton(for item: Item) -> some View {
        let resumeMs = item.progress?.resumePositionMs ?? 0
        Button {
            playbackItem = item
        } label: {
            Label(
                resumeMs > 0 ? "Resume from \(formatDuration(resumeMs))" : "Play",
                systemImage: "play.fill"
            )
            .font(.headline)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
    }

    @ViewBuilder
    private func metadata(for item: Item) -> some View {
        HStack(spacing: 12) {
            if let year = item.year, year > 0 { Text(String(year)) }
            if let rating = item.contentRating { Text(rating).padding(.horizontal, 6).overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary)) }
            if let duration = item.durationMs, duration > 0 { Text(formatDuration(duration)) }
            if let vote = item.voteAverage, vote > 0 { Label(String(format: "%.1f", vote), systemImage: "star.fill") }
            if let genres = item.genres, !genres.isEmpty {
                Text(genres.map(\.name).joined(separator: " · "))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func childList(for item: Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.kind == "show" ? "Seasons" : "Episodes")
                .font(.title3.weight(.semibold))
            ForEach(childItems) { child in
                if child.isPlayable {
                    Button {
                        playbackItem = child
                    } label: {
                        childRow(child)
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(value: child) {
                        childRow(child)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func childRow(_ child: Item) -> some View {
        HStack(spacing: 12) {
            if child.isPlayable {
                Image(systemName: (child.progress?.played ?? false) ? "checkmark.circle.fill" : "play.circle")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            VStack(alignment: .leading) {
                Text(childTitle(child))
                    .font(.body.weight(.medium))
                if let duration = child.durationMs, duration > 0 {
                    Text(formatDuration(duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !child.isPlayable {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func childTitle(_ child: Item) -> String {
        if let number = child.episodeNumber, number > 0 {
            return "\(number). \(child.title)"
        }
        return child.title
    }
}

func formatDuration(_ milliseconds: Int64) -> String {
    let totalMinutes = Int(milliseconds / 60_000)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
}
