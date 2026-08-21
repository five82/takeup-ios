import SwiftUI

/// The device's download workspace. Completed files remain playable offline;
/// queued, running, and failed work stays here until the user resolves it.
struct DownloadsView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(DownloadManager.self) private var downloads
    @Environment(NetworkPolicy.self) private var network
    @State private var playbackItem: Item?
    @State private var removalEntry: DownloadEntry?
    @State private var showRemovalConfirmation = false
    @State private var showRemoveAllConfirmation = false

    var body: some View {
        ZStack {
            HouseLights(thread: .violet)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if !downloads.activeProgress.isEmpty || !downloads.failedItems.isEmpty {
                        RowLabel(text: "Active", color: .violet)
                            .padding(.top, 28)
                        ForEach(activeItems, id: \.id) { item in
                            activeRow(item)
                        }
                        ForEach(failedItems, id: \.id) { item in
                            failedRow(item)
                        }
                    }

                    RowLabel(text: "On this iPad", color: .violet)
                        .padding(.top, 28)
                    if downloads.completed.isEmpty {
                        Text(emptyMessage)
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
        .paneConstrained()
        .background(Color.stage)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playbackItem) { playable in
            PlayerScreen(item: playable)
        }
        .alert("Remove \(removalEntry?.item.title ?? "download")?", isPresented: $showRemovalConfirmation) {
            Button("Remove", role: .destructive) {
                if let removalEntry { downloads.remove(removalEntry.item.id) }
                removalEntry = nil
            }
            Button("Keep", role: .cancel) { removalEntry = nil }
        } message: {
            if let removalEntry {
                Text("Remove \(ByteCountFormatter.string(fromByteCount: removalEntry.size, countStyle: .file)) from this iPad? It will no longer play offline.")
            }
        }
        .alert("Remove all downloads?", isPresented: $showRemoveAllConfirmation) {
            Button("Remove all", role: .destructive) { downloads.removeAll() }
            Button("Keep", role: .cancel) { }
        } message: {
            Text("Remove or cancel \(downloads.totalManagedCount) \(downloads.totalManagedCount == 1 ? "download" : "downloads") and free \(ByteCountFormatter.string(fromByteCount: downloads.completedBytesUsed, countStyle: .file))? Completed titles will no longer play offline.")
        }
    }

    private var header: some View {
        let summary = downloads.summary
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Downloads")
                    .font(.displaySmall)
                    .foregroundStyle(Color.ink)
                Spacer()
                if summary.totalManagedCount > 0 {
                    Button("Remove all…", role: .destructive) {
                        showRemoveAllConfirmation = true
                    }
                    .font(.labelLarge)
                    .foregroundStyle(Color.violet)
                    .buttonStyle(.plain)
                }
            }
            Text(summaryLine(summary))
                .font(.bodyMedium)
                .foregroundStyle(Color.muted)
            Text(spaceLine(summary))
                .font(.labelSmall)
                .foregroundStyle(Color.muted)
        }
        .padding(.top, 16)
    }

    private var activeItems: [Item] {
        downloads.activeProgress.keys.compactMap { downloads.pendingItems[$0] }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var failedItems: [Item] {
        downloads.failedItems.values.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private var emptyMessage: String {
        downloads.totalManagedCount == 0
            ? "Nothing downloaded yet. Use the download button on a movie or episode."
            : "No completed downloads yet."
    }

    private func activeRow(_ item: Item) -> some View {
        let fraction = downloads.activeProgress[item.id] ?? 0
        return managementRow(item: item) {
            VStack(alignment: .leading, spacing: 7) {
                Text((fraction == 0 ? "Queued" : "Downloading · \(fraction.formatted(.percent.precision(.fractionLength(0))))") + transferSizeSuffix(item))
                    .font(.labelSmall)
                    .foregroundStyle(Color.muted)
                ThreadProgress(fraction: fraction, color: .violet)
            }
        } actions: {
            Button("Cancel") { downloads.cancel(item.id) }
                .buttonStyle(DownloadActionStyle(tint: .muted))
        }
    }

    private func failedRow(_ item: Item) -> some View {
        managementRow(item: item) {
            Text("Download failed" + transferSizeSuffix(item))
                .font(.labelSmall)
                .foregroundStyle(Color.ember)
        } actions: {
            Button("Retry") {
                guard let client = appEnvironment.client else { return }
                Task { await downloads.start(item: item, client: client) }
            }
            .buttonStyle(DownloadActionStyle(tint: .violet))
            .disabled(network.reach == .offline || appEnvironment.client == nil)
        }
    }

    private func completedRow(_ entry: DownloadEntry) -> some View {
        managementRow(item: entry.item) {
            Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                .font(.labelSmall)
                .foregroundStyle(Color.muted)
        } actions: {
            Button("Play") { playbackItem = entry.item }
                .buttonStyle(DownloadActionStyle(tint: .violet))
            Button("Remove") { confirmRemoval(entry) }
                .buttonStyle(DownloadActionStyle(tint: .muted))
        }
        .contextMenu {
            Button("Play", systemImage: "play.fill") { playbackItem = entry.item }
            Button(role: .destructive) { confirmRemoval(entry) } label: {
                Label("Remove Download", systemImage: "trash")
            }
        }
    }

    private func managementRow<Detail: View, Actions: View>(
        item: Item,
        @ViewBuilder detail: () -> Detail,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Color.surface1
                if let url = downloads.posterURL(for: item.id) {
                    CachedImage(url: url, contentMode: .fill)
                } else {
                    MissingArt(title: item.title, tint: .violet)
                }
            }
            .frame(width: 54, height: 81)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.titleSmall)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                if let context = itemContext(item) {
                    Text(context)
                        .font(.labelSmall)
                        .foregroundStyle(Color.muted)
                }
                detail()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) { actions() }
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.line).frame(height: 1) }
    }

    private func confirmRemoval(_ entry: DownloadEntry) {
        removalEntry = entry
        showRemovalConfirmation = true
    }

    private func summaryLine(_ summary: DownloadSummary) -> String {
        var parts = ["\(summary.readyCount) ready", "\(summary.activeCount) active"]
        if summary.failedCount > 0 {
            parts.append("\(summary.failedCount) failed")
        }
        return parts.joined(separator: " · ")
    }

    private func spaceLine(_ summary: DownloadSummary) -> String {
        let used = ByteCountFormatter.string(fromByteCount: summary.occupiedBytes, countStyle: .file)
        if let free = summary.freeBytes {
            return "\(used) used · \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free on this iPad"
        }
        return "\(used) used on this iPad"
    }

    private func itemContext(_ item: Item) -> String? {
        if let label = episodeLabel(item) { return label }
        if let year = item.year, year > 0 { return String(year) }
        return nil
    }

    private func transferSizeSuffix(_ item: Item) -> String {
        guard let size = item.media?.size, size > 0 else { return "" }
        return " · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
    }

}

private struct DownloadActionStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.labelSmall)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(tint.opacity(configuration.isPressed ? 0.22 : 0.12), in: Capsule())
    }
}
