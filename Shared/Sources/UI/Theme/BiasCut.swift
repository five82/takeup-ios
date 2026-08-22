import SwiftUI
import UIKit

// The app's single strongest visual signature: backdrop art whose bottom edge
// is a shallow diagonal rising left-to-right. One angle everywhere, so the
// cut reads as the app's signature.

let biasCutDegrees = 4.0
/// Art runs this far below the cut's low point, so the cut always trims the
/// raw bottom edge while hiding as little photo as possible.
let biasCutOverlap: CGFloat = 16

/// The visible art region: full rect minus the wedge below the cut. Clipping
/// with a Shape antialiases cleanly in SwiftUI, and leaves the wedge truly
/// transparent for the background behind.
struct BiasCutShape: Shape {
    func path(in rect: CGRect) -> Path {
        let leftY = rect.height - biasCutOverlap
        let rightY = leftY - rect.width * tan(biasCutDegrees * .pi / 180)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rightY))
        path.addLine(to: CGPoint(x: rect.minX, y: leftY))
        path.closeSubpath()
        return path
    }
}

/// Logo art standardized to a fixed box: every screen reserves the same
/// identity space regardless of the art's shape (the library spans 0.8:1
/// stacked lockups to 18:1 wordmarks). The logo scales to fit and pins to
/// the box's bottom-leading corner, so it sits tight against whatever
/// follows below. The exact fitted frame needs the decoded aspect —
/// CachedImage's greedy placeholder would otherwise center the art in the
/// box's leftover width.
/// The reserved box height for a screen-owning identity (detail heads, home
/// heroes). One value per platform keeps the occupied space constant across
/// wildly different logo shapes; leaner contexts (the TV episode page) pass
/// their own height.
#if os(tvOS)
let logoBoxHeight: CGFloat = 200
#else
let logoBoxHeight: CGFloat = 100
#endif

struct LogoBox: View {
    var url: URL?
    var width: CGFloat
    var height: CGFloat
    /// Reserve the full box height (TV: the band centers its column, so the
    /// constant reservation reads as composition) or hug the fitted logo
    /// (iPad: the bias-cut head sizes its open ground to the logo, and a
    /// reserved box strands empty space above thin wordmarks).
    var hugs = false
    /// Reports the fitted height whenever it changes, for layout that must
    /// track it — the iPad head's open ground. Fires on the decoded aspect
    /// settling and on the box's width changing (rotation re-fits a
    /// width-constrained wordmark), so the tracked value never goes stale.
    var onHeight: ((CGFloat) -> Void)? = nil

    @State private var aspect: Double = 3

    var body: some View {
        let fittedWidth = min(CGFloat(aspect) * height, width)
        let fittedHeight = fittedWidth / CGFloat(aspect)
        CachedImage(url: url, contentMode: .fit, onLoad: { image in
            let decoded = Double(image.size.width / max(image.size.height, 1))
            if aspect != decoded {
                withAnimation(.spring) { aspect = decoded }
            }
        }) { Color.clear }
            .frame(width: fittedWidth, height: fittedHeight)
            .frame(height: hugs ? fittedHeight : height, alignment: .bottomLeading)
            .onChange(of: fittedHeight) { _, newValue in
                withAnimation(.spring) { onHeight?(newValue) }
            }
    }
}

/// The art crop for a bias-cut head: the phone's full-width 4:3 in compact
/// panes, widening as the canvas does — the cut's angle never changes, only
/// the crop. The widest step is the TV's 1920pt canvas, where 2.6 would still
/// swallow most of the screen.
func biasCutArtAspect(width: CGFloat) -> CGFloat {
    if width >= 1600 { return 2.9 }
    if width >= 1000 { return 2.6 }
    if width >= 700 { return 2.1 }
    return 4.0 / 3.0
}

/// Total head height for a given width: art plus the open ground at the
/// bottom-left (`solidLeft`), minus the overlap the cut consumes.
func biasCutHeight(width: CGFloat, artAspect: CGFloat, solidLeft: CGFloat) -> CGFloat {
    width / artAspect + solidLeft - biasCutOverlap
}

/// The selvedge seam: the blade turned vertical for the TV's 16:9 canvas,
/// where the horizontal cut would trim the axis the screen is short on. The
/// art's left edge leans 4° — entering from the left at the top, running out
/// to the right at the bottom — like the self-finished edge of a bolt.
struct SelvedgeSeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        let run = rect.height * tan(biasCutDegrees * .pi / 180)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + run, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Backdrop art trimmed by the selvedge seam: art full-bleed to the top and
/// right edges, open ground on the left where the identity column sits. The
/// column never needs a scrim — text sits on the screen's own background,
/// which runs seamlessly up to the seam. `seam` is the fraction of the width
/// where the art begins at the top edge.
struct SelvedgeBackdrop<Content: View>: View {
    var url: URL?
    var width: CGFloat
    var height: CGFloat
    var seam: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            CachedImage(url: url, contentMode: .fill) { Color.surface1 }
                .frame(width: width * (1 - seam), height: height)
                .clipShape(SelvedgeSeamShape())
                .frame(width: width, alignment: .topTrailing)
            content()
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

/// Backdrop art trimmed by the bias cut, with open ground at the bottom-left
/// where the logo or title sits. The cut climbs away from there, so clearance
/// over left-aligned content only grows to the right. Nothing is painted
/// below the cut: the screen's own background runs seamlessly up to the
/// photo, and its scrim is what keeps the content legible.
struct BiasCutBackdrop<Content: View>: View {
    var url: URL?
    var width: CGFloat
    var solidLeft: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        let artAspect = biasCutArtAspect(width: width)
        let artHeight = width / artAspect
        ZStack(alignment: .bottomLeading) {
            CachedImage(url: url, contentMode: .fill) { Color.surface1 }
                .frame(width: width, height: artHeight)
                .clipShape(BiasCutShape())
                .overlay(alignment: .top) {
                    // Only overlay on the art: a wash protecting the status
                    // bar and header icons.
                    LinearGradient(
                        colors: [.stage.opacity(0.35), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 120)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            content()
        }
        .frame(width: width, height: biasCutHeight(width: width, artAspect: artAspect, solidLeft: solidLeft))
    }
}
