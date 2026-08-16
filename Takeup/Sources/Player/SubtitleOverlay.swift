import SwiftUI
import UIKit

// Sizing follows the displayed picture rather than the type scale or the whole
// surface, so cues keep their proportions on any screen and in any orientation.
// The fractions are Media3 SubtitleView's defaults (5.33% of the picture),
// pulled in slightly for a handheld tablet.
private let textSizeFraction: CGFloat = 0.05
private let edgeFraction: CGFloat = 0.08

/// The rectangle mpv paints the picture into: scaled to fit the surface and
/// centered both ways, i.e. letterboxed or pillarboxed. A nil (or nonsense)
/// aspect means the shape is unknown -- before the file loads, or while
/// crop-to-fill has the picture covering the surface -- and the whole surface
/// stands in for it.
func subtitleVideoRect(surface: CGSize, aspect: Double?) -> CGRect {
    guard let aspect, aspect.isFinite, aspect > 0,
          surface.width > 0, surface.height > 0 else {
        return CGRect(origin: .zero, size: surface)
    }
    let ratio = CGFloat(aspect)
    let width = min(surface.width, surface.height * ratio)
    let height = min(surface.height, surface.width / ratio)
    return CGRect(
        x: (surface.width - width) / 2,
        y: (surface.height - height) / 2,
        width: width,
        height: height
    )
}

/// The bundled Lato faces used for cue text: medium as the base weight, bold
/// for `{\b}` runs, and italic variants of both. Falls back to the SF system
/// font if a face fails to resolve (defensive only -- the four TTFs are
/// registered via UIAppFonts and should always be present).
private struct SubtitleFonts {
    let medium: UIFont
    let mediumItalic: UIFont
    let bold: UIFont
    let boldItalic: UIFont

