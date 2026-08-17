import SwiftUI

// The two card shapes. Depth comes from background light, not drop shadows —
// no card in the app has one. Posters carry no captions: the poster is the
// label, and only the MissingArt fallback shows a title.

struct PosterCard: View {
    let item: Item
    /// Badge, progress, and missing-art tint — the screen's thread color.
    var thread: Color = .ember
    /// Overrides the item's own unwatched tally. Offline a show's snapshot
    /// counts episodes that are not on this device, so the caller recounts
    /// from what actually is.
    var badgeCount: Int?

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(DownloadManager.self) private var downloads
    @Environment(NetworkPolicy.self) private var network

    var body: some View {
        ZStack {
            if let url = posterURL {
                CachedImage(url: url, contentMode: .fill)
            } else {
                MissingArt(title: item.title, tint: thread)
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if let unwatched = badgeCount ?? item.unwatchedCount, unwatched > 0 {
                BobbinBadge(count: unwatched, color: thread)
                    .padding(6)
            }
        }
        .overlay(alignment: .bottom) {
            if let fraction = progressFraction(item) {
                ThreadProgress(fraction: fraction, color: thread)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .hoverEffect(.lift)
    }

    private var posterURL: URL? {
        // Offline the poster is a file beside the download; a Loom URL would
        // only spend the fetch to fail.
        if network.reach == .offline {
            return downloads.posterURL(for: item.id)
        }
        if let url = appEnvironment.client?.imageURL(id: item.posterImageId, tag: item.posterImageTag, width: 480) {
            return url
        }
        // No server configured: the poster saved beside the download.
        return downloads.posterURL(for: item.id)
    }
}

/// 16:9 card for Continue Watching / Next Up. Loom's thumb art has the title
/// baked in, so the single line beneath carries context, not identity.
struct ThumbCard: View {
    let item: Item
    var caption: String?
    var thread: Color = .ember
    var width: CGFloat = 240

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(DownloadManager.self) private var downloads
    @Environment(NetworkPolicy.self) private var network

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Color.surface1
                if let url = thumbURL {
                    CachedImage(url: url, contentMode: .fill)
                } else {
                    MissingArt(title: item.title, tint: thread)
                }
            }
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottom) {
                if let fraction = progressFraction(item) {
                    ThreadProgress(fraction: fraction, color: thread)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            }
            .hoverEffect(.lift)

            if let caption {
                Text(caption)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.muted)
                    .lineLimit(2)
                    .padding(.leading, 2)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    /// Offline the screencap saved beside the download, falling back to the
    /// poster: a cropped poster still says which title this is.
    private var thumbURL: URL? {
        if network.reach == .offline {
            return downloads.artworkURL(for: item.id, kind: .thumb) ?? downloads.posterURL(for: item.id)
        }
        return appEnvironment.client?.imageURL(id: item.thumbImageId, tag: item.thumbImageTag, width: 480)
    }
}
