import CoreGraphics
import Testing
@testable import Takeup

struct SubtitleCueTests {
    @Test func plainCueSitsBottomCenter() {
        let cues = SubtitleCue.parse("Hello there")
        #expect(cues.count == 1)
        #expect(cues[0].vertical == .bottom)
        #expect(cues[0].horizontal == .center)
        #expect(cues[0].runs == [SubtitleCue.Run(text: "Hello there")])
    }

    @Test func nothingToDraw() {
        #expect(SubtitleCue.parse(nil).isEmpty)
        #expect(SubtitleCue.parse("").isEmpty)
        // An event of nothing but stripped tags leaves no text.
        #expect(SubtitleCue.parse("{\\an8}").isEmpty)
    }

    @Test func hardBreaksAndHardSpaces() {
        let cues = SubtitleCue.parse("First line\\NSecond\\hline")
        #expect(cues[0].plainText == "First line\nSecond\u{00A0}line")
    }

    @Test func linesSplitAtHardBreaks() {
        let cue = SubtitleCue.parse("{\\i1}Whisper{\\i0} it\\Nout loud")[0]
        #expect(cue.lines == [
            [SubtitleCue.Run(text: "Whisper", italic: true), SubtitleCue.Run(text: " it")],
            [SubtitleCue.Run(text: "out loud")],
        ])
    }

    @Test func emphasisBecomesRuns() {
        let cues = SubtitleCue.parse("plain {\\i1}italic{\\i0} back")
        #expect(cues[0].runs == [
            SubtitleCue.Run(text: "plain "),
            SubtitleCue.Run(text: "italic", italic: true),
            SubtitleCue.Run(text: " back"),
        ])
    }

    @Test func boldAndUnderlineCombine() {
        let cues = SubtitleCue.parse("{\\b1}{\\u1}loud{\\u0} still bold")
        #expect(cues[0].runs == [
            SubtitleCue.Run(text: "loud", bold: true, underline: true),
            SubtitleCue.Run(text: " still bold", bold: true),
        ])
    }

    @Test func weightNumbersDecideBold() {
        #expect(SubtitleCue.parse("{\\b700}heavy")[0].runs[0].bold)
        #expect(!SubtitleCue.parse("{\\b400}regular")[0].runs[0].bold)
        #expect(!SubtitleCue.parse("{\\b0}regular")[0].runs[0].bold)
    }

    @Test func numpadAlignment() {
        #expect(SubtitleCue.parse("{\\an8}top")[0].vertical == .top)
        #expect(SubtitleCue.parse("{\\an8}top")[0].horizontal == .center)
        #expect(SubtitleCue.parse("{\\an1}corner")[0].vertical == .bottom)
        #expect(SubtitleCue.parse("{\\an1}corner")[0].horizontal == .leading)
        #expect(SubtitleCue.parse("{\\an6}side")[0].vertical == .middle)
        #expect(SubtitleCue.parse("{\\an6}side")[0].horizontal == .trailing)
    }

    @Test func unknownTagsAreDropped() {
        // Colors, fonts, borders and positions all give way to the one style.
        let cues = SubtitleCue.parse("{\\c&H00FF00&\\bord2\\blur3\\fn Arial\\pos(10,20)}green")
        #expect(cues[0].runs == [SubtitleCue.Run(text: "green")])
        #expect(cues[0].vertical == .bottom)
    }

    @Test func simultaneousEventsMergeByAnchor() {
        let cues = SubtitleCue.parse("bottom one\nbottom two\n{\\an8}sign")
        #expect(cues.count == 2)
        #expect(cues[0].plainText == "bottom one\nbottom two")
        #expect(cues[0].vertical == .bottom)
        #expect(cues[1].plainText == "sign")
        #expect(cues[1].vertical == .top)
    }
}

/// Cues are sized and placed against the displayed picture, so the rect the
/// overlay derives has to match mpv's own centered fit.
struct SubtitleVideoRectTests {
    @Test func letterboxedPortrait() {
        // 16:9 on the 11" iPad's portrait surface: a band with black above and
        // below, and the cue font a twentieth of the band, not of the screen.
        let rect = subtitleVideoRect(surface: CGSize(width: 834, height: 1194), aspect: 16.0 / 9.0)
        #expect(rect.width == 834)
        #expect(abs(rect.height - 469.125) < 0.01)
        #expect(rect.minX == 0)
        #expect(abs(rect.minY - 362.4375) < 0.01)
        #expect(abs(rect.height * 0.05 - 23.4) < 0.1)
    }

    @Test func pillarboxed() {
        // A 4:3 picture on a wide surface leaves bars at the sides instead.
        let rect = subtitleVideoRect(surface: CGSize(width: 1200, height: 600), aspect: 4.0 / 3.0)
        #expect(rect.height == 600)
        #expect(rect.width == 800)
        #expect(rect.minX == 200)
        #expect(rect.minY == 0)
    }

    @Test func aspectMatchingTheSurfaceFillsIt() {
        let rect = subtitleVideoRect(surface: CGSize(width: 1600, height: 900), aspect: 16.0 / 9.0)
        #expect(abs(rect.width - 1600) < 0.01)
        #expect(abs(rect.height - 900) < 0.01)
        #expect(rect.origin == .zero)
    }

    @Test func unknownAspectFallsBackToTheWholeSurface() {
        let surface = CGSize(width: 1194, height: 834)
        for aspect in [nil, 0, -1.5, Double.nan, .infinity] as [Double?] {
            let rect = subtitleVideoRect(surface: surface, aspect: aspect)
            #expect(rect == CGRect(origin: .zero, size: surface))
        }
    }
}
