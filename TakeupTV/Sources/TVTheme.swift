import SwiftUI

// TV-specific layout constants and focus treatments. The palette, type scale,
// and light treatments come from Shared/UI/Theme; what is new here is how the
// focus engine plays the role the iPad's pointer and fingers play.

/// The overscan-safe margins: content keeps 80pt from the sides and 60pt from
/// the top and bottom, per the tvOS layout guidance.
enum TVLayout {
    static let sideMargin: CGFloat = 80
    static let verticalMargin: CGFloat = 60
    static let posterWidth: CGFloat = 220
    static let thumbWidth: CGFloat = 400
    static let cardSpacing: CGFloat = 36
    static let rowSpacing: CGFloat = 44
}

/// Focus-aware capsule for pills and chips: the fill brightens to the given
/// color under focus and the text flips to its on-color, so the focused
/// control is unmistakable from the couch.
struct TVPillButtonStyle: ButtonStyle {
    var fill: Color = .ink
    var onFill: Color = Color(hexValue: 0x171B26)
    var idleFill: Color?
    var idleText: Color = .ink

    func makeBody(configuration: Configuration) -> some View {
        PillLabel(
            configuration: configuration,
            fill: fill, onFill: onFill,
            idleFill: idleFill ?? fill.opacity(0.10), idleText: idleText
        )
    }

    private struct PillLabel: View {
        @Environment(\.isFocused) private var focused
        let configuration: Configuration
        let fill: Color
        let onFill: Color
        let idleFill: Color
        let idleText: Color

        var body: some View {
            configuration.label
                .font(.labelLarge)
                .foregroundStyle(focused ? onFill : idleText)
                .padding(.horizontal, 32)
                .frame(minHeight: 64)
                .background(focused ? fill : idleFill, in: Capsule())
                .scaleEffect(focused ? 1.05 : 1)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .shadow(color: .black.opacity(focused ? 0.4 : 0), radius: 16, y: 8)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// Focus-aware full-width row: the frosted ink card used by pickers, search
/// results, cast billing, and discovered-server lists.
struct TVRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowLabelView(configuration: configuration)
    }

    private struct RowLabelView: View {
        @Environment(\.isFocused) private var focused
        let configuration: Configuration

        var body: some View {
            configuration.label
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    focused ? Color.ink.opacity(0.18) : Color.ink.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(focused ? Color.ink.opacity(0.6) : Color.ink.opacity(0.10), lineWidth: focused ? 2 : 1)
                )
                .scaleEffect(focused ? 1.02 : 1)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// The hero is one big click target, like the Android app; under focus it
/// breathes rather than lifts — a bias-cut backdrop on a card platter would
/// break the seamless ground the cut depends on.
struct TVHeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HeroLabel(configuration: configuration)
    }

    private struct HeroLabel: View {
        @Environment(\.isFocused) private var focused
        let configuration: Configuration

        var body: some View {
            configuration.label
                .scaleEffect(focused ? 1.012 : 1, anchor: .bottom)
                .brightness(focused ? 0.05 : 0)
                .animation(.easeOut(duration: 0.2), value: focused)
        }
    }
}

// MARK: - Cards

/// Poster face for the tvOS card button style: the style supplies the lift,
/// specular sheen, and focus motion; the overlays ride along with it.
struct TVPosterCard: View {
    let item: Item
    var thread: Color = .ember
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        ZStack {
            if let url = appEnvironment.client?.imageURL(id: item.posterImageId, tag: item.posterImageTag, width: 480) {
                CachedImage(url: url, contentMode: .fill)
            } else {
                MissingArt(title: item.title, tint: thread)
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .overlay(alignment: .topTrailing) {
            if let unwatched = item.unwatchedCount, unwatched > 0 {
                BobbinBadge(count: unwatched, color: thread)
                    .padding(10)
            }
        }
        .overlay(alignment: .bottom) {
            if let fraction = progressFraction(item) {
                ThreadProgress(fraction: fraction, color: thread)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
        }
    }
}

/// 16:9 thumb face plus its static labels. The card lifts under focus; the
/// text stays put beneath it, the way the system's own shelves behave.
struct TVThumbCell: View {
    let item: Item
    var heading: String?
    var caption: String?
    var thread: Color = .ember
    var width: CGFloat = TVLayout.thumbWidth
    var action: () -> Void

    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: action) {
                ZStack {
                    Color.surface1
                    if let url = appEnvironment.client?.imageURL(id: item.thumbImageId, tag: item.thumbImageTag, width: 480) {
                        CachedImage(url: url, contentMode: .fill)
                    } else {
                        MissingArt(title: item.title, tint: thread)
                    }
                }
                .frame(width: width, height: width * 9 / 16)
                .overlay(alignment: .bottom) {
                    if let fraction = progressFraction(item) {
                        ThreadProgress(fraction: fraction, color: thread)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
            }
            .buttonStyle(.card)

            VStack(alignment: .leading, spacing: 2) {
                if let heading {
                    Text(heading)
                        .font(.titleSmall)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                }
                if let caption {
                    Text(caption)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 4)
        }
        .frame(width: width, alignment: .leading)
    }
}

/// Episodes show their own screencap; everything else leads with the backdrop
/// (the poster only as a last resort). Same rule as the iPad detail screen.
func tvDetailArtURL(for item: Item, client: LoomClient, width: Int) -> URL? {
    if item.kind == "episode",
       let url = client.imageURL(id: item.thumbImageId, tag: item.thumbImageTag, width: width) {
        return url
    }
    return client.imageURL(id: item.backdropImageId, tag: item.backdropImageTag, width: width)
        ?? client.imageURL(id: item.thumbImageId, tag: item.thumbImageTag, width: width)
        ?? client.imageURL(id: item.posterImageId, tag: item.posterImageTag, width: width)
}
