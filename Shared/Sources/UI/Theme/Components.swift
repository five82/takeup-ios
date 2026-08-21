import SwiftUI

// MARK: - Pointer hover

extension View {
    /// The iPad's pointer hover lift. On tvOS the focus engine supplies all
    /// the motion, and `hoverEffect` does not exist there.
    @ViewBuilder
    func padHover() -> some View {
#if os(iOS)
        hoverEffect(.lift)
#else
        self
#endif
    }
}

// MARK: - Pane width

// The measured width of the navigation pane, provided by the root shell.
// Pushed navigation destinations on the iOS 26 beta receive an unspecified
// width proposal and would otherwise size to their ideal width.
extension EnvironmentValues {
    @Entry var paneWidth: CGFloat = 0
}

/// Pins a pushable screen to the shell's measured pane width.
struct PaneConstrained: ViewModifier {
    @Environment(\.paneWidth) private var paneWidth

    func body(content: Content) -> some View {
        content.frame(width: paneWidth > 0 ? paneWidth : nil)
    }
}

extension View {
    func paneConstrained() -> some View {
        modifier(PaneConstrained())
    }
}

// MARK: - Selvedge

/// The woven brand stripe: ember, teal, amber, violet in fixed proportion.
/// Narrow uses get one full pattern scaled to fit; wide uses tile it.
struct Selvedge: View {
    var height: CGFloat = 4

    private static let pattern: [(Color, CGFloat)] = [
        (.ember, 0.40), (.teal, 0.29), (.amber, 0.20), (.violet, 0.11),
    ]

    var body: some View {
        GeometryReader { proxy in
            let repeatWidth = min(proxy.size.width, 140)
            let tiles = Int((proxy.size.width / repeatWidth).rounded(.up))
            HStack(spacing: 0) {
                ForEach(0..<max(tiles, 1), id: \.self) { _ in
                    ForEach(0..<Self.pattern.count, id: \.self) { index in
                        Self.pattern[index].0
                            .frame(width: repeatWidth * Self.pattern[index].1)
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2))
    }
}

// MARK: - Thread progress

/// Progress drawn as a thread being woven: a thin line in the given color
/// brightening toward its end, on a faint unwoven track.
struct ThreadProgress: View {
    var fraction: Double
    var color: Color
    /// The bright tip: the same color lightened 35% toward white.
    var tipColor: Color?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.18))
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [color, tipColor ?? color.opacity(0.65)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 3)
    }
}

extension ThreadProgress {
    /// Thread + tip from one RGB, computing the literal +35%-toward-white tip.
    init(fraction: Double, thread: RGB) {
        self.init(fraction: fraction, color: thread.color, tipColor: thread.lightened(0.35).color)
    }
}

func progressFraction(_ item: Item) -> Double? {
    guard let progress = item.progress,
          let position = progress.resumePositionMs, position > 0,
          let duration = progress.durationMs, duration > 0
    else { return nil }
    return Double(position) / Double(duration)
}

// MARK: - Missing art

/// Poster fallback: the title set in the display voice over a Surface1 field,
/// under a short tinted rule. The poster is normally the label; here the
/// title stands in.
struct MissingArt: View {
    var title: String
    var tint: Color

    var body: some View {
        ZStack {
            Color.surface1
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tint.opacity(0.85))
                    .frame(width: 22, height: 3)
                Text(title.uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
            }
            .padding(10)
        }
    }
}

// MARK: - Badges and tags

/// The bobbin badge: unwatched episode count in a Stage-dark chip on a
/// poster's corner.
struct BobbinBadge: View {
    var count: Int
    var color: Color

    var body: some View {
        Text(String(count))
            .font(.labelSmall)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.stage.opacity(0.82), in: RoundedRectangle(cornerRadius: 7))
    }
}

/// Outlined uppercase tech badge: 4K, HDR, HEVC, channel layout, file size.
struct TechBadge: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.labelSmall)
            .foregroundStyle(Color.muted)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.line, lineWidth: 1))
    }
}

/// Search result kind tag: uppercase label on a tinted fill. Movie=Ember,
/// Show=Teal, Episode=Amber.
struct KindTag: View {
    var kind: String

    var body: some View {
        Text(label.uppercased())
            .font(.labelSmall)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
    }

    private var label: String {
        switch kind {
        case "movie": "Movie"
        case "show": "Show"
        case "season": "Season"
        case "episode": "Episode"
        default: kind
        }
    }

    private var color: Color {
        switch kind {
        case "movie": .ember
        case "show": .teal
        case "episode": .amber
        default: .muted
        }
    }
}

// MARK: - Buttons

/// The 48pt round header button floating over artwork.
struct RoundIconButton: View {
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color.ink)
                .frame(width: 48, height: 48)
                .background(Color.stage.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .padHover()
    }
}

// MARK: - Shared states

struct LoadingState: View {
    var body: some View {
        ProgressView()
            .tint(.ember)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "The loom is dark" — errors carry the brand voice, over a short selvedge.
struct ErrorState: View {
    var message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Selvedge(height: 3)
                .frame(width: 72)
            Text("The loom is dark")
                .font(.displaySmall)
                .foregroundStyle(Color.ink)
            Text(message)
                .font(.bodyMedium)
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
            if let retry {
                PillButton(title: "Try again", action: retry)
                    .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The quiet capsule action used by the shared states.
struct PillButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.labelLarge)
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(Color.ink.opacity(0.08), in: Capsule())
            .buttonStyle(.plain)
            .padHover()
    }
}

// MARK: - Offline

/// Offline as a place, not a failure. Unlike ErrorState this neither fills the
/// screen nor centers itself: whatever is genuinely on the device goes
/// underneath it, so the app still has something to show rather than only an
/// apology. Callers own the horizontal margins.
struct OfflineNotice: View {
    var reason: String
    var onRetry: () -> Void
    var onSettings: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The amber thread, cut short: the same signal the banner's dot
            // carries, in the voice MissingArt uses for its rule.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.amber.opacity(0.85))
                .frame(width: 44, height: 3)
            Text("Offline")
                .font(.displaySmall)
                .foregroundStyle(Color.ink)
                .padding(.top, 12)
            Text(reason)
                .font(.bodyMedium)
                .foregroundStyle(Color.muted)
                .padding(.top, 8)
            HStack(spacing: 12) {
                PillButton(title: "Try again", action: onRetry)
                if let onSettings {
                    PillButton(title: "Settings", action: onSettings)
                }
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Offline once there is something to show. OfflineNotice is for a screen with
/// nothing on it; this is one line above a screen full of downloads, so being
/// offline reads as a condition rather than as the page's subject.
struct OfflineBanner: View {
    var reason: String
    var onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.amber)
                .frame(width: 6, height: 6)
            Text(reason)
                .font(.labelLarge)
                .foregroundStyle(Color.muted)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Try again", action: onRetry)
                .font(.labelLarge)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .buttonStyle(.plain)
                .padHover()
        }
        .frame(maxWidth: .infinity)
    }
}

struct EmptyState: View {
    var message: String

    var body: some View {
        Text(message)
            .font(.bodyMedium)
            .foregroundStyle(Color.muted)
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
    }
}
