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

/// Logo art equalizes on area, not bounding box: a wide wordmark and a
/// stacked lockup carry the same visual weight. Tuned so a typical 3:1
/// wordmark lands at 64pt tall.
func logoLaneHeight(aspect: Double?) -> CGFloat {
    guard let aspect, aspect > 0 else { return 64 }
    return CGFloat(min(max((12300.0 / aspect).squareRoot(), 44), 100))
}

/// The art crop for a bias-cut head: the phone's full-width 4:3 in compact
/// panes, widening as the canvas does — the cut's angle never changes, only
/// the crop.
func biasCutArtAspect(width: CGFloat) -> CGFloat {
    if width >= 1000 { return 2.6 }
    if width >= 700 { return 2.1 }
    return 4.0 / 3.0
}

/// Total head height for a given width: art plus the open ground at the
/// bottom-left (`solidLeft`), minus the overlap the cut consumes.
func biasCutHeight(width: CGFloat, artAspect: CGFloat, solidLeft: CGFloat) -> CGFloat {
    width / artAspect + solidLeft - biasCutOverlap
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
