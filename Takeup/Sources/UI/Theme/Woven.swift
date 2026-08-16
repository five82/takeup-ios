import SwiftUI
import ImageIO

// Artwork-seeded "woven" color, ported from the Android app (theme/Woven.kt):
// the artwork is decoded tiny, histogrammed, and up to three saturated,
// hue-separated swatches come back. The first is the seed that dresses a
// screen's accents; backgrounds stay pinned to Stage so pushing a screen
// never repaints the room, only its accents.

enum WovenExtractor {
    // Keyed per artwork URL: an item's poster and backdrop disagree often
    // enough that they must not share an entry. Cached results return
    // synchronously so a revisited screen paints woven on frame 1.
    @MainActor private static var cache: [URL: [RGB]] = [:]

    @MainActor
    static func cachedThreads(for url: URL?) -> [RGB]? {
        url.flatMap { cache[$0] }
    }

    @MainActor
    static func threads(for url: URL?) async -> [RGB] {
        guard let url else { return [] }
        if let hit = cache[url] { return hit }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        let extracted = extractThreads(from: data)
        cache[url] = extracted
        return extracted
    }

    /// Decodes at 64px and histograms 4 bits per channel (4096 buckets).
    /// Near-black and near-white are the backdrop, not thread; the score
    /// favors saturated area so a big beige sky loses to a smaller saturated
    /// costume. Up to three picks, each at least 40 degrees of hue apart.
    static func extractThreads(from data: Data) -> [RGB] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 64,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary)
        else { return [] }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return [] }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = context.data else { return [] }

        var buckets = [Int](repeating: 0, count: 4096)
        let buffer = pixels.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for i in 0..<(width * height) {
            let r = Int(buffer[i * 4]) >> 4
            let g = Int(buffer[i * 4 + 1]) >> 4
            let b = Int(buffer[i * 4 + 2]) >> 4
            buckets[(r << 8) | (g << 4) | b] += 1
        }

        struct Candidate {
            let rgb: RGB
            let hue: Double
            let score: Double
        }
        var candidates: [Candidate] = []
        for (bucket, count) in buckets.enumerated() where count > 0 {
            // Nibble * 17 reconstructs the bucket's representative color.
            let rgb = RGB(
                r: Double((bucket >> 8) & 0xF) * 17 / 255,
                g: Double((bucket >> 4) & 0xF) * 17 / 255,
                b: Double(bucket & 0xF) * 17 / 255
            )
            let (h, s, v) = rgb.hsv
            if v < 0.12 { continue }
            if s < 0.08 && v > 0.85 { continue }
            let score = Double(count) * (0.15 + s) * (0.25 + v)
            candidates.append(Candidate(rgb: rgb, hue: h, score: score))
        }
        candidates.sort { $0.score > $1.score }

        var picks: [Candidate] = []
        for candidate in candidates {
            if picks.count == 3 { break }
            let separated = picks.allSatisfy { pick in
                let delta = abs(pick.hue - candidate.hue)
                return min(delta, 360 - delta) >= 40
            }
            if separated { picks.append(candidate) }
        }
        return picks.map(\.rgb)
    }
}

/// The accent roles a seed dresses a screen in. The Android app builds a full
/// Material scheme from the seed; here the same intent is carried by hand:
/// accents follow the seed's own chroma (muted art gives muted accents), and
/// the fill/onFill pair keeps button text legible whatever the artwork.
struct WovenAccent: Equatable {
    var fill: Color        // primary button fill (pastel of the seed)
    var onFill: Color      // text/icon on that fill (deep cut of the seed)
    var tint: Color        // freestanding accents: progress, chips, checks

    /// Before the artwork decodes, the room stays neutral — falling back to
    /// the brand accent would flash Ember on every push.
    static let neutral = WovenAccent(
        fill: Color(hexValue: 0xC9CFDC),
        onFill: Color(hexValue: 0x272B36),
        tint: .muted
    )

    static func from(seed: RGB) -> WovenAccent {
        let (h, s, _) = seed.hsv
        // Tone mapping in the spirit of a Material dark scheme: a light
        // pastel fill (tone ~85), a deep on-color (~25), and a brighter tint
        // that can stand alone on Stage.
        let fill = RGB.fromHSV(h: h, s: min(s * 0.62, 0.55), v: 0.88)
        let onFill = RGB.fromHSV(h: h, s: min(s * 0.85, 0.7), v: 0.24)
        let tint = RGB.fromHSV(h: h, s: min(max(s * 0.9, 0.25), 0.65), v: 0.85)
        return WovenAccent(fill: fill.color, onFill: onFill.color, tint: tint.color)
    }
}
