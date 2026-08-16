import SwiftUI

/// Downloaded and in-flight items. Works fully offline: artwork comes from
/// locally saved posters and playback uses the local file.
struct DownloadsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(DownloadManager.self) private var downloads
    @State private var playbackItem: Item?

    var body: some View {
        List {
            if !downloads.activeProgress.isEmpty {
                Section("Downloading") {
                    ForEach(downloads.activeProgress.keys.sorted(), id: \.self) { itemId in
                        activeRow(itemId: itemId)
                    }
                }
            }
            Section("Downloaded") {
                if downloads.completed.isEmpty {
                    Text("Nothing downloaded yet. Use the Download button on a movie or episode.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(downloads.completed) { entry in
                        completedRow(entry)
                    }
                }
            }
        }
        .navigationTitle("Downloads")
        .fullScreenCover(item: $playbackItem) { playable in
            PlayerScreen(item: playable)
        }
    }

    private func activeRow(itemId: Int64) -> some View {
        let title = downloads.pendingItems[itemId]?.title ?? "Item \(itemId)"
        let fraction = downloads.activeProgress[itemId] ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                ProgressView(value: fraction)
            }
            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                downloads.cancel(itemId)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func completedRow(_ entry: DownloadEntry) -> some View {
        Button {
            playbackItem = entry.item
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: downloads.posterURL(for: entry.item.id)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(width: 50, height: 75)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.item.title)
                        .font(.body.weight(.medium))
                    Text(subtitle(for: entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) {
                downloads.remove(entry.item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func subtitle(for entry: DownloadEntry) -> String {
        var parts: [String] = []
        if entry.item.kind == "episode",
           let season = entry.item.seasonNumber, let episode = entry.item.episodeNumber {
            parts.append("S\(season) E\(episode)")
        } else if let year = entry.item.year, year > 0 {
            parts.append(String(year))
        }
        parts.append(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
        return parts.joined(separator: " · ")
    }
}
