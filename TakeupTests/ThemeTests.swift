import Testing
import SwiftUI
@testable import Takeup

struct PaletteTests {
    @Test func libraryThreadMapsWorldsToTheirColors() {
        #expect(libraryThread("tv") == Color(hexValue: 0x3FD1C4))
        #expect(libraryThread("shorts") == Color(hexValue: 0xFFB84D))
        #expect(libraryThread("movies") == Color(hexValue: 0xFF4D55))
        #expect(libraryThread(nil) == Color(hexValue: 0xFF4D55))
    }

    @Test func curatedGenresUseTheJewelTable() {
        // Action is garnet; the table, not a derivation, is the source.
        let action = genreField(28)
        #expect(abs(action.r - Double(0x9E) / 255) < 0.001)
        #expect(abs(action.g - Double(0x2B) / 255) < 0.001)
        #expect(abs(action.b - Double(0x3A) / 255) < 0.001)
    }

    @Test func unknownGenreGetsStableFallback() {
        let a = genreField(99_999)
        let b = genreField(99_999)
        #expect(a == b)
        // Golden-angle fallback keeps the muted field tone.
        let (_, s, v) = a.hsv
        #expect(abs(s - 0.48) < 0.01)
        #expect(abs(v - 0.32) < 0.01)
    }

    @Test func genreThreadBrightensToScreenAccent() {
        let (_, _, v) = genreThread(28).hsv
        #expect(abs(v - 0.92) < 0.01)
    }

    @Test func fieldToneClampsForLegibility() {
        // Near-black poster swatch: value floors at 0.48 so it doesn't
        // vanish into Stage.
        let dark = RGB.fromHSV(h: 200, s: 0.5, v: 0.05).fieldTone()
        #expect(dark.hsv.v >= 0.48 - 0.001)
        // Bright swatch: value ceils at 0.62 so white logo art stays legible.
        let bright = RGB.fromHSV(h: 200, s: 0.5, v: 0.95).fieldTone()
        #expect(bright.hsv.v <= 0.62 + 0.001)
        // Desaturated swatch: saturation floors at 0.30.
        let gray = RGB.fromHSV(h: 200, s: 0.05, v: 0.55).fieldTone()
        #expect(gray.hsv.s >= 0.30 - 0.001)
        // Hue is untouched.
        #expect(abs(gray.hsv.h - 200) < 1)
    }

    @Test func lighteningMovesEachChannelTowardWhite() {
        let tip = RGB(hexValue: 0xFF4D55).lightened(0.35)
        #expect(abs(tip.r - 1.0) < 0.001)
        #expect(tip.g > Double(0x4D) / 255)
        #expect(tip.b > Double(0x55) / 255)
    }
}

struct BiasCutTests {
    @Test func logoLaneEqualizesOnArea() {
        // A typical 3:1 wordmark lands at ~64pt.
        #expect(abs(logoLaneHeight(aspect: 3) - 64) < 1)
        // Wide wordmarks clamp at the floor, stacked lockups at the ceiling.
        #expect(logoLaneHeight(aspect: 10) == 44)
        #expect(logoLaneHeight(aspect: 0.5) == 100)
        // No aspect yet: the default lane.
        #expect(logoLaneHeight(aspect: nil) == 64)
    }

    @Test func artCropWidensWithTheCanvas() {
        #expect(abs(biasCutArtAspect(width: 600) - 4.0 / 3.0) < 0.001)
        #expect(abs(biasCutArtAspect(width: 800) - 2.1) < 0.001)
        #expect(abs(biasCutArtAspect(width: 1200) - 2.6) < 0.001)
    }

    @Test func headHeightIsArtPlusGroundMinusOverlap() {
        let height = biasCutHeight(width: 900, artAspect: 2.1, solidLeft: 100)
        #expect(abs(height - (900 / 2.1 + 100 - 16)) < 0.001)
    }
}

struct WovenAccentTests {
    @Test func neutralAccentIsNotBrandColored() {
        // The pre-decode accent must not flash Ember.
        #expect(WovenAccent.neutral.tint == Color(hexValue: 0x8C96AB))
    }

    @Test func accentFollowsSeedHue() {
        let warm = WovenAccent.from(seed: RGB.fromHSV(h: 30, s: 0.8, v: 0.6))
        let cool = WovenAccent.from(seed: RGB.fromHSV(h: 210, s: 0.8, v: 0.6))
        #expect(warm != cool)
    }
}
