import SwiftUI

// The light treatments that give screens their atmosphere. Depth in Takeup
// comes from background light, not card shadows: every treatment paints over
// the Stage the screen already sits on.

private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

private func lerpStage(toward tone: RGB, _ t: Double) -> Color {
    let stage = RGB(hexValue: 0x0B0E14)
    return RGB(
        r: lerp(stage.r, tone.r, t),
        g: lerp(stage.g, tone.g, t),
        b: lerp(stage.b, tone.b, t)
    ).color
}

/// The quietest treatment: Stage soaked 16% toward the seed's field tone,
/// plus one soft glow from above.
struct DyeBath: View {
    var seed: RGB?

    var body: some View {
        let tone = (seed ?? RGB(hexValue: 0x131826)).fieldTone()
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack {
                lerpStage(toward: tone, 0.16)
                RadialGradient(
                    colors: [tone.color.opacity(0.20), .clear],
                    center: UnitPoint(x: 0.5, y: -0.2 * w / max(proxy.size.height, 1)),
                    startRadius: 0,
                    endRadius: 1.3 * w
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// The hero's backdrop blurred past recognition — no faces, no composition,
/// just the film's color weather — darkened toward the ceiling and hung
/// behind the whole screen. Fetch the 240 bucket: a blur has no detail to
/// lose.
struct GauzeBackground: View {
    var url: URL?
    var seed: RGB? = nil
    /// Home uses 0.9 to stay a little more colorful than Detail.
    var scrimAlphaScale: Double = 1.0

    // Blur radius is in points, so a fixed value reads weaker as the canvas
    // grows: 64 is ~6% of the iPad pane's width but only ~3% of the TV's
    // 1920pt, which left the backdrop's composition recognizable at ten feet.
    // Hold the iPad proportion on the big canvas instead.
    #if os(tvOS)
    private let blurRadius: CGFloat = 128
    #else
    private let blurRadius: CGFloat = 64
    #endif

    var body: some View {
        ZStack {
            DyeBath(seed: seed)
            if let url {
                // The filled image reports its overflowing size, not the
                // proposal; hosting it in an overlay keeps that overflow out
                // of layout, where it would balloon the enclosing stack and
                // shove the screen's real content off the pane (`.clipped()`
                // trims drawing only, not the reported size).
                Color.clear
                    .overlay {
                        CachedImage(url: url, contentMode: .fill) { Color.clear }
                            .saturation(1.4)
                            .blur(radius: blurRadius)
                    }
                    .ignoresSafeArea()
            }
            LinearGradient(
                stops: [
                    .init(color: .stage.opacity(0.55 * scrimAlphaScale), location: 0),
                    .init(color: .stage.opacity(0.68 * scrimAlphaScale), location: 0.55),
                    .init(color: .stage.opacity(0.88 * scrimAlphaScale), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .clipped()
        .ignoresSafeArea()
    }
}

/// A thread-colored field pouring from the top-leading corner, like house
/// lights coming up in one wing of the theater — bright enough to light the
/// header, shallow enough to leave the lower screen on plain Stage.
struct HouseLights: View {
    var thread: Color

    var body: some View {
        GeometryReader { proxy in
            let radius = 1.15 * proxy.size.width
            // A full disc squashed into an ellipse and cornered, rather than a
            // scaled screen-sized layer: the disc reaches clear at its own
            // edge, so the compression can't leave a visible cut line where
            // the layer ends (it did, in landscape).
            RadialGradient(
                colors: [thread.opacity(0.20), .clear],
                center: .center,
                startRadius: 0,
                endRadius: radius
            )
            .frame(width: radius * 2, height: radius * 2)
            .scaleEffect(y: 0.55)
            .position(x: 0, y: 0)
        }
        .background(Color.stage)
        .ignoresSafeArea()
    }
}

/// Up to three extracted (or brand) colors as large soft fields of light,
/// optionally drifting like stage lighting warming up.
struct ThreeThreads: View {
    var colors: [RGB]
    var drifting = false

    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var t1 = 0.5
    @State private var t2 = 0.5

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let tones = colors.map { $0.fieldTone().color }
            let sway1 = (t1 - 0.5) * 0.12 * w
            let sway2 = (t2 - 0.5) * 0.12 * w
            ZStack {
                Color.stage
                if tones.count > 0 {
                    blob(tones[0], alpha: 0.30, radius: 0.70 * w,
                         x: 0.12 * w + sway1, y: 0.18 * h + sway2 * 0.5)
                }
                if tones.count > 1 {
                    blob(tones[1], alpha: 0.24, radius: 0.80 * w,
                         x: 0.92 * w - sway1, y: 0.42 * h - sway2 * 0.5)
                }
                if tones.count > 2 {
                    blob(tones[2], alpha: 0.26, radius: 0.85 * w,
                         x: 0.35 * w + sway2, y: 0.98 * h + sway1 * 0.5)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard drifting, !reducedMotion else { return }
            withAnimation(.linear(duration: 21).repeatForever(autoreverses: true)) { t1 = 1 }
            withAnimation(.linear(duration: 27).repeatForever(autoreverses: true)) { t2 = 1 }
        }
    }

    private func blob(_ color: Color, alpha: Double, radius: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        RadialGradient(colors: [color.opacity(alpha), .clear], center: .center, startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
            .position(x: x, y: y)
    }
}

/// The grid's lead item casts a soft two-color echo into the top of the
/// screen, cross-fading when the lead changes so browsing washes rather than
/// strobes.
struct ShadowWeave: View {
    var swatches: [RGB]
    var fallback: RGB

    var body: some View {
        let first = (swatches.first ?? fallback).fieldTone().color
        let second = (swatches.count > 1 ? swatches[1] : (swatches.first ?? fallback)).fieldTone().color
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Color.stage
                RadialGradient(colors: [first.opacity(0.26), .clear], center: .center, startRadius: 0, endRadius: 0.75 * w)
                    .frame(width: 1.5 * w, height: 1.5 * w)
                    .position(x: 0.30 * w, y: 0.02 * h)
                RadialGradient(colors: [second.opacity(0.20), .clear], center: .center, startRadius: 0, endRadius: 0.60 * w)
                    .frame(width: 1.2 * w, height: 1.2 * w)
                    .position(x: 0.80 * w, y: 0.10 * h)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.4), value: swatches)
    }
}
