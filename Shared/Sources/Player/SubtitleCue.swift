import Foundation

/// One subtitle block to draw, with the placement the cue asked for.
///
/// Cues are drawn by SubtitleOverlay rather than by libass, which cannot round
/// a corner or pad a background box. We only ever play SRT: text cues, no
/// bitmaps, no embedded fonts or sizes, so there is little of libass's job left
/// to miss. Emphasis and `{\anX}` placement, the two things SRT does carry,
/// survive mpv's SRT-to-ASS conversion and are parsed out here.
struct SubtitleCue: Equatable, Identifiable {
    enum Vertical { case top, middle, bottom }
    enum Horizontal { case leading, center, trailing }

    /// A stretch of text sharing one emphasis. A cue's own colors are dropped
    /// on purpose: the point of drawing these ourselves is one deliberate look.
    struct Run: Equatable {
        var text: String
        var italic = false
        var bold = false
        var underline = false
    }

    var vertical: Vertical = .bottom
    var horizontal: Horizontal = .center
    var runs: [Run] = []

    /// Cues are merged by placement, so the anchor identifies one uniquely.
    var id: String { "\(vertical)-\(horizontal)" }

    var plainText: String { runs.map(\.text).joined() }

    /// The runs split at hard breaks. The overlay draws a row per line so the
    /// box hugs the longest one: a SwiftUI Text that wraps reports the whole
    /// width it was offered, which would leave a near-full-width box behind
    /// two short lines.
    var lines: [[Run]] {
        var lines: [[Run]] = [[]]
        for run in runs {
            for (index, piece) in run.text.components(separatedBy: "\n").enumerated() {
                if index > 0 { lines.append([]) }
                guard !piece.isEmpty else { continue }
                var line = run
                line.text = piece
                lines[lines.count - 1].append(line)
            }
        }
        return lines
    }
}

extension SubtitleCue {
    /// Parses mpv's `sub-text/ass`: simultaneous events joined by newlines,
    /// each an ASS event body. Events that land on the same anchor are merged
    /// into one block so they stack instead of overprinting each other.
    static func parse(_ ass: String?) -> [SubtitleCue] {
        guard let ass, !ass.isEmpty else { return [] }
        var cues: [SubtitleCue] = []
        for event in ass.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let cue = parseEvent(String(event)) else { continue }
            if let index = cues.firstIndex(where: {
                $0.vertical == cue.vertical && $0.horizontal == cue.horizontal
            }) {
                cues[index].runs.append(Run(text: "\n"))
                cues[index].runs.append(contentsOf: cue.runs)
            } else {
                cues.append(cue)
            }
        }
        return cues
    }

    private static func parseEvent(_ event: String) -> SubtitleCue? {
        var cue = SubtitleCue()
        var style = Run(text: "")
        var pending = ""
        var runs: [Run] = []

        func flush() {
            guard !pending.isEmpty else { return }
            style.text = pending
            runs.append(style)
            pending = ""
        }

        var index = event.startIndex
        while index < event.endIndex {
            let character = event[index]
            if character == "{", let close = event[index...].firstIndex(of: "}") {
                flush()
                apply(String(event[event.index(after: index)..<close]), to: &cue, style: &style)
                index = event.index(after: close)
                continue
            }
            let next = event.index(after: index)
            if character == "\\", next < event.endIndex {
                switch event[next] {
                // \N is a hard break; \n only breaks when wrapping is off, but
                // SRT never sets that, and a break is what the author meant.
                case "N", "n": pending.append("\n")
                case "h": pending.append("\u{00A0}")
                default:
                    pending.append(character)
                    pending.append(event[next])
                }
                index = event.index(after: next)
                continue
            }
            pending.append(character)
            index = next
        }
        flush()

        guard !runs.isEmpty else { return nil }
        cue.runs = runs
        return cue
    }

    /// Reads an override block's tags. Anything unrecognized is dropped, which
    /// is the point: colors, fonts and pixel positions all give way to the one
    /// app style.
    private static func apply(_ block: String, to cue: inout SubtitleCue, style: inout Run) {
        for tag in block.split(separator: "\\") {
            let tag = String(tag)
            if let value = number(in: tag, after: "an"), (1...9).contains(value) {
                cue.vertical = value <= 3 ? .bottom : (value <= 6 ? .middle : .top)
                cue.horizontal = value % 3 == 1 ? .leading : (value % 3 == 2 ? .center : .trailing)
            } else if let value = number(in: tag, after: "i") {
                style.italic = value != 0
            } else if let value = number(in: tag, after: "b") {
                // \b1 switches bold on, \b0 off; a number is a font weight, so
                // only 700 and up count as bold (\b400 is regular).
                style.bold = value == 1 || value >= 700
            } else if let value = number(in: tag, after: "u") {
                style.underline = value != 0
            }
        }
    }

    /// The digits following a tag name, or nil when the tag is something else
    /// that merely starts the same way (`\iclip`, `\bord`, `\blur`).
    private static func number(in tag: String, after name: String) -> Int? {
        guard tag.hasPrefix(name) else { return nil }
        let digits = tag.dropFirst(name.count)
        guard !digits.isEmpty, digits.allSatisfy(\.isWholeNumber) else { return nil }
        return Int(digits)
    }
}
