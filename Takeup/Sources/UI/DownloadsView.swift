import SwiftUI

/// Downloaded and in-flight items under the violet thread. Works fully
/// offline: artwork comes from locally saved posters and playback uses the
/// local file.
struct DownloadsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(DownloadManager.self) private var downloads
    @State private var playbackItem: Item?

    var body: some View {
        ZStack {
            HouseLights(thread: .violet)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Downloads")
                        .font(.displaySmall)
                        .foregroundStyle(Color.ink)
                        .padding(.top, 16)

                    if !downloads.activeProgress.isEmpty {
                        RowLabel(text: "Downloading", color: .violet)
                            .padding(.top, 24)
                        ForEach(downloads.activeProgress.keys.sorted(), id: \.self) { itemId in
                            activeRow(itemId: itemId)
                        }
                    }

                    RowLabel(text: "Downloaded", color: .violet)
                        .padding(.top, 24)
                    if downloads.completed.isEmpty {
                        Text("Nothing downloaded yet. Use the download button on a movie or episode.")
                            .font(.bodyMedium)
                            .foregroundStyle(Color.muted)
                            .padding(.top, 12)
                    } else {
                        ForEach(downloads.completed) { entry in
                            completedRow(entry)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.stage)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playbackItem) { playable in
            PlayerScreen(item: playable)
        }
    }

    private func activeRow(itemId: Int64) -> some View {
        let title = downloads.pendingItems[itemId]?.title ?? "Item \(itemId)"
        let fraction = downloads.activeProgress[itemId] ?? 0
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.titleSmall)
                    .foregroundStyle(Color.ink)
                ThreadProgress(fraction: fraction, color: .violet)
            }
            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                .font(.labelLarge.monospacedDigit())
                .foregroundStyle(Color.muted)
            Button {
                downloads.cancel(itemId)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.muted)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
        }
        .padding(.vertical, 10)
    }

    private func completedRow(_ entry: DownloadEntry) -> some View {
        Button {
            playbackItem = entry.item
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Color.surface1
                    if let url = downloads.posterURL(for: entry.item.id) {
                        CachedImage(url: url, contentMode: .fill)
                    }
                }
                .frame(width: 50, height: 75)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.item.title)
                        .font(.titleSmall)
                        .foregroundStyle(Color.ink)
                    Text(subtitle(for: entry))
                        .font(.labelSmall)
                        .foregroundStyle(Color.muted)
                }
                Spacer()
                Image(systemName: "play.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.violet)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .contextMenu {
            Button("Play", systemImage: "play.fill") { playbackItem = entry.item }
            Button(role: .destructive) {
                downloads.remove(entry.item.id)
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        }
    }

    private func subtitle(for entry: DownloadEntry) -> String {
        var parts: [String] = []
        if let label = episodeLabel(entry.item) {
            parts.append(label)
        } else if let year = entry.item.year, year > 0 {
            parts.append(String(year))
        }
        parts.append(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
        return parts.joined(separator: " · ")
    }
}