    init(size: CGFloat) {
        medium = UIFont(name: "Lato-Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
        mediumItalic = UIFont(name: "Lato-MediumItalic", size: size) ?? .italicSystemFont(ofSize: size)
        bold = UIFont(name: "Lato-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
        boldItalic = UIFont(name: "Lato-BoldItalic", size: size) ?? {
            let systemBold = UIFont.systemFont(ofSize: size, weight: .bold)
            let italicDescriptor = systemBold.fontDescriptor.withSymbolicTraits(
                systemBold.fontDescriptor.symbolicTraits.union(.traitItalic)
            )
            return italicDescriptor.map { UIFont(descriptor: $0, size: size) } ?? systemBold
        }()
    }

    func font(bold: Bool, italic: Bool) -> UIFont {
        switch (bold, italic) {
        case (true, true): return boldItalic
        case (true, false): return self.bold
        case (false, true): return mediumItalic
        case (false, false): return medium
        }
    }
}

/// Draws the current cues in the app's one subtitle voice: white Lato Medium
/// in a rounded, padded black box. See SubtitleCue for why libass does not
/// draw these itself.
struct SubtitleOverlay: View {
    var cues: [SubtitleCue]
    /// Display aspect of the picture; nil when it is unknown or fills the
    /// surface. See `subtitleVideoRect(surface:aspect:)`.
    var aspect: Double?
    /// How far bottom cues rise to clear the console while it is up.
    var lift: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let video = subtitleVideoRect(surface: size, aspect: aspect)
            let fontSize = video.height * textSizeFraction
            let edge = video.height * edgeFraction
            // Letterbox depths; on a pillarboxed or filled picture these are 0.
            let above = video.minY
            let below = size.height - video.maxY
            ZStack {
                ForEach(cues) { cue in
                    box(cue, fontSize: fontSize, maxWidth: video.width * 0.9)
                        // Keeping the padding relative to the picture holds
                        // cues (and left/right anchors) with it instead of
                        // letting them drift onto the pillarbox.
                        .padding(.horizontal, video.minX + 24)
                        .padding(.top, topInset(cue, above: above, edge: edge))
                        .padding(.bottom, bottomInset(cue, below: below, edge: edge))
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: alignment(for: cue)
                        )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func topInset(_ cue: SubtitleCue, above: CGFloat, edge: CGFloat) -> CGFloat {
        switch cue.vertical {
        case .top: return above + edge
        // Pair with the matching bottom inset so the cue centers on the
        // picture rather than on the surface.
        case .middle: return above
        case .bottom: return 0
        }
    }

    private func bottomInset(_ cue: SubtitleCue, below: CGFloat, edge: CGFloat) -> CGFloat {
        switch cue.vertical {
        case .top: return 0
        case .middle: return below
        // The console rises over the bottom of the surface, so bottom cues
        // clear whichever is higher: their own place in the picture, or the
        // console. In portrait the letterbox alone already puts them above it.
        case .bottom: return max(below + edge, lift)
        }
    }

    private func box(_ cue: SubtitleCue, fontSize: CGFloat, maxWidth: CGFloat) -> some View {
        let fonts = SubtitleFonts(size: fontSize)
        let spacing = lineSpacing(fonts: fonts, fontSize: fontSize)
        let cap = max(maxWidth - 28, 1)
        return VStack(spacing: spacing) {
            ForEach(Array(cue.lines.enumerated()), id: \.offset) { _, line in
                Text(attributed(line, fonts: fonts))
                    .lineSpacing(spacing)
                    .frame(maxWidth: cap)
                    // fixedSize hands the frame the text's own ideal width,
                    // which lets a short line hug instead of stretching to
                    // the cap. But fixedSize also proposes a nil width to
                    // Text, so a line whose own width exceeds the cap lays
                    // out at full, unwrapped width and overflows it -- only
                    // apply fixedSize when the line actually fits under the
                    // cap; otherwise let it wrap within the cap.
                    .fixedSize(horizontal: singleLineWidth(line, fonts: fonts) <= cap, vertical: false)
            }
        }
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        // The shadow keeps letters legible where a bright shot shows through
        // the box.
        .shadow(color: .black, radius: 3, x: 0, y: 2)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }

    /// The line's own single-line width, measured with the same per-run fonts
    /// `attributed(_:fonts:fontSize:)` picks (built directly as an
    /// NSAttributedString rather than bridged from the SwiftUI one, whose Font
    /// attribute does not reliably convert to a measurable UIFont). Used to
    /// decide whether fixedSize is safe: a line under the cap should hug it,
    /// but one over the cap must be allowed to wrap instead of overflowing.
    private func singleLineWidth(_ line: [SubtitleCue.Run], fonts: SubtitleFonts) -> CGFloat {
        let result = NSMutableAttributedString()
        for run in line {
            let font = fonts.font(bold: run.bold, italic: run.italic)
            result.append(NSAttributedString(string: run.text, attributes: [.font: font]))
        }
        let bounds = result.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return bounds.width.rounded(.up)
    }

    private func attributed(_ line: [SubtitleCue.Run], fonts: SubtitleFonts) -> AttributedString {
        var result = AttributedString()
        for run in line {
            var piece = AttributedString(run.text)
            let uiFont = fonts.font(bold: run.bold, italic: run.italic)
            piece.font = Font(uiFont)
            if run.underline { piece.underlineStyle = .single }
            result += piece
        }
        return result
    }

    /// SwiftUI's lineSpacing is a gap between lines, not a line height, so back
    /// the font's own height out of the 1.3x the design calls for.
    private func lineSpacing(fonts: SubtitleFonts, fontSize: CGFloat) -> CGFloat {
        return max(0, fontSize * 1.3 - fonts.medium.lineHeight)
    }

    private func alignment(for cue: SubtitleCue) -> Alignment {
        switch (cue.vertical, cue.horizontal) {
        case (.top, .leading): return .topLeading
        case (.top, .center): return .top
        case (.top, .trailing): return .topTrailing
        case (.middle, .leading): return .leading
        case (.middle, .center): return .center
        case (.middle, .trailing): return .trailing
        case (.bottom, .leading): return .bottomLeading
        case (.bottom, .center): return .bottom
        case (.bottom, .trailing): return .bottomTrailing
        }
    }
}
