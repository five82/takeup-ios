import SwiftUI

// The Takeup palette, shared verbatim with the Android app (ui/theme/Color.kt).
// The whole system is a loom metaphor: Stage is the unlit loom — deep indigo,
// never pure black — and four fixed "threads" color the app's worlds.

extension Color {
    // Neutrals.
    static let stage = Color(hexValue: 0x0B0E14)
    static let surface1 = Color(hexValue: 0x131826)
    static let surface2 = Color(hexValue: 0x1A2032)
    static let line = Color(hexValue: 0x232B3F)
    static let ink = Color(hexValue: 0xE9EDF6)
    static let muted = Color(hexValue: 0x8C96AB)
    static let faint = Color(hexValue: 0x5C667C)

    // Brand threads.
    static let ember = Color(hexValue: 0xFF4D55)
    static let teal = Color(hexValue: 0x3FD1C4)
    static let amber = Color(hexValue: 0xFFB84D)
    static let violet = Color(hexValue: 0xA78BFA)
    // Fifth thread, added when Browse split into Collections and Genres: a
    // cornflower blue sitting in the palette gap between teal and violet.
    static let cobalt = Color(hexValue: 0x5FA0FF)

    init(hexValue: UInt32) {
        self.init(
            red: Double((hexValue >> 16) & 0xFF) / 255,
            green: Double((hexValue >> 8) & 0xFF) / 255,
            blue: Double(hexValue & 0xFF) / 255
        )
    }
}

/// The thread color for a Loom library kind: tv → Teal, shorts → Amber,
/// everything else (movies, the brand) → Ember.
func libraryThread(_ kind: String?) -> Color {
    switch kind {
    case "tv": .teal
    case "shorts": .amber
    default: .ember
    }
}

// MARK: - RGB/HSV plumbing

/// A color as plain RGB in [0, 1], for the HSV math the palette derivations
/// need. SwiftUI's Color hides its components; the design system works in
/// values it owns.
struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(hexValue: UInt32) {
        r = Double((hexValue >> 16) & 0xFF) / 255
        g = Double((hexValue >> 8) & 0xFF) / 255
        b = Double(hexValue & 0xFF) / 255
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    var hsv: (h: Double, s: Double, v: Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h *= 60
            if h < 0 { h += 360 }
        }
        let s = maxC == 0 ? 0 : delta / maxC
        return (h, s, maxC)
    }

    static func fromHSV(h: Double, s: Double, v: Double) -> RGB {
        let c = v * s
        let hPrime = (h.truncatingRemainder(dividingBy: 360) / 60)
        let x = c * (1 - abs(hPrime.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double) = switch Int(hPrime) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        let m = v - c
        return RGB(r: r1 + m, g: g1 + m, b: b1 + m)
    }

    /// The tone every background treatment paints with: hue untouched,
    /// saturation floored at 0.30 (so quantized swatches don't go murky),
    /// value clamped to [0.48, 0.62] (ceiling keeps white logo art and Ink
    /// legible on every field; floor keeps near-black swatches from vanishing
    /// into Stage).
    func fieldTone() -> RGB {
        let (h, s, v) = hsv
        return RGB.fromHSV(h: h, s: max(s, 0.30), v: min(max(v, 0.48), 0.62))
    }

    /// HSV value scaled by `valueScale` — the genre tiles' darkened floor.
    func darkened(_ valueScale: Double) -> RGB {
        RGB(r: r * valueScale, g: g * valueScale, b: b * valueScale)
    }

    /// Per-channel lightening toward white — the bright tip of a progress
    /// thread.
    func lightened(_ fraction: Double) -> RGB {
        RGB(r: r + (1 - r) * fraction, g: g + (1 - g) * fraction, b: b + (1 - b) * fraction)
    }
}

// MARK: - Genre palette

// One curated tile color per TMDB movie genre id: a cool, saturated jewel
// palette — no browns, tans, golds, or olives. The single source of truth for
// genre hue, mirrored from the Android app.
private let genreFields: [Int64: UInt32] = [
    28: 0x9E2B3A,     // Action - garnet
    12: 0x2268B8,     // Adventure - azure
    16: 0x6C33C4,     // Animation - violet
    35: 0xA62887,     // Comedy - magenta
    80: 0x3D51C9,     // Crime - indigo
    99: 0x2E7D46,     // Documentary - forest
    18: 0x7A2140,     // Drama - deep wine
    10751: 0x0F8A6D,  // Family - teal
    14: 0x8146E0,     // Fantasy - bright violet
    36: 0x1D5A9E,     // History - deep azure
    27: 0x24523B,     // Horror - dark forest
    10402: 0x0E7E96,  // Music - cyan
    9648: 0x2C3B9E,   // Mystery - deep indigo
    10749: 0xB13D6F,  // Romance - rose
    878: 0x1899B4,    // Science Fiction - bright cyan
    53: 0x39456E,     // Thriller - slate indigo
    10770: 0x6D5591,  // TV Movie - dusty violet
    10752: 0x2F5D84,  // War - steel azure
    37: 0x216D54,     // Western - spruce
]

func genreField(_ id: Int64) -> RGB {
    if let hexValue = genreFields[id] {
        return RGB(hexValue: hexValue)
    }
    // Unknown ids get a golden-angle hue spin so new genres still land on a
    // stable, distinct color.
    let hue = (Double(id) * 137.508).truncatingRemainder(dividingBy: 360)
    return RGB.fromHSV(h: hue, s: 0.48, v: 0.32)
}

/// The bright accent derived from a genre field: saturation eased, value
/// forced up so it works as a screen accent on Stage.
func genreThread(_ id: Int64) -> RGB {
    let (h, s, _) = genreField(id).hsv
    return RGB.fromHSV(h: h, s: s * 0.8, v: 0.92)
}
