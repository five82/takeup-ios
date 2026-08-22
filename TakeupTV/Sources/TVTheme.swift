import SwiftUI

// TV-specific layout constants and focus treatments. The palette, type scale,
// and light treatments come from Shared/UI/Theme; what is new here is how the
// focus engine plays the role the iPad's pointer and fingers play.

/// The overscan-safe margins: content keeps 80pt from the sides and 60pt from
/// the top and bottom, per the tvOS layout guidance.
enum TVLayout {
    static let sideMargin: CGFloat = 80
    static let verticalMargin: CGFloat = 60
    static let posterWidth: CGFloat = 240
    static let thumbWidth: CGFloat = 400
    static let cardSpacing: CGFloat = 36
    static let rowSpacing: CGFloat = 44

    // The selvedge system: every backdrop head is a band across the top of
    // the screen, split by the 4° seam — art right, identity column left.
    // Home wears the tightest column (five short elements); detail takes a
    // working column; shows keep the band short so the episode strip is
    // fully on screen at rest.
    static let heroSeam: CGFloat = 0.36
    static let heroBand: CGFloat = 0.574
    static let detailSeam: CGFloat = 0.46
    static let movieBand: CGFloat = 0.62
    static let showBand: CGFloat = 0.52
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
                .lineLimit(1)
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

/// Bare label for the home hero's button: the focus treatment is painted on
/// the whole backdrop by TVHomeView (keyed on the button's focus), and a
/// system style would wash its white focus highlight over the identity block
/// — the same trap as the player's full-screen remote catcher.
struct TVHeroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - Focus halo

/// Thread-colored glow behind the focused card. The system card style's lift
/// and sheen read well mid-navigation but are easy to lose in a still frame;
/// the halo marks the focused card from across the room. Apply it to the
/// focusable control itself, outside `.buttonStyle(.card)`, so the glow hugs
/// the lifted platter.
private struct TVFocusHalo: ViewModifier {
    var thread: Color
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .shadow(color: thread.opacity(focused ? 0.55 : 0), radius: 28, y: 10)
            .animation(.easeOut(duration: 0.18), value: focused)
    }
}

extension View {
    func tvFocusHalo(_ thread: Color) -> some View {
        modifier(TVFocusHalo(thread: thread))
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
            if let url = appEnvironment.client?.imageURL(id: item.posterImageId, tag: item.posterImageTag, width: 600) {
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

/// Poster shelf/grid cell: the card button plus a title that appears only
/// under the focused poster, the way the system shelves caption focus. The
/// label slot is always reserved so rows never reflow, and the title dips
/// with the lift so the platter does not cover it.
struct TVPosterCell: View {
    let item: Item
    var thread: Color = .ember
    var width: CGFloat?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            NavigationLink(value: item) {
                TVPosterCard(item: item, thread: thread)
            }
            .buttonStyle(.card)
            .focused($focused)
            .shadow(color: thread.opacity(focused ? 0.55 : 0), radius: 28, y: 10)

            // The title slot stays one line tall, but the revealed title may
            // run wider than the poster: neighbors' slots are empty whenever
            // this cell is focused, so a long title borrows their space
            // instead of costing every row a second line.
            Text(verbatim: " ")
                .font(.titleSmall)
                .overlay {
                    Text(item.title)
                        .font(.titleSmall)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .frame(width: TVLayout.posterWidth * 1.5)
                }
                .opacity(focused ? 1 : 0)
                .offset(y: focused ? 14 : 0)
        }
        .frame(width: width)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

/// 16:9 thumb face plus its static labels. The card lifts under focus; the
/// text stays put beneath it, the way the system's own shelves behave, but
/// the caption inks up so the focused cell reads without motion.
struct TVThumbCell: View {
    let item: Item
    var heading: String?
    var caption: String?
    var thread: Color = .ember
    var width: CGFloat = TVLayout.thumbWidth
    var action: () -> Void

    @Environment(AppEnvironment.self) private var appEnvironment
    @FocusState private var focused: Bool

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
            .focused($focused)
            .shadow(color: thread.opacity(focused ? 0.55 : 0), radius: 28, y: 10)

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
                        .foregroundStyle(focused ? Color.ink : Color.muted)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 4)
        }
        .frame(width: width, alignment: .leading)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

/// One cast entry as billing, not a headshot: Loom stores no people photos,
/// so the strip commits to type — the character in the tracked label voice
/// over the actor's name, sized to its own content. Focus inks the name and
/// slides the selvedge stripe underneath; select pushes the person search.
struct TVBillingCard: View {
    let credit: Credit
    var accent: Color = .ember
    @FocusState private var focused: Bool

    var body: some View {
        NavigationLink(value: TVPersonSearch(name: credit.name)) {
            VStack(alignment: .leading, spacing: 6) {
                RowLabel(
                    text: credit.character ?? credit.role,
                    color: credit.role == "Director" ? accent : .faint,
                    font: .labelSmall,
                    tracking: TypeScale.labelSmall * 0.18
                )
                .lineLimit(1)
                Text(credit.name)
                    .font(.titleSmall)
                    .foregroundStyle(focused ? Color.ink : Color.muted)
                    .lineLimit(1)
                // Always in layout so focus never reflows the row.
                Selvedge(height: 4)
                    .frame(width: 110)
                    .opacity(focused ? 1 : 0)
            }
            // Long character strings ("The Bride / Beatrix Kiddo (Black
            // Mamba) / Mommy") would blow the card up to a banner; the card
            // truncates instead, and the person page has the full billing.
            .frame(maxWidth: 400, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(TVHeroButtonStyle())
        .focused($focused)
        .scaleEffect(focused ? 1.06 : 1, anchor: .leading)
        .animation(.easeOut(duration: 0.15), value: focused)
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
